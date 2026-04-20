package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	TS "github.com/metacubex/mihomo/component/tailscale"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
)

const defaultTailscaleAcceptRoutes = true

var tailscaleApplyMu sync.Mutex

func init() {
	setupCrashLog()
	TS.SetProxy(adapter.NewProxy(outbound.NewTailscale()))
}

func setupCrashLog() {
	crashPath := filepath.Join(os.TempDir(), "flclash_crash.log")
	f, err := os.OpenFile(crashPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return
	}
	debug.SetCrashOutput(f, debug.CrashOptions{})
}

func applyTailscale(schema *tailscaleSchema) error {
	startedAt := time.Now()
	config, err := toTailscaleConfig(schema)
	if err != nil {
		return err
	}
	log.Infoln("[TAILSCALE] core apply start: %s", summarizeCoreTailscaleConfig(config))
	if config.Enable && config.Dir != "" {
		logsDir := filepath.Join(config.Dir, "logs")
		if err := os.MkdirAll(logsDir, 0o755); err != nil {
			return fmt.Errorf("create tailscale logs dir: %w", err)
		}
		if err := os.Setenv("TS_LOGS_DIR", logsDir); err != nil {
			return fmt.Errorf("set tailscale logs dir: %w", err)
		}
	}
	if err := TS.ApplyConfig(config); err != nil {
		log.Warnln("[TAILSCALE] core apply failed after %s: %s", time.Since(startedAt).Round(time.Millisecond), err.Error())
		return err
	}
	log.Infoln("[TAILSCALE] core apply finished in %s", time.Since(startedAt).Round(time.Millisecond))
	return nil
}

func closeTailscale() {
	startedAt := time.Now()
	log.Infoln("[TAILSCALE] core close start")
	if err := TS.Close(); err != nil {
		log.Warnln("[TAILSCALE] close error: %s", err.Error())
		return
	}
	log.Infoln("[TAILSCALE] core close finished in %s", time.Since(startedAt).Round(time.Millisecond))
}

func reconnectTailscale() error {
	startedAt := time.Now()
	log.Infoln("[TAILSCALE] core reconnect start")
	if err := TS.Reconnect(); err != nil {
		log.Warnln("[TAILSCALE] core reconnect failed after %s: %s", time.Since(startedAt).Round(time.Millisecond), err.Error())
		return err
	}
	log.Infoln("[TAILSCALE] core reconnect finished in %s", time.Since(startedAt).Round(time.Millisecond))
	return nil
}

func reconnectTailscaleIfEnabled() {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Errorln("[TAILSCALE] panic in reconnectTailscaleIfEnabled: %v", r)
			}
		}()
		snapshot := TS.Snapshot()
		if !snapshot.Enable {
			return
		}
		// Only reconnect when tsnet is fully Running. If it's still Starting,
		// NeedsLogin, NoState, etc., it either hasn't established any connections
		// yet (so nothing to "reconnect") or is in a user-action-required state
		// that reconnect won't fix. Reconnecting a not-yet-Running tsnet would
		// just tear down and restart it for no reason, delaying startup.
		if snapshot.BackendState != "Running" {
			log.Infoln("[TAILSCALE] skip reconnect, backendState=%s", snapshot.BackendState)
			return
		}
		log.Infoln("[TAILSCALE] listener state changed, triggering reconnect")
		tailscaleApplyMu.Lock()
		defer tailscaleApplyMu.Unlock()
		if err := reconnectTailscale(); err != nil {
			log.Warnln("[TAILSCALE] reconnect on listener change: %s", err.Error())
		}
	}()
}

