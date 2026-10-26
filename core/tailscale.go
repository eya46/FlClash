package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/netip"
	"path"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/rules"
	RC "github.com/metacubex/mihomo/rules/common"
	"github.com/metacubex/mihomo/rules/wrapper"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/tailscale/ipn"
	"github.com/metacubex/tailscale/ipn/ipnstate"
	"github.com/metacubex/tailscale/tsnet"
)

// Every enabled tailnet account becomes a mihomo `tailscale` outbound named
// TAILNET-<label>, and the injected rules route through the TAILNET select
// group. One account is one outbound is one state directory: two outbounds on
// one directory are two FileStore writers clobbering each other's state.
const (
	tailnetGroupName       = "TAILNET"
	tailnetLegacyGroupName = "TAILSCALE"
	tailnetNamePrefix      = "TAILNET-"
	tailnetStateRoot       = "tailscale/accounts"
	tailnetFallbackLabel   = "account"
	tailnetStatusTimeout   = 5 * time.Second
	tailnetLoginTimeout    = 30 * time.Second
)

var errTailnetOutboundUnavailable = errors.New("tailscale outbound not available")

// tailnetProxyName derives the outbound name from the account label; the host
// derives the same name when it validates uniqueness.
func tailnetProxyName(label string) string {
	return tailnetNamePrefix + sanitizeTailnetLabel(label)
}

func sanitizeTailnetLabel(label string) string {
	sanitized := strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '_', r == '-':
			return r
		default:
			return '-'
		}
	}, label)
	if sanitized == "" {
		return tailnetFallbackLabel
	}
	return sanitized
}

// tailnetStateDir keeps a migrated account on the pre-v2 directory (the host
// sends "tailscale" explicitly) and files every other account under
// tailscale/accounts/<id>. NewTailscale resolves the value against the mihomo
// home and rejects paths outside it.
func tailnetStateDir(account *tailscaleAccountSchema) string {
	if stateDir := strings.TrimSpace(account.StateDir); stateDir != "" {
		return stateDir
	}
	return path.Join(tailnetStateRoot, sanitizeTailnetLabel(account.ID))
}

// normalizeTailnetDomain strips the trailing dot ipnstate always carries and
// lowercases, so a DOMAIN-SUFFIX literal matches the dotless names mihomo
// resolves. The snapshot output and the injection input share this single
// normalization point.
func normalizeTailnetDomain(domain string) string {
	return strings.ToLower(strings.TrimSuffix(strings.TrimSpace(domain), "."))
}

func tailnetAccounts(schema *tailscaleAccountsSchema) []*tailscaleAccountSchema {
	accounts := []*tailscaleAccountSchema{}
	if schema != nil {
		accounts = schema.Accounts
	}
	enabled := make([]*tailscaleAccountSchema, 0, len(accounts))
	for _, account := range accounts {
		if account != nil && account.Enable {
			enabled = append(enabled, account)
		}
	}
	return enabled
}

// injectTailnet adds the account outbounds, the TAILNET group, the legacy
// TAILSCALE alias group and the front rules to a parsed config. Name clashes
// skip the account rather than the whole config; a broken account must not
// take the profile's proxies down with it.
func injectTailnet(cfg *config.Config, schema *tailscaleAccountsSchema) error {
	if cfg == nil {
		return nil
	}
	var (
		built []C.Proxy
		names []string
		taken = map[string]string{}
	)
	for _, account := range tailnetAccounts(schema) {
		name := tailnetProxyName(account.Label)
		owner, duplicate := taken[name]
		_, profileConflict := cfg.Proxies[name]
		if duplicate || profileConflict {
			reason := "conflicts with a profile proxy"
			if duplicate {
				reason = fmt.Sprintf("already used by account %s", owner)
			}
			log.Infoln("[TAILNET] skip account %s: outbound name %s %s", account.ID, name, reason)
			continue
		}
		taken[name] = account.ID
		proxy, err := newTailnetOutbound(account, name)
		if err != nil {
			log.Infoln("[TAILNET] skip account %s: %v", account.ID, err)
			continue
		}
		cfg.Proxies[name] = proxy
		built = append(built, proxy)
		names = append(names, name)
	}
	if len(built) == 0 {
		return nil
	}
	direct, compatible := cfg.Proxies["DIRECT"], cfg.Proxies["COMPATIBLE"]
	if direct == nil || compatible == nil {
		return errors.New("tailnet injection needs the DIRECT and COMPATIBLE proxies every parsed config carries")
	}
	group, err := newTailnetSelectGroup(tailnetGroupName, append(built, direct), false, compatible)
	if err != nil {
		return err
	}
	cfg.Proxies[tailnetGroupName] = group
	names = append(names, tailnetGroupName)
	if schema.LegacyAlias {
		legacy, err := newTailnetSelectGroup(tailnetLegacyGroupName, []C.Proxy{group}, true, compatible)
		if err != nil {
			return err
		}
		cfg.Proxies[tailnetLegacyGroupName] = legacy
		names = append(names, tailnetLegacyGroupName)
	}
	registerProxyNames(names...)
	cfg.Rules = append(tailnetRules(schema, cfg), cfg.Rules...)
	log.Infoln("[TAILNET] injected %d outbound(s) behind %s", len(built), tailnetGroupName)
	return nil
}

