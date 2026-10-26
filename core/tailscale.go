package core

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"sort"
	"strings"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/tailscale/ipn/ipnstate"
	"github.com/metacubex/tailscale/tsnet"
)

// The Tailscale node runs as a mihomo outbound of the official `tailscale`
// type, so profiles reference it by this name in groups and rules. Anything
// the outbound does not model (disabled-routes, the control-plane and DERP
// bypass toggles of the old in-tree manager) has no effect here.
const tailscaleProxyName = "TAILSCALE"

func setupCrashLog() {
	crashPath := filepath.Join(os.TempDir(), "flclash_crash.log")
	f, err := os.OpenFile(crashPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return
	}
	debug.SetCrashOutput(f, debug.CrashOptions{})
}

func init() {
	setupCrashLog()
}

// injectTailscaleProxy adds the FlClash-managed Tailscale outbound to the
// parsed config before it is applied, keeping the node's state in
// <home>/tailscale as before. The tsnet server starts when mihomo dials the
// proxy or resolves its DNS client.
func injectTailscaleProxy(cfg *config.Config, schema *tailscaleSchema) error {
	if cfg == nil || schema == nil || !schema.Enable {
		return nil
	}
	option := outbound.TailscaleOption{
		UDP: true,
	}
	option.Name = tailscaleProxyName
	option.Hostname = trimString(schema.Hostname)
	option.AuthKey = trimString(schema.AuthKey)
	option.ControlURL = trimString(schema.ControlURL)
	if schema.AcceptRoutes != nil {
		option.AcceptRoutes = schema.AcceptRoutes
	}
	proxy, err := outbound.NewTailscale(option)
	if err != nil {
		return fmt.Errorf("build tailscale outbound: %w", err)
	}
	cfg.Proxies[tailscaleProxyName] = adapter.NewProxy(proxy)
	names := config.GetProxyNameList()
	if !sortSearchString(names, tailscaleProxyName) {
		config.SetProxyNameList(append(names, tailscaleProxyName))
	}
	log.Infoln("[TAILSCALE] outbound %s injected (acceptRoutes=%v)", tailscaleProxyName, schema.AcceptRoutes != nil && *schema.AcceptRoutes)
	return nil
}

func sortSearchString(list []string, value string) bool {
	for _, item := range list {
		if item == value {
			return true
		}
	}
	return false
}

func trimString(value *string) string {
	if value == nil {
		return ""
	}
	return strings.TrimSpace(*value)
}

// closeTailscale tears the node down on shutdown; mihomo closes the outbound
// itself too, this covers the paths where the config was never re-applied.
func closeTailscale() {
	proxy := findTailscaleOutbound()
	if proxy == nil {
		return
	}
	startedAt := time.Now()
	log.Infoln("[TAILSCALE] core close start")
	if err := proxy.Close(); err != nil {
		log.Warnln("[TAILSCALE] close error: %s", err.Error())
		return
	}
	log.Infoln("[TAILSCALE] core close finished in %s", time.Since(startedAt).Round(time.Millisecond))
}

// The outbound only carries Server when built with tailscale support
// (with_gvisor and not no_tailscale); the stub build satisfies none of this,
// so the assertion fails and the state falls back to "not available".
type tailscaleOutbound interface {
	Close() error
	Server() *tsnet.Server
}

func findTailscaleOutbound() tailscaleOutbound {
	for _, proxy := range tunnel.AllProxies() {
		outboundProxy, ok := proxy.Adapter().(tailscaleOutbound)
		if ok {
			return outboundProxy
		}
	}
	return nil
}

// handleReconnectTailscale re-applies the running config, which rebuilds the
// Tailscale outbound and its tsnet server; the state directory keeps the node
// logged in, so this is the reconnect the UI asks for.
func handleReconnectTailscale() error {
	configMu.Lock()
	defer configMu.Unlock()
	if currentSetupParams == nil {
		return fmt.Errorf("tailscale reconnect: config not applied")
	}
	startedAt := time.Now()
	log.Infoln("[TAILSCALE] core reconnect start")
	err := applyConfigLocked(currentSetupParams)
	if err != nil {
		log.Warnln("[TAILSCALE] core reconnect failed after %s: %s", time.Since(startedAt).Round(time.Millisecond), err.Error())
		return err
	}
	log.Infoln("[TAILSCALE] core reconnect finished in %s", time.Since(startedAt).Round(time.Millisecond))
	return nil
}

func handleGetTailscaleState() string {
	data, err := json.Marshal(tailscaleSnapshot())
	if err != nil {
		return ""
	}
	return string(data)
}

