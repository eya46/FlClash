//go:build android && cgo

package main

import (
	"encoding/json"
	"fmt"
	"net"
	"net/netip"
	"strings"

	"github.com/metacubex/mihomo/log"
	"tailscale.com/net/netmon"
)

type androidNetmonAddr struct {
	Address      string `json:"address"`
	PrefixLength int    `json:"prefixLength"`
}

type androidNetmonInterface struct {
	Index             int                 `json:"index"`
	Name              string              `json:"name"`
	MTU               int                 `json:"mtu"`
	HardwareAddr      string              `json:"hardwareAddr"`
	IsUp              bool                `json:"isUp"`
	IsLoopback        bool                `json:"isLoopback"`
	IsPointToPoint    bool                `json:"isPointToPoint"`
	SupportsMulticast bool                `json:"supportsMulticast"`
	Addrs             []androidNetmonAddr `json:"addrs"`
}

func init() {
	netmon.RegisterInterfaceGetter(androidNetInterfaces)
}

func androidNetInterfaces() ([]netmon.Interface, error) {
	payload := strings.TrimSpace(networkInterfacesJSON())
	if payload == "" {
		return nil, fmt.Errorf("android network interface snapshot is empty")
	}

	var raw []androidNetmonInterface
	if err := json.Unmarshal([]byte(payload), &raw); err != nil {
		return nil, fmt.Errorf("decode android network interfaces: %w", err)
	}

	if len(raw) == 0 {
		return nil, fmt.Errorf("android network interface snapshot returned no interfaces")
	}

	items := make([]netmon.Interface, 0, len(raw))
	for _, item := range raw {
		if strings.TrimSpace(item.Name) == "" {
			continue
		}

		stdIface := &net.Interface{
			Index: item.Index,
			MTU:   item.MTU,
			Name:  strings.TrimSpace(item.Name),
			Flags: androidInterfaceFlags(item),
		}
		if hwAddr := strings.TrimSpace(item.HardwareAddr); hwAddr != "" {
			parsed, err := net.ParseMAC(hwAddr)
			if err == nil {
				stdIface.HardwareAddr = parsed
			}
		}

		addrs := make([]net.Addr, 0, len(item.Addrs))
		for _, addr := range item.Addrs {
			ip := strings.TrimSpace(addr.Address)
			if ip == "" {
				continue
			}
			parsed, err := netip.ParseAddr(ip)
			if err != nil {
				log.Warnln("[TAILSCALE] ignore invalid android interface address %q: %v", ip, err)
				continue
			}
			bitLen := parsed.BitLen()
			if addr.PrefixLength < 0 || addr.PrefixLength > bitLen {
				continue
			}
			addrs = append(addrs, prefixToIPNet(netip.PrefixFrom(parsed, addr.PrefixLength)))
		}

		items = append(items, netmon.Interface{
			Interface: stdIface,
			AltAddrs:  addrs,
		})
	}

	if len(items) == 0 {
		return nil, fmt.Errorf("android network interface snapshot contained no usable interfaces")
	}

	return items, nil
}

func androidInterfaceFlags(item androidNetmonInterface) net.Flags {
	var flags net.Flags
	if item.IsUp {
		flags |= net.FlagUp | net.FlagRunning
	}
	if item.IsLoopback {
		flags |= net.FlagLoopback
	}
	if item.IsPointToPoint {
		flags |= net.FlagPointToPoint
	}
	if item.SupportsMulticast {
		flags |= net.FlagMulticast
	}
	return flags
}

func prefixToIPNet(prefix netip.Prefix) *net.IPNet {
	addr := prefix.Addr().Unmap()
	ip := net.IP(addr.AsSlice())
	if addr.Is4() {
		ip = ip.To4()
	}
	return &net.IPNet{
		IP:   ip,
		Mask: net.CIDRMask(prefix.Bits(), addr.BitLen()),
	}
}