func newTailnetOutbound(account *tailscaleAccountSchema, name string) (C.Proxy, error) {
	acceptRoutes := account.AcceptRoutes
	allowLANAccess := account.ExitNodeAllowLANAccess
	option := outbound.TailscaleOption{
		Name:                   name,
		Hostname:               strings.TrimSpace(account.Hostname),
		AuthKey:                strings.TrimSpace(account.AuthKey),
		ControlURL:             strings.TrimSpace(account.ControlURL),
		StateDir:               tailnetStateDir(account),
		Ephemeral:              account.Ephemeral,
		UDP:                    account.UDP,
		AcceptRoutes:           &acceptRoutes,
		ExitNode:               strings.TrimSpace(account.ExitNode),
		ExitNodeAllowLANAccess: &allowLANAccess,
	}
	option.DialerProxy = strings.TrimSpace(account.DialerProxy)
	proxy, err := outbound.NewTailscale(option)
	if err != nil {
		return nil, fmt.Errorf("build outbound %s: %w", name, err)
	}
	return adapter.NewProxy(proxy), nil
}

// NewSelector reads its members from providers and never from a Proxies list,
// so static members ride a compatible provider — the recipe mihomo's own
// config parsing uses for GLOBAL.
func newTailnetSelectGroup(name string, members []C.Proxy, hidden bool, emptyFallback C.Proxy) (C.Proxy, error) {
	healthCheck := provider.NewHealthCheck(members, "", 5000, 0, true, nil)
	pd, err := provider.NewCompatibleProvider(name, members, healthCheck)
	if err != nil {
		return nil, fmt.Errorf("build provider for group %s: %w", name, err)
	}
	group, err := outboundgroup.NewSelector(
		outboundgroup.GroupCommonOption{Name: name, Hidden: hidden},
		outboundgroup.SelectorOption{},
		emptyFallback,
		[]P.ProxyProvider{pd},
	)
	if err != nil {
		return nil, fmt.Errorf("build group %s: %w", name, err)
	}
	return adapter.NewProxy(group), nil
}

func registerProxyNames(names ...string) {
	list := config.GetProxyNameList()
	for _, name := range names {
		if !sortSearchString(list, name) {
			list = append(list, name)
		}
	}
	config.SetProxyNameList(list)
}

func sortSearchString(list []string, value string) bool {
	for _, item := range list {
		if item == value {
			return true
		}
	}
	return false
}

// tailnetRules builds the front rules in a fixed order: per account (user
// order) extra rules, peer domains, advertised routes, then peer IPs. A
// literal repeated across accounts keeps its first occurrence.
func tailnetRules(schema *tailscaleAccountsSchema, cfg *config.Config) []C.Rule {
	if _, ok := cfg.Proxies[tailnetGroupName]; !ok {
		return nil
	}
	var (
		generated []C.Rule
		cidrs     = map[string]bool{}
		domains   = map[string]bool{}
	)
	for _, account := range tailnetAccounts(schema) {
		for _, line := range account.ExtraRules {
			rule, err := parseTailnetExtraRule(line, cfg)
			if err != nil {
				log.Infoln("[TAILNET] skip extra rule %q: %v", line, err)
				continue
			}
			generated = append(generated, rule)
		}
		for _, domain := range account.PeerDomains {
			domain = normalizeTailnetDomain(domain)
			if domain == "" || domains[domain] {
				continue
			}
			domains[domain] = true
			rule, err := newTailnetRule("DOMAIN-SUFFIX", domain, nil)
			if err != nil {
				log.Infoln("[TAILNET] skip peer domain %q: %v", domain, err)
				continue
			}
			generated = append(generated, rule)
		}
		for _, cidr := range append(append([]string{}, account.RouteCidrs...), account.PeerCidrs...) {
			if cidr == "" || cidrs[cidr] {
				continue
			}
			cidrs[cidr] = true
			rule, err := newTailnetCidrRule(cidr)
			if err != nil {
				log.Infoln("[TAILNET] skip route %q: %v", cidr, err)
				continue
			}
			generated = append(generated, rule)
		}
	}
	return generated
}