func tailscaleEnabled() bool {
	if currentSetupParams == nil || currentSetupParams.Tailscale == nil {
		return false
	}
	return currentSetupParams.Tailscale.Enable
}

func tailscaleSnapshot() map[string]any {
	state := map[string]any{
		"enable":            tailscaleEnabled(),
		"backend-state":     "NeedsLogin",
		"auth-url":          "",
		"tailscale-ips":     []string{},
		"routes":            []string{},
		"tailnet":           "",
		"magic-dns-suffix":  "",
		"error":             "",
		"peer-count":        0,
		"online-peer-count": 0,
		"last-handshake":    "",
		"peers":             []map[string]any{},
		"derp":              []map[string]any{},
	}
	if currentSetupParams != nil && currentSetupParams.Tailscale != nil {
		schema := currentSetupParams.Tailscale
		state["accept-routes"] = schema.AcceptRoutes != nil && *schema.AcceptRoutes
		if schema.DisabledRoutes != nil {
			routes := make([]string, 0, len(*schema.DisabledRoutes))
			for _, route := range *schema.DisabledRoutes {
				if route = strings.TrimSpace(route); route != "" {
					routes = append(routes, route)
				}
			}
			sort.Strings(routes)
			state["disabled-routes"] = routes
		}
	}

	proxy := findTailscaleOutbound()
	if proxy == nil {
		if !tailscaleEnabled() {
			state["backend-state"] = ""
		}
		return state
	}
	server := proxy.Server()
	if server == nil {
		return state
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	client, err := server.LocalClient()
	if err != nil {
		state["error"] = err.Error()
		return state
	}
	status, err := client.Status(ctx)
	if err != nil {
		state["error"] = err.Error()
		return state
	}
	if status == nil {
		return state
	}

	state["backend-state"] = status.BackendState
	state["auth-url"] = status.AuthURL
	if status.CurrentTailnet != nil {
		state["tailnet"] = status.CurrentTailnet.Name
		state["magic-dns-suffix"] = status.CurrentTailnet.MagicDNSSuffix
	}
	ips := make([]string, 0, len(status.TailscaleIPs))
	for _, addr := range status.TailscaleIPs {
		ips = append(ips, addr.String())
	}
	state["tailscale-ips"] = ips

	peers := make([]map[string]any, 0, len(status.Peer))
	online := 0
	var lastHandshake time.Time
	for _, peer := range status.Peer {
		if peer == nil {
			continue
		}
		if peer.Online {
			online++
		}
		if peer.LastHandshake.After(lastHandshake) {
			lastHandshake = peer.LastHandshake
		}
		peers = append(peers, peerView(peer))
	}
	sort.Slice(peers, func(i, j int) bool {
		return peers[i]["host-name"].(string) < peers[j]["host-name"].(string)
	})
	state["peers"] = peers
	state["peer-count"] = len(peers)
	state["online-peer-count"] = online
	state["last-handshake"] = formatHandshake(lastHandshake)

	if status.Self != nil {
		routes := make([]string, 0, len(status.Self.PrimaryRoutes.AsSlice()))
		for _, prefix := range status.Self.PrimaryRoutes.AsSlice() {
			routes = append(routes, prefix.String())
		}
		sort.Strings(routes)
		state["routes"] = routes
	}
	return state
}

func peerView(peer *ipnstate.PeerStatus) map[string]any {
	connection := "idle"
	switch {
	case !peer.Online:
		connection = "offline"
	case peer.CurAddr != "":
		connection = "direct"
	case peer.Relay != "":
		connection = "derp"
	}
	ips := make([]string, 0, len(peer.TailscaleIPs))
	for _, addr := range peer.TailscaleIPs {
		ips = append(ips, addr.String())
	}
	routes := make([]string, 0, len(peer.PrimaryRoutes.AsSlice()))
	for _, prefix := range peer.PrimaryRoutes.AsSlice() {
		routes = append(routes, prefix.String())
	}
	return map[string]any{
		"host-name":        peer.HostName,
		"dns-name":         peer.DNSName,
		"tailscale-ips":    ips,
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

func formatHandshake(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.Format(time.RFC3339)
}

func sameTailscaleSchema(a, b *tailscaleSchema) bool {
	if a == nil || b == nil {
		return a == b
	}
	left, leftErr := json.Marshal(a)
	right, rightErr := json.Marshal(b)
	return leftErr == nil && rightErr == nil && string(left) == string(right)
}

// GetTailscale is nil-safe access to the applied setup's Tailscale schema.
func (params *SetupParams) GetTailscale() *tailscaleSchema {
	if params == nil {
		return nil
	}
	return params.Tailscale
}
