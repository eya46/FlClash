package core

import (
	"encoding/json"
	"net/netip"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/rules"
	"github.com/metacubex/tailscale/ipn/ipnstate"
	"github.com/metacubex/tailscale/types/views"
)

func withTailnetHome(t *testing.T) {
	t.Helper()
	previous := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	t.Cleanup(func() { C.SetHomeDir(previous) })
}

func parseDefaultTailnetConfig(t *testing.T) *config.Config {
	t.Helper()
	cfg, err := config.ParseRawConfig(config.DefaultRawConfig())
	if err != nil {
		t.Fatalf("ParseRawConfig(default) = %v", err)
	}
	return cfg
}

func tailnetAccount(label string, enable bool) *tailscaleAccountSchema {
	return &tailscaleAccountSchema{ID: "id-" + label, Label: label, Enable: enable, UDP: true}
}

func tailnetSchema(accounts ...*tailscaleAccountSchema) *tailscaleAccountsSchema {
	return &tailscaleAccountsSchema{Accounts: accounts}
}

func proxyNames(proxies []C.Proxy) []string {
	names := make([]string, 0, len(proxies))
	for _, proxy := range proxies {
		names = append(names, proxy.Name())
	}
	return names
}

func ruleSummaries(rules []C.Rule) []string {
	summaries := make([]string, 0, len(rules))
	for _, rule := range rules {
		summaries = append(summaries, rule.RuleType().String()+","+rule.Payload()+","+rule.Adapter())
	}
	return summaries
}

func assertElementsEqual(t *testing.T, name string, got, want []string) {
	t.Helper()
	if strings.Join(got, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("%s = %v, want %v", name, got, want)
	}
}

func TestTailnetProxyNameSanitizesLabel(t *testing.T) {
	cases := map[string]string{
		"work":        "TAILNET-work",
		"a b":         "TAILNET-a-b",
		"home.corp/1": "TAILNET-home-corp-1",
		"":            "TAILNET-account",
		"日本語":         "TAILNET----",
	}
	for label, want := range cases {
		if got := tailnetProxyName(label); got != want {
			t.Errorf("tailnetProxyName(%q) = %q, want %q", label, got, want)
		}
	}
}

func TestTailnetStateDirPassthroughAndDerivation(t *testing.T) {
	migrated := tailnetAccount("work", true)
	migrated.StateDir = "tailscale"
	if got := tailnetStateDir(migrated); got != "tailscale" {
		t.Fatalf("tailnetStateDir(migrated) = %q, want tailscale", got)
	}
	derived := tailnetAccount("work", true)
	derived.ID = "019b;drop/../tables"
	if got, want := tailnetStateDir(derived), "tailscale/accounts/019b-drop----tables"; got != want {
		t.Fatalf("tailnetStateDir(derived) = %q, want %q", got, want)
	}
}

func TestInjectTailnetOutboundsAndGroups(t *testing.T) {
	withTailnetHome(t)
	cfg := parseDefaultTailnetConfig(t)
	primary := tailnetAccount("work", true)
	secondary := &tailscaleAccountSchema{ID: "id-second", Label: "home lan", Enable: true, UDP: true}
	if err := injectTailnet(cfg, tailnetSchema(primary, secondary)); err != nil {
		t.Fatalf("injectTailnet = %v", err)
	}
	for _, name := range []string{"TAILNET-work", "TAILNET-home-lan", tailnetGroupName} {
		if cfg.Proxies[name] == nil {
			t.Fatalf("cfg.Proxies[%s] missing", name)
		}
	}
	if cfg.Proxies[tailnetLegacyGroupName] != nil {
		t.Fatalf("TAILSCALE alias group injected without legacy-alias")
	}
	group, ok := cfg.Proxies[tailnetGroupName].Adapter().(*outboundgroup.Selector)
	if !ok {
		t.Fatalf("TAILNET is a %T, want *outboundgroup.Selector", cfg.Proxies[tailnetGroupName].Adapter())
	}
	// Members ride a compatible provider: the selector sees the account
	// outbounds plus DIRECT, in account order.
	assertElementsEqual(t, "group members", proxyNames(group.Proxies()),
		[]string{"TAILNET-work", "TAILNET-home-lan", "DIRECT"})
	if providers := group.Providers(); len(providers) != 1 {
		t.Fatalf("group providers = %d, want 1", len(providers))
	} else {
		assertElementsEqual(t, "provider proxies", proxyNames(providers[0].Proxies()),
			[]string{"TAILNET-work", "TAILNET-home-lan", "DIRECT"})
	}
	if got := cfg.Proxies[tailnetGroupName].Name(); got != tailnetGroupName {
		t.Fatalf("group name = %q", got)
	}
	registered := config.GetProxyNameList()
	for _, name := range []string{"TAILNET-work", "TAILNET-home-lan", tailnetGroupName} {
		if !sortSearchString(registered, name) {
			t.Errorf("proxy name list misses %s: %v", name, registered)
		}
	}
}