func newTailnetCidrRule(cidr string) (C.Rule, error) {
	ruleType := "IP-CIDR"
	if strings.Contains(cidr, ":") {
		ruleType = "IP-CIDR6"
	}
	return newTailnetRule(ruleType, cidr, []string{"no-resolve"})
}

func newTailnetRule(ruleType, payload string, params []string) (C.Rule, error) {
	parsed, err := rules.ParseRule(ruleType, payload, tailnetGroupName, params, nil)
	if err != nil {
		return nil, err
	}
	return wrapper.NewRuleWrapper(parsed), nil
}

// parseTailnetExtraRule validates a full literal the account model carries.
// Post-parse injection bypasses mihomo's parseRules, so an unknown target or
// rule set has to be caught here instead of blowing up at match time.
func parseTailnetExtraRule(line string, cfg *config.Config) (C.Rule, error) {
	ruleType, payload, target, params := RC.ParseRulePayload(strings.TrimSpace(line), true)
	if target == "" {
		return nil, errors.New("missing target")
	}
	if _, ok := cfg.Proxies[target]; !ok {
		return nil, fmt.Errorf("proxy %s not found", target)
	}
	parsed, err := rules.ParseRule(ruleType, payload, target, params, nil)
	if err != nil {
		return nil, err
	}
	for _, name := range parsed.ProviderNames() {
		if _, ok := cfg.RuleProviders[name]; !ok {
			return nil, fmt.Errorf("rule set %s not found", name)
		}
	}
	return wrapper.NewRuleWrapper(parsed), nil
}

// closeTailscale tears every injected node down on shutdown; mihomo closes
// the outbounds it applied itself, this covers the paths where the config was
// never re-applied.
func closeTailscale() {
	for _, proxy := range tunnel.AllProxies() {
		if outboundProxy, ok := proxy.Adapter().(tailscaleOutbound); ok {
			if err := outboundProxy.Close(); err != nil {
				log.Warnln("[TAILNET] close %s: %s", proxy.Name(), err.Error())
			}
		}
	}
}

// closeReplacedTailnet closes the tailnet outbounds a re-apply displaced.
// mihomo swaps its proxy maps without closing the old adapters, so without
// this sweep a replay would leave a second tsnet server writing a state
// directory the replacement also owns.
func closeReplacedTailnet(previous, current map[string]C.Proxy) {
	for name, proxy := range previous {
		outboundProxy, ok := proxy.Adapter().(tailscaleOutbound)
		if !ok || current[name] == proxy {
			continue
		}
		if err := outboundProxy.Close(); err != nil {
			log.Warnln("[TAILNET] close replaced outbound %s: %s", name, err.Error())
		} else {
			log.Infoln("[TAILNET] closed replaced outbound %s", name)
		}
	}
}

// The outbound only carries Server when built with tailscale support
// (with_gvisor and not no_tailscale); the stub build satisfies none of this,
// so the assertion fails and the account reports itself as not available.
type tailscaleOutbound interface {
	Close() error
	Server() *tsnet.Server
}

func findTailscaleOutbound(name string) tailscaleOutbound {
	proxy := tunnel.AllProxies()[name]
	if proxy == nil {
		return nil
	}
	outboundProxy, _ := proxy.Adapter().(tailscaleOutbound)
	return outboundProxy
}

// handleReconnectTailscale re-applies the running config, which rebuilds
// every tailnet outbound; each state directory keeps its node logged in.
func handleReconnectTailscale() error {
	configMu.Lock()
	defer configMu.Unlock()
	if currentSetupParams == nil {
		return fmt.Errorf("tailscale reconnect: config not applied")
	}
	startedAt := time.Now()
	log.Infoln("[TAILNET] core reconnect start")
	err := applyConfigLocked(currentSetupParams)
	if err != nil {
		log.Warnln("[TAILNET] core reconnect failed after %s: %s", time.Since(startedAt).Round(time.Millisecond), err.Error())
		return err
	}
	log.Infoln("[TAILNET] core reconnect finished in %s", time.Since(startedAt).Round(time.Millisecond))
	return nil
}