func applyTailscaleAsync(schema *tailscaleSchema) {
	snapshot := cloneTailscaleSchema(schema)
	go func() {
		queuedAt := time.Now()
		defer func() {
			if r := recover(); r != nil {
				log.Errorln("[TAILSCALE] panic in applyTailscale: %v", r)
			}
		}()
		log.Infoln("[TAILSCALE] core async apply queued")
		tailscaleApplyMu.Lock()
		defer tailscaleApplyMu.Unlock()
		log.Infoln("[TAILSCALE] core async apply lock acquired after %s", time.Since(queuedAt).Round(time.Millisecond))

		if err := applyTailscale(snapshot); err != nil {
			log.Warnln("[TAILSCALE] apply config error: %s", err.Error())
		}
	}()
}

func summarizeCoreTailscaleConfig(config TS.Config) string {
	return fmt.Sprintf(
		"enable=%v acceptRoutes=%v dir=%q hostname=%q controlURL=%q authKeySet=%v disabledRoutes=%d",
		config.Enable,
		config.AcceptRoutes,
		config.Dir,
		config.Hostname,
		config.ControlURL,
		strings.TrimSpace(config.AuthKey) != "",
		len(config.DisabledRoutes),
	)
}

func toTailscaleConfig(schema *tailscaleSchema) (TS.Config, error) {
	acceptRoutes := defaultTailscaleAcceptRoutes
	if schema != nil && schema.AcceptRoutes != nil {
		acceptRoutes = *schema.AcceptRoutes
	}

	config := TS.Config{
		Enable:       schema != nil && schema.Enable,
		AcceptRoutes: acceptRoutes,
	}
	if schema != nil && schema.DisabledRoutes != nil {
		config.DisabledRoutes = append([]string(nil), (*schema.DisabledRoutes)...)
	}
	if schema != nil && schema.RouteControlPlaneViaProxy != nil {
		config.RouteControlPlaneViaProxy = *schema.RouteControlPlaneViaProxy
	}
	if schema != nil && schema.RouteDERPViaProxy != nil {
		config.RouteDERPViaProxy = *schema.RouteDERPViaProxy
	}
	if !config.Enable {
		return config, nil
	}

	homeDir := strings.TrimSpace(C.Path.HomeDir())
	if homeDir == "" {
		return TS.Config{}, fmt.Errorf("tailscale home dir is empty")
	}

	stateDir := filepath.Join(homeDir, "tailscale")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		return TS.Config{}, fmt.Errorf("create tailscale state dir: %w", err)
	}

	config.Dir = stateDir
	config.Hostname = trimString(schema.Hostname)
	config.AuthKey = trimString(schema.AuthKey)
	config.ControlURL = trimString(schema.ControlURL)
	return config, nil
}

func trimString(value *string) string {
	if value == nil {
		return ""
	}
	return strings.TrimSpace(*value)
}

func normalizeTailscaleRoutes(values []string) []string {
	routes := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		routes = append(routes, value)
	}
	slices.Sort(routes)
	return routes
}

func cloneTailscaleSchema(schema *tailscaleSchema) *tailscaleSchema {
	if schema == nil {
		return nil
	}

	cloned := *schema
	if schema.AcceptRoutes != nil {
		value := *schema.AcceptRoutes
		cloned.AcceptRoutes = &value
	}
	if schema.Hostname != nil {
		value := *schema.Hostname
		cloned.Hostname = &value
	}
	if schema.AuthKey != nil {
		value := *schema.AuthKey
		cloned.AuthKey = &value
	}
	if schema.ControlURL != nil {
		value := *schema.ControlURL
		cloned.ControlURL = &value
	}
	if schema.DisabledRoutes != nil {
		value := append([]string(nil), (*schema.DisabledRoutes)...)
		cloned.DisabledRoutes = &value
	}
	if schema.RouteControlPlaneViaProxy != nil {
		value := *schema.RouteControlPlaneViaProxy
		cloned.RouteControlPlaneViaProxy = &value
	}
	if schema.RouteDERPViaProxy != nil {
		value := *schema.RouteDERPViaProxy
		cloned.RouteDERPViaProxy = &value
	}
	return &cloned
}