func TestInjectTailnetLegacyAliasGroup(t *testing.T) {
	withTailnetHome(t)
	cfg := parseDefaultTailnetConfig(t)
	schema := tailnetSchema(tailnetAccount("work", true))
	schema.LegacyAlias = true
	if err := injectTailnet(cfg, schema); err != nil {
		t.Fatalf("injectTailnet = %v", err)
	}
	legacy, ok := cfg.Proxies[tailnetLegacyGroupName].Adapter().(*outboundgroup.Selector)
	if !ok {
		t.Fatalf("TAILSCALE alias is a %T, want *outboundgroup.Selector", cfg.Proxies[tailnetLegacyGroupName].Adapter())
	}
	if !legacy.Hidden() {
		t.Error("TAILSCALE alias group is visible, want hidden")
	}
	assertElementsEqual(t, "alias members", proxyNames(legacy.Proxies()), []string{tailnetGroupName})
}

func TestInjectTailnetRulesOrderDedupAndNormalization(t *testing.T) {
	withTailnetHome(t)
	cfg := parseDefaultTailnetConfig(t)
	sentinel, err := rules.ParseRule("IP-CIDR", "198.51.100.7/32", "DIRECT", nil, nil)
	if err != nil {
		t.Fatalf("sentinel rule: %v", err)
	}
	cfg.Rules = append(cfg.Rules, sentinel)
	first := &tailscaleAccountSchema{
		ID: "id-first", Label: "work", Enable: true,
		ExtraRules: []string{
			"DOMAIN-SUFFIX,internal.example.com,TAILNET",
			"DST-PORT,443,NO-SUCH-PROXY",
			"GARBAGE",
		},
		PeerDomains: []string{"Foo.Tail1234.ts.NET.", "bar.tail1234.ts.net"},
		RouteCidrs:  []string{"10.1.0.0/16"},
		PeerCidrs:   []string{"100.101.1.23/32", "fd7a:115c:a1e0::1/128"},
	}
	second := &tailscaleAccountSchema{
		ID: "id-second", Label: "home", Enable: true,
		PeerDomains: []string{"bar.tail1234.ts.net"},
		RouteCidrs:  []string{"10.1.0.0/16"},
		PeerCidrs:   []string{"100.101.1.23/32"},
	}
	if err := injectTailnet(cfg, tailnetSchema(first, second)); err != nil {
		t.Fatalf("injectTailnet = %v", err)
	}
	assertElementsEqual(t, "cfg.Rules", ruleSummaries(cfg.Rules), []string{
		"DomainSuffix,internal.example.com,TAILNET",
		"DomainSuffix,foo.tail1234.ts.net,TAILNET",
		"DomainSuffix,bar.tail1234.ts.net,TAILNET",
		"IPCIDR,10.1.0.0/16,TAILNET",
		"IPCIDR,100.101.1.23/32,TAILNET",
		"IPCIDR,fd7a:115c:a1e0::1/128,TAILNET",
		"IPCIDR,198.51.100.7/32,DIRECT",
	})
}

func TestSameTailscaleAccountsSchema(t *testing.T) {
	base := tailnetSchema(tailnetAccount("work", true))
	if !sameTailscaleSchema(base, tailnetSchema(tailnetAccount("work", true))) {
		t.Error("equal schemas compared different")
	}
	if sameTailscaleSchema(base, tailnetSchema()) {
		t.Error("schema with an account compared equal to empty schema")
	}
	renamed := tailnetSchema(tailnetAccount("work", true))
	renamed.Accounts[0].PeerCidrs = []string{"100.101.1.23/32"}
	if sameTailscaleSchema(base, renamed) {
		t.Error("literal change compared equal")
	}
	if !sameTailscaleSchema(nil, nil) || sameTailscaleSchema(nil, base) || sameTailscaleSchema(base, nil) {
		t.Error("nil comparison broken")
	}
}

func TestInjectTailnetSkipsConflictingNames(t *testing.T) {
	withTailnetHome(t)
	cfg := parseDefaultTailnetConfig(t)
	schema := tailnetSchema(tailnetAccount("a b", true), tailnetAccount("a-b", true))
	if err := injectTailnet(cfg, schema); err != nil {
		t.Fatalf("injectTailnet = %v", err)
	}
	if cfg.Proxies["TAILNET-a-b"] == nil {
		t.Fatal("first account was skipped")
	}
	if group, ok := cfg.Proxies[tailnetGroupName].Adapter().(*outboundgroup.Selector); !ok {
		t.Fatalf("TAILNET missing after duplicate skip: %T", cfg.Proxies[tailnetGroupName].Adapter())
	} else {
		assertElementsEqual(t, "group members", proxyNames(group.Proxies()), []string{"TAILNET-a-b", "DIRECT"})
	}

	cfg = parseDefaultTailnetConfig(t)
	cfg.Proxies["TAILNET-taken"] = cfg.Proxies["DIRECT"]
	if err := injectTailnet(cfg, tailnetSchema(tailnetAccount("taken", true))); err != nil {
		t.Fatalf("injectTailnet = %v", err)
	}
	if cfg.Proxies[tailnetGroupName] != nil {
		t.Error("TAILNET group injected although every account was skipped")
	}
}