// handleStartTailscaleLogin restarts interactive login for one account. tsnet
// already starts it on its own in NeedsLogin; this is the explicit path for a
// login that went stale. A Running backend makes it a no-op.
func handleStartTailscaleLogin(params tailnetAccountParams) error {
	account := findTailnetAccount(params.ID)
	if account == nil {
		return fmt.Errorf("tailscale account not found: %s", params.ID)
	}
	proxy := findTailscaleOutbound(tailnetProxyName(account.Label))
	if proxy == nil || proxy.Server() == nil {
		return errTailnetOutboundUnavailable
	}
	ctx, cancel := context.WithTimeout(context.Background(), tailnetLoginTimeout)
	defer cancel()
	client, err := proxy.Server().LocalClient()
	if err != nil {
		return err
	}
	status, err := client.Status(ctx)
	if err == nil && status != nil && status.BackendState == ipn.Running.String() {
		return nil
	}
	return client.StartLoginInteractive(ctx)
}

// handleLogoutTailscale drops one account's node identity; the state
// directory stays on disk, so logging back in reuses the machine key only
// after a fresh interactive login.
func handleLogoutTailscale(params tailnetAccountParams) error {
	account := findTailnetAccount(params.ID)
	if account == nil {
		return fmt.Errorf("tailscale account not found: %s", params.ID)
	}
	proxy := findTailscaleOutbound(tailnetProxyName(account.Label))
	if proxy == nil || proxy.Server() == nil {
		return errTailnetOutboundUnavailable
	}
	ctx, cancel := context.WithTimeout(context.Background(), tailnetLoginTimeout)
	defer cancel()
	client, err := proxy.Server().LocalClient()
	if err != nil {
		return err
	}
	return client.Logout(ctx)
}

func findTailnetAccount(id string) *tailscaleAccountSchema {
	for _, account := range currentTailnetAccounts() {
		if account.ID == id {
			return account
		}
	}
	return nil
}

func currentTailnetAccounts() []*tailscaleAccountSchema {
	configMu.Lock()
	defer configMu.Unlock()
	return currentSetupParams.GetTailnetAccounts()
}

func handleGetTailscaleAccountsState() string {
	data, err := json.Marshal(tailnetAccountsState())
	if err != nil {
		return ""
	}
	return string(data)
}

// tailnetAccountsState snapshots every configured account in parallel: the
// poll drives a LocalClient per account, which starts that account's tsnet
// backend, and one slow backend must not stall the accounts behind it.
func tailnetAccountsState() map[string]any {
	accounts := currentTailnetAccounts()
	views := make([]map[string]any, 0, len(accounts))
	seen := map[string]string{}
	var wg sync.WaitGroup
	for _, account := range accounts {
		if account == nil {
			continue
		}
		view := newTailnetAccountView(account)
		views = append(views, view)
		name := tailnetProxyName(account.Label)
		if owner, duplicate := seen[name]; duplicate {
			view["error"] = fmt.Sprintf("outbound name %s already used by account %s", name, owner)
			continue
		}
		seen[name] = account.ID
		if !account.Enable {
			continue
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			defer func() {
				if r := recover(); r != nil {
					view["error"] = fmt.Sprintf("snapshot panic: %v", r)
				}
			}()
			tailnetAccountStatus(view, name)
		}()
	}
	wg.Wait()
	return map[string]any{"accounts": views}
}

func newTailnetAccountView(account *tailscaleAccountSchema) map[string]any {
	view := map[string]any{
		"id":                account.ID,
		"name":              tailnetProxyName(account.Label),
		"present":           false,
		"backend-state":     "",
		"auth-url":          "",
		"tailnet":           "",
		"magic-dns-suffix":  "",
		"tailscale-ips":     []string{},
		"self-routes":       []string{},
		"peer-count":        0,
		"online-peer-count": 0,
		"peers":             []map[string]any{},
		"error":             "",
	}
	if !tailnetSupported {
		view["error"] = "tailscale not available in this build"
	}
	return view
}

// tailnetAccountStatus fills the view from the live outbound. LocalClient
// starts the account's tsnet backend, which is what the UI poll rides on.
func tailnetAccountStatus(view map[string]any, name string) {
	proxy := findTailscaleOutbound(name)
	if proxy == nil || proxy.Server() == nil {
		if proxy == nil && tunnel.AllProxies()[name] != nil {
			view["error"] = fmt.Sprintf("outbound name %s is taken by a profile proxy", name)
		}
		return
	}
	view["present"] = true
	ctx, cancel := context.WithTimeout(context.Background(), tailnetStatusTimeout)
	defer cancel()
	client, err := proxy.Server().LocalClient()
	if err != nil {
		view["error"] = err.Error()
		return
	}
	status, err := client.Status(ctx)
	if err != nil {
		view["error"] = err.Error()
		return
	}
	if status == nil {
		return
	}
	view["backend-state"] = status.BackendState
	view["auth-url"] = status.AuthURL
	if status.CurrentTailnet != nil {
		view["tailnet"] = status.CurrentTailnet.Name
		view["magic-dns-suffix"] = status.CurrentTailnet.MagicDNSSuffix
	}
	view["tailscale-ips"] = tailnetAddrs(status.TailscaleIPs)
	peers := make([]map[string]any, 0, len(status.Peer))
	online := 0
	for _, peer := range status.Peer {
		if peer == nil {
			continue
		}
		if peer.Online {
			online++
		}
		peers = append(peers, tailnetPeerView(peer))
	}
	sort.Slice(peers, func(i, j int) bool {
		if peers[i]["host-name"].(string) != peers[j]["host-name"].(string) {
			return peers[i]["host-name"].(string) < peers[j]["host-name"].(string)
		}
		return peers[i]["dns-name"].(string) < peers[j]["dns-name"].(string)
	})
	view["peers"] = peers
	view["peer-count"] = len(peers)
	view["online-peer-count"] = online
	if status.Self != nil && status.Self.PrimaryRoutes != nil {
		view["self-routes"] = tailnetPrefixes(status.Self.PrimaryRoutes.AsSlice())
	}
}

// tailnetPeerView renders one peer. PrimaryRoutes is a pointer a routeless
// peer leaves nil, and views.Slice has no nil-safe accessor.
func tailnetPeerView(peer *ipnstate.PeerStatus) map[string]any {
	connection := "idle"
	switch {
	case !peer.Online:
		connection = "offline"
	case peer.CurAddr != "":
		connection = "direct"
	case peer.Relay != "":
		connection = "derp"
	}
	routes := []string{}
	if peer.PrimaryRoutes != nil {
		routes = tailnetPrefixes(peer.PrimaryRoutes.AsSlice())
	}
	return map[string]any{
		"host-name":        peer.HostName,
		"dns-name":         normalizeTailnetDomain(peer.DNSName),
		"tailscale-ips":    tailnetAddrs(peer.TailscaleIPs),
		"primary-routes":   routes,
		"online":           peer.Online,
		"active":           peer.Active,
		"exit-node":        peer.ExitNode,
		"exit-node-option": peer.ExitNodeOption,
		"connection-type":  connection,
		"cur-addr":         peer.CurAddr,
		"relay":            peer.Relay,
		"last-handshake":   formatHandshake(peer.LastHandshake),
		"rx-bytes":         peer.RxBytes,
		"tx-bytes":         peer.TxBytes,
	}
}

func tailnetAddrs(addrs []netip.Addr) []string {
	ips := make([]string, 0, len(addrs))
	for _, addr := range addrs {
		ips = append(ips, addr.String())
	}
	return ips
}

func tailnetPrefixes(prefixes []netip.Prefix) []string {
	routes := make([]string, 0, len(prefixes))
	for _, prefix := range prefixes {
		routes = append(routes, prefix.String())
	}
	sort.Strings(routes)
	return routes
}

func formatHandshake(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.Format(time.RFC3339)
}

func sameTailscaleSchema(a, b *tailscaleAccountsSchema) bool {
	if a == nil || b == nil {
		return a == b
	}
	left, leftErr := json.Marshal(a)
	right, rightErr := json.Marshal(b)
	return leftErr == nil && rightErr == nil && string(left) == string(right)
}

// GetTailscale is nil-safe access to the applied setup's tailnet schema.
func (params *SetupParams) GetTailscale() *tailscaleAccountsSchema {
	if params == nil {
		return nil
	}
	return params.Tailscale
}

// GetTailnetAccounts is nil-safe access to the applied setup's account list.
func (params *SetupParams) GetTailnetAccounts() []*tailscaleAccountSchema {
	if params == nil || params.Tailscale == nil {
		return nil
	}
	return params.Tailscale.Accounts
}