func TestInjectTailnetNoEnabledAccountsInjectsNothing(t *testing.T) {
	withTailnetHome(t)
	cfg := parseDefaultTailnetConfig(t)
	if err := injectTailnet(cfg, tailnetSchema(tailnetAccount("work", false))); err != nil {
		t.Fatalf("injectTailnet = %v", err)
	}
	if cfg.Proxies[tailnetGroupName] != nil || cfg.Proxies["TAILNET-work"] != nil {
		t.Fatal("disabled account injected something")
	}
	if len(cfg.Rules) != 0 {
		t.Fatalf("rules injected for disabled account: %v", ruleSummaries(cfg.Rules))
	}
	if err := injectTailnet(cfg, nil); err != nil {
		t.Fatalf("injectTailnet(nil schema) = %v", err)
	}
}

func TestTailnetPeerViewNormalizesDNSName(t *testing.T) {
	peer := &ipnstate.PeerStatus{
		HostName:      "Foo-Device",
		DNSName:       "Foo.Tail1234.ts.NET.",
		TailscaleIPs:  []netip.Addr{netip.MustParseAddr("100.101.1.23")},
		PrimaryRoutes: nil,
		Online:        true,
		CurAddr:       "10.0.0.5:1234",
	}
	view := tailnetPeerView(peer)
	if got := view["dns-name"]; got != "foo.tail1234.ts.net" {
		t.Errorf("dns-name = %v, want foo.tail1234.ts.net", got)
	}
	if got := view["connection-type"]; got != "direct" {
		t.Errorf("connection-type = %v, want direct", got)
	}
	routes, ok := view["primary-routes"].([]string)
	if !ok || len(routes) != 0 {
		t.Errorf("primary-routes = %#v, want empty non-nil slice", view["primary-routes"])
	}
	routed := &ipnstate.PeerStatus{
		PrimaryRoutes: &[]views.Slice[netip.Prefix]{
			views.SliceOf([]netip.Prefix{
				netip.MustParsePrefix("10.2.0.0/16"),
				netip.MustParsePrefix("10.1.0.0/16"),
			}),
		}[0],
	}
	view = tailnetPeerView(routed)
	assertElementsEqual(t, "primary-routes", view["primary-routes"].([]string),
		[]string{"10.1.0.0/16", "10.2.0.0/16"})
}

func TestHandleGetTailscaleAccountsStateEmpty(t *testing.T) {
	configMu.Lock()
	previous := currentSetupParams
	currentSetupParams = nil
	configMu.Unlock()
	t.Cleanup(func() {
		configMu.Lock()
		currentSetupParams = previous
		configMu.Unlock()
	})

	var payload struct {
		Accounts []map[string]any `json:"accounts"`
	}
	if err := json.Unmarshal([]byte(handleGetTailscaleAccountsState()), &payload); err != nil {
		t.Fatalf("accounts state is not valid JSON: %v", err)
	}
	if payload.Accounts == nil || len(payload.Accounts) != 0 {
		t.Fatalf("accounts = %#v, want empty non-nil array", payload.Accounts)
	}
}

func TestHandleGetTailscaleAccountsStateReportsAccounts(t *testing.T) {
	disabled := tailnetAccount("work", false)
	duplicateA := tailnetAccount("a b", true)
	duplicateB := tailnetAccount("a-b", true)
	configMu.Lock()
	previous := currentSetupParams
	currentSetupParams = &SetupParams{Tailscale: tailnetSchema(disabled, duplicateA, duplicateB)}
	configMu.Unlock()
	t.Cleanup(func() {
		configMu.Lock()
		currentSetupParams = previous
		configMu.Unlock()
	})

	var payload struct {
		Accounts []struct {
			ID      string `json:"id"`
			Name    string `json:"name"`
			Present bool   `json:"present"`
			Error   string `json:"error"`
		} `json:"accounts"`
	}
	if err := json.Unmarshal([]byte(handleGetTailscaleAccountsState()), &payload); err != nil {
		t.Fatalf("accounts state is not valid JSON: %v", err)
	}
	if len(payload.Accounts) != 3 {
		t.Fatalf("accounts = %d entries, want 3", len(payload.Accounts))
	}
	for i, want := range map[int]string{0: "", 1: "", 2: "outbound name TAILNET-a-b already used by account id-a b"} {
		if payload.Accounts[i].Error != want {
			t.Errorf("account %d error = %q, want %q", i, payload.Accounts[i].Error, want)
		}
		if payload.Accounts[i].Present {
			t.Errorf("account %d present, want absent (no config applied in this test)", i)
		}
	}
}
