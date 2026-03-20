package netops

import (
	"context"
	"encoding/base64"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/parrsi01/securewave/netopsd/internal/rpc"
	"github.com/parrsi01/securewave/netopsd/internal/system"
	"log/slog"
)

var ifacePattern = regexp.MustCompile(`^[a-zA-Z0-9_.-]{1,15}$`)
var tableConfig = map[string]struct {
	Table    string
	FWMark   string
	IIFPrio  string
	MarkPrio string
	NATChain string
}{
	"wireguard": {Table: "100", FWMark: "0x64", IIFPrio: "10100", MarkPrio: "10101", NATChain: "WG_NAT"},
	"openvpn":   {Table: "200", FWMark: "0xc8", IIFPrio: "10200", MarkPrio: "10201", NATChain: "OVPN_NAT"},
	"ikev2":     {Table: "300", FWMark: "0x12c", IIFPrio: "10300", MarkPrio: "10301", NATChain: "IKEV2_NAT"},
}

type Service struct {
	runner system.Runner
	logger *slog.Logger
}

func New(runner system.Runner, logger *slog.Logger) *Service {
	return &Service{runner: runner, logger: logger}
}

func (s *Service) HealthPing(_ context.Context) (rpc.HealthPingResult, error) {
	return rpc.HealthPingResult{Status: "ok"}, nil
}

func (s *Service) NetSetupProtocol(ctx context.Context, p rpc.NetSetupProtocolParams) (map[string]any, error) {
	if err := validateProtocol(p.Protocol); err != nil {
		return nil, err
	}
	if err := validateCIDR(p.SourceCIDR); err != nil {
		return nil, err
	}
	if err := validateInterface(p.TunnelIface); err != nil {
		return nil, err
	}
	if err := validateInterface(p.EgressIface); err != nil {
		return nil, err
	}

	cfg := tableConfig[p.Protocol]
	if err := s.ensureRTTable(ctx, p.Protocol, cfg.Table); err != nil {
		return nil, err
	}
	if _, err := s.runner.Run(ctx, "ip", "-4", "route", "replace", p.SourceCIDR, "dev", p.TunnelIface, "table", cfg.Table); err != nil {
		return nil, err
	}
	if _, err := s.runner.Run(ctx, "ip", "-4", "route", "replace", "default", "dev", p.EgressIface, "table", cfg.Table); err != nil {
		return nil, err
	}
	if recurse, err := s.tableDefaultUsesIface(ctx, cfg.Table, p.TunnelIface); err != nil {
		return nil, err
	} else if recurse {
		return nil, fmt.Errorf("route recursion detected for %s via %s", p.Protocol, p.TunnelIface)
	}
	if err := s.ensureRule(ctx, cfg.IIFPrio, []string{"iif", p.TunnelIface, "lookup", cfg.Table}); err != nil {
		return nil, err
	}
	if err := s.ensureRule(ctx, cfg.MarkPrio, []string{"fwmark", cfg.FWMark, "lookup", cfg.Table}); err != nil {
		return nil, err
	}
	if err := s.enableIPv4Forwarding(ctx); err != nil {
		return nil, err
	}
	if err := s.ensureNAT(ctx, p.Protocol, p.SourceCIDR, p.EgressIface); err != nil {
		return nil, err
	}
	s.logger.Info("net.setup_protocol complete", "protocol", p.Protocol, "tunnel_iface", p.TunnelIface, "egress_iface", p.EgressIface)
	return map[string]any{"status": "ok"}, nil
}

func (s *Service) NetTeardownProtocol(ctx context.Context, p rpc.NetTeardownProtocolParams) (map[string]any, error) {
	if err := validateProtocol(p.Protocol); err != nil {
		return nil, err
	}
	if err := validateCIDR(p.SourceCIDR); err != nil {
		return nil, err
	}
	if err := validateInterface(p.TunnelIface); err != nil {
		return nil, err
	}
	if err := validateInterface(p.EgressIface); err != nil {
		return nil, err
	}
	if p.CleanupXfrmMark != "" && !strings.HasPrefix(strings.ToLower(p.CleanupXfrmMark), "0x") {
		return nil, fmt.Errorf("cleanup_xfrm_mark must be hex mark")
	}

	cfg := tableConfig[p.Protocol]
	if err := s.teardownNAT(ctx, p.Protocol, p.SourceCIDR, p.EgressIface); err != nil {
		return nil, err
	}
	if err := s.removeRule(ctx, cfg.MarkPrio, []string{"fwmark", cfg.FWMark, "lookup", cfg.Table}); err != nil {
		return nil, err
	}
	if err := s.removeRule(ctx, cfg.IIFPrio, []string{"iif", p.TunnelIface, "lookup", cfg.Table}); err != nil {
		return nil, err
	}
	if _, err := s.runner.Run(ctx, "ip", "-4", "route", "flush", "table", cfg.Table); err != nil {
		return nil, err
	}
	if p.CleanupXfrmMark != "" {
		if err := s.cleanupXFRM(ctx, p.CleanupXfrmMark); err != nil {
			return nil, err
		}
	}
	if p.BringLinkDown {
		if _, err := s.runner.Run(ctx, "ip", "link", "set", "dev", p.TunnelIface, "down"); err != nil && !strings.Contains(err.Error(), "Cannot find device") {
			return nil, err
		}
	}
	s.logger.Info("net.teardown_protocol complete", "protocol", p.Protocol, "tunnel_iface", p.TunnelIface)
	return map[string]any{"status": "ok"}, nil
}

func (s *Service) WireGuardCreateInterface(ctx context.Context, p rpc.WireGuardCreateInterfaceParams) (map[string]any, error) {
	if err := validateInterface(p.Interface); err != nil {
		return nil, err
	}
	if _, err := s.runner.Run(ctx, "ip", "link", "add", "dev", p.Interface, "type", "wireguard"); err != nil {
		return nil, err
	}
	return map[string]any{"status": "ok"}, nil
}

func (s *Service) WireGuardDeleteInterface(ctx context.Context, p rpc.WireGuardDeleteInterfaceParams) (map[string]any, error) {
	if err := validateInterface(p.Interface); err != nil {
		return nil, err
	}
	if _, err := s.runner.Run(ctx, "ip", "link", "del", "dev", p.Interface); err != nil && !strings.Contains(err.Error(), "Cannot find device") {
		return nil, err
	}
	return map[string]any{"status": "ok"}, nil
}

func (s *Service) WireGuardSetMTU(ctx context.Context, p rpc.WireGuardSetMTUParams) (map[string]any, error) {
	if err := validateInterface(p.Interface); err != nil {
		return nil, err
	}
	if p.MTU < 576 || p.MTU > 9000 {
		return nil, fmt.Errorf("mtu out of range")
	}
	if _, err := s.runner.Run(ctx, "ip", "link", "set", "dev", p.Interface, "mtu", strconv.Itoa(p.MTU)); err != nil {
		return nil, err
	}
	return map[string]any{"status": "ok"}, nil
}

func (s *Service) WireGuardAssignAddress(ctx context.Context, p rpc.WireGuardAddressParams) (map[string]any, error) {
	if err := validateInterface(p.Interface); err != nil {
		return nil, err
	}
	for _, addr := range p.Addresses {
		if err := validateCIDR(addr); err != nil {
			return nil, err
		}
		if _, err := s.runner.Run(ctx, "ip", "address", "replace", addr, "dev", p.Interface); err != nil {
			return nil, err
		}
	}
	return map[string]any{"status": "ok"}, nil
}

func (s *Service) WireGuardSetLinkState(ctx context.Context, p rpc.WireGuardLinkParams) (map[string]any, error) {
	if err := validateInterface(p.Interface); err != nil {
		return nil, err
	}
	if p.State != "up" && p.State != "down" {
		return nil, fmt.Errorf("invalid link state")
	}
	if _, err := s.runner.Run(ctx, "ip", "link", "set", "dev", p.Interface, p.State); err != nil {
		return nil, err
	}
	return map[string]any{"status": "ok"}, nil
}

func (s *Service) WireGuardApplyConfig(ctx context.Context, p rpc.WireGuardApplyConfigParams) (map[string]any, error) {
	if err := validateInterface(p.Interface); err != nil {
		return nil, err
	}
	if err := validateWGKey(p.PrivateKey); err != nil {
		return nil, fmt.Errorf("private_key: %w", err)
	}
	for _, peer := range p.Peers {
		if err := validateWGKey(peer.PublicKey); err != nil {
			return nil, fmt.Errorf("peer public_key: %w", err)
		}
		if peer.PresharedKey != "" {
			if err := validateWGKey(peer.PresharedKey); err != nil {
				return nil, fmt.Errorf("peer preshared_key: %w", err)
			}
		}
		if peer.Endpoint != "" {
			if err := validateEndpoint(peer.Endpoint); err != nil {
				return nil, fmt.Errorf("peer endpoint: %w", err)
			}
		}
		if peer.PersistentKeepalive < 0 || peer.PersistentKeepalive > 65535 {
			return nil, fmt.Errorf("persistent_keepalive out of range")
		}
		for _, cidr := range peer.AllowedIPs {
			if err := validateCIDR(cidr); err != nil {
				return nil, fmt.Errorf("peer allowed_ips: %w", err)
			}
		}
	}
	if p.ListenPort < 0 || p.ListenPort > 65535 {
		return nil, fmt.Errorf("listen_port out of range")
	}

	tmpDir, err := os.MkdirTemp("", "securewave-netd-*")
	if err != nil {
		return nil, fmt.Errorf("mktemp: %w", err)
	}
	defer os.RemoveAll(tmpDir)
	confPath := filepath.Join(tmpDir, "wg.conf")
	if err := os.WriteFile(confPath, []byte(buildWGConfig(p)), 0o600); err != nil {
		return nil, fmt.Errorf("write config: %w", err)
	}
	if _, err := s.runner.Run(ctx, "wg", "setconf", p.Interface, confPath); err != nil {
		return nil, err
	}
	return map[string]any{"status": "ok"}, nil
}

func (s *Service) WireGuardStatus(ctx context.Context, p rpc.WireGuardStatusParams) (rpc.WireGuardStatusResult, error) {
	if err := validateInterface(p.Interface); err != nil {
		return rpc.WireGuardStatusResult{}, err
	}
	result := rpc.WireGuardStatusResult{Interface: p.Interface}
	if _, err := s.runner.Run(ctx, "ip", "link", "show", "dev", p.Interface); err != nil {
		if strings.Contains(err.Error(), "Cannot find device") {
			return result, nil
		}
		return result, err
	}
	result.Exists = true
	linkOut, err := s.runner.Run(ctx, "ip", "link", "show", "dev", p.Interface)
	if err != nil {
		return result, err
	}
	result.LinkUp = strings.Contains(linkOut, " state UP ")
	addrOut, err := s.runner.Run(ctx, "ip", "-o", "address", "show", "dev", p.Interface)
	if err == nil {
		for _, line := range strings.Split(addrOut, "\n") {
			fields := strings.Fields(line)
			if len(fields) >= 4 {
				result.Addresses = append(result.Addresses, fields[3])
			}
		}
	}
	wgDump, err := s.runner.Run(ctx, "wg", "show", p.Interface, "dump")
	if err == nil {
		result.WGDump = wgDump
	}
	return result, nil
}

func (s *Service) RouteAdd(ctx context.Context, p rpc.RouteAddParams) (map[string]any, error) {
	if err := validateCIDR(p.Destination); err != nil {
		return nil, err
	}
	args := []string{"-4", "route"}
	if p.Replace {
		args = append(args, "replace")
	} else {
		args = append(args, "add")
	}
	args = append(args, p.Destination)
	if p.Via != "" {
		if ip := net.ParseIP(p.Via); ip == nil {
			return nil, fmt.Errorf("invalid via IP")
		}
		args = append(args, "via", p.Via)
	}
	if p.Dev != "" {
		if err := validateInterface(p.Dev); err != nil {
			return nil, err
		}
		args = append(args, "dev", p.Dev)
	}
	if p.Table != "" {
		args = append(args, "table", p.Table)
	}
	if _, err := s.runner.Run(ctx, "ip", args...); err != nil {
		return nil, err
	}
	return map[string]any{"status": "ok"}, nil
}

func (s *Service) RouteDelete(ctx context.Context, p rpc.RouteDeleteParams) (map[string]any, error) {
	if err := validateCIDR(p.Destination); err != nil {
		return nil, err
	}
	args := []string{"-4", "route", "del", p.Destination}
	if p.Via != "" {
		if ip := net.ParseIP(p.Via); ip == nil {
			return nil, fmt.Errorf("invalid via IP")
		}
		args = append(args, "via", p.Via)
	}
	if p.Dev != "" {
		if err := validateInterface(p.Dev); err != nil {
			return nil, err
		}
		args = append(args, "dev", p.Dev)
	}
	if p.Table != "" {
		args = append(args, "table", p.Table)
	}
	if _, err := s.runner.Run(ctx, "ip", args...); err != nil && !strings.Contains(err.Error(), "No such process") {
		return nil, err
	}
	return map[string]any{"status": "ok"}, nil
}

func (s *Service) VpnCleanup(ctx context.Context, p rpc.VpnCleanupParams) (map[string]any, error) {
	return s.NetTeardownProtocol(ctx, rpc.NetTeardownProtocolParams{
		Protocol:        p.Protocol,
		SourceCIDR:      p.SourceCIDR,
		TunnelIface:     p.TunnelIface,
		EgressIface:     p.EgressIface,
		BringLinkDown:   true,
		CleanupXfrmMark: p.CleanupXfrmMark,
	})
}

func (s *Service) OpenVPNStub(_ context.Context) (map[string]any, error) {
	return nil, fmt.Errorf("openvpn operations are not implemented in securewave-netd yet")
}

func (s *Service) IKEv2Stub(_ context.Context) (map[string]any, error) {
	return nil, fmt.Errorf("ikev2 operations are not implemented in securewave-netd yet")
}

func validateProtocol(protocol string) error {
	if _, ok := tableConfig[protocol]; !ok {
		return fmt.Errorf("unsupported protocol %q", protocol)
	}
	return nil
}

func validateInterface(name string) error {
	if !ifacePattern.MatchString(name) {
		return fmt.Errorf("invalid interface name")
	}
	return nil
}

func validateCIDR(value string) error {
	if _, _, err := net.ParseCIDR(value); err != nil {
		return fmt.Errorf("invalid CIDR %q", value)
	}
	return nil
}

func validateEndpoint(endpoint string) error {
	host, port, err := net.SplitHostPort(endpoint)
	if err != nil {
		return fmt.Errorf("invalid endpoint")
	}
	if host == "" {
		return fmt.Errorf("endpoint host missing")
	}
	portNum, err := strconv.Atoi(port)
	if err != nil || portNum < 1 || portNum > 65535 {
		return fmt.Errorf("invalid endpoint port")
	}
	return nil
}

func validateWGKey(value string) error {
	decoded, err := base64.StdEncoding.DecodeString(value)
	if err != nil {
		return fmt.Errorf("invalid base64 key")
	}
	if len(decoded) != 32 {
		return fmt.Errorf("unexpected key length")
	}
	return nil
}

func buildWGConfig(p rpc.WireGuardApplyConfigParams) string {
	var b strings.Builder
	b.WriteString("[Interface]\n")
	b.WriteString(fmt.Sprintf("PrivateKey = %s\n", p.PrivateKey))
	if p.ListenPort > 0 {
		b.WriteString(fmt.Sprintf("ListenPort = %d\n", p.ListenPort))
	}
	if p.FirewallMark != "" {
		b.WriteString(fmt.Sprintf("FwMark = %s\n", p.FirewallMark))
	}
	for _, peer := range p.Peers {
		b.WriteString("\n[Peer]\n")
		b.WriteString(fmt.Sprintf("PublicKey = %s\n", peer.PublicKey))
		if peer.PresharedKey != "" {
			b.WriteString(fmt.Sprintf("PresharedKey = %s\n", peer.PresharedKey))
		}
		if peer.Endpoint != "" {
			b.WriteString(fmt.Sprintf("Endpoint = %s\n", peer.Endpoint))
		}
		if len(peer.AllowedIPs) > 0 {
			b.WriteString(fmt.Sprintf("AllowedIPs = %s\n", strings.Join(peer.AllowedIPs, ", ")))
		}
		if peer.PersistentKeepalive > 0 {
			b.WriteString(fmt.Sprintf("PersistentKeepalive = %d\n", peer.PersistentKeepalive))
		}
	}
	return b.String()
}

func (s *Service) ensureRTTable(ctx context.Context, protocol, table string) error {
	entry := table + " " + protocol
	content, err := os.ReadFile("/etc/iproute2/rt_tables")
	if err != nil {
		return fmt.Errorf("read rt_tables: %w", err)
	}
	if strings.Contains(string(content), entry) {
		return nil
	}
	f, err := os.OpenFile("/etc/iproute2/rt_tables", os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		return fmt.Errorf("open rt_tables: %w", err)
	}
	defer f.Close()
	if _, err := f.WriteString("\n" + entry + "\n"); err != nil {
		return fmt.Errorf("append rt_tables: %w", err)
	}
	return nil
}

func (s *Service) tableDefaultUsesIface(ctx context.Context, table, iface string) (bool, error) {
	out, err := s.runner.Run(ctx, "ip", "-4", "route", "show", "table", table, "default")
	if err != nil && !strings.Contains(err.Error(), "FIB table does not exist") {
		return false, err
	}
	return strings.Contains(out, "dev "+iface), nil
}

func (s *Service) ensureRule(ctx context.Context, priority string, args []string) error {
	show, err := s.runner.Run(ctx, "ip", "-4", "rule", "show")
	if err != nil {
		return err
	}
	wantTokens := append([]string{"priority " + priority}, args...)
	for _, line := range strings.Split(show, "\n") {
		matched := true
		for _, token := range wantTokens {
			if !strings.Contains(line, token) {
				matched = false
				break
			}
		}
		if matched {
			return nil
		}
	}
	runArgs := append([]string{"-4", "rule", "add", "priority", priority}, args...)
	_, err = s.runner.Run(ctx, "ip", runArgs...)
	return err
}

func (s *Service) removeRule(ctx context.Context, priority string, args []string) error {
	show, err := s.runner.Run(ctx, "ip", "-4", "rule", "show")
	if err != nil {
		return err
	}
	wantTokens := append([]string{"priority " + priority}, args...)
	for _, line := range strings.Split(show, "\n") {
		matched := true
		for _, token := range wantTokens {
			if !strings.Contains(line, token) {
				matched = false
				break
			}
		}
		if matched {
			runArgs := append([]string{"-4", "rule", "del", "priority", priority}, args...)
			if _, err := s.runner.Run(ctx, "ip", runArgs...); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Service) enableIPv4Forwarding(ctx context.Context) error {
	out, err := s.runner.Run(ctx, "sysctl", "-n", "net.ipv4.ip_forward")
	if err != nil {
		return err
	}
	if strings.TrimSpace(out) == "1" {
		return nil
	}
	_, err = s.runner.Run(ctx, "sysctl", "-w", "net.ipv4.ip_forward=1")
	return err
}

func (s *Service) ensureNAT(ctx context.Context, protocol, sourceCIDR, egressIface string) error {
	cfg := tableConfig[protocol]
	if _, err := s.runner.Run(ctx, "iptables", "-t", "nat", "-S", cfg.NATChain); err != nil {
		if _, err := s.runner.Run(ctx, "iptables", "-t", "nat", "-N", cfg.NATChain); err != nil {
			return err
		}
	}
	masqRule := []string{"-s", sourceCIDR, "-o", egressIface, "-m", "comment", "--comment", "sw:" + protocol + ":masq", "-j", "MASQUERADE"}
	if !s.iptablesRuleExists(ctx, "nat", cfg.NATChain, masqRule...) {
		if _, err := s.runner.Run(ctx, "iptables", append([]string{"-t", "nat", "-A", cfg.NATChain}, masqRule...)...); err != nil {
			return err
		}
	}
	hookRule := []string{"-m", "comment", "--comment", "sw:" + protocol + ":hook", "-j", cfg.NATChain}
	if !s.iptablesRuleExists(ctx, "nat", "POSTROUTING", hookRule...) {
		if _, err := s.runner.Run(ctx, "iptables", append([]string{"-t", "nat", "-I", "POSTROUTING", "1"}, hookRule...)...); err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) teardownNAT(ctx context.Context, protocol, sourceCIDR, egressIface string) error {
	cfg := tableConfig[protocol]
	hookRule := []string{"-m", "comment", "--comment", "sw:" + protocol + ":hook", "-j", cfg.NATChain}
	masqRule := []string{"-s", sourceCIDR, "-o", egressIface, "-m", "comment", "--comment", "sw:" + protocol + ":masq", "-j", "MASQUERADE"}
	for s.iptablesRuleExists(ctx, "nat", "POSTROUTING", hookRule...) {
		if _, err := s.runner.Run(ctx, "iptables", append([]string{"-t", "nat", "-D", "POSTROUTING"}, hookRule...)...); err != nil {
			return err
		}
	}
	for s.iptablesRuleExists(ctx, "nat", cfg.NATChain, masqRule...) {
		if _, err := s.runner.Run(ctx, "iptables", append([]string{"-t", "nat", "-D", cfg.NATChain}, masqRule...)...); err != nil {
			return err
		}
	}
	chainDump, err := s.runner.Run(ctx, "iptables", "-t", "nat", "-S", cfg.NATChain)
	if err == nil {
		ownedEntries := 0
		for _, line := range strings.Split(chainDump, "\n") {
			if strings.HasPrefix(line, "-A ") {
				ownedEntries++
			}
		}
		if ownedEntries == 0 {
			if _, err := s.runner.Run(ctx, "iptables", "-t", "nat", "-X", cfg.NATChain); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Service) iptablesRuleExists(ctx context.Context, table, chain string, rule ...string) bool {
	args := append([]string{"-t", table, "-C", chain}, rule...)
	_, err := s.runner.Run(ctx, "iptables", args...)
	return err == nil
}

func (s *Service) cleanupXFRM(ctx context.Context, mark string) error {
	stateList, err := s.runner.Run(ctx, "ip", "xfrm", "state", "list")
	if err == nil {
		for _, block := range splitBlocks(stateList) {
			if !strings.Contains(strings.ToLower(block), "mark "+strings.ToLower(mark)) {
				continue
			}
			src, dst, proto, spi := parseXfrmState(block)
			if src == "" || dst == "" || proto == "" || spi == "" {
				continue
			}
			if _, err := s.runner.Run(ctx, "ip", "xfrm", "state", "delete", "src", src, "dst", dst, "proto", proto, "spi", spi); err != nil {
				return err
			}
		}
	}
	policyList, err := s.runner.Run(ctx, "ip", "xfrm", "policy", "list")
	if err == nil {
		for _, block := range splitBlocks(policyList) {
			if !strings.Contains(strings.ToLower(block), "mark "+strings.ToLower(mark)) {
				continue
			}
			index, dir := parseXfrmPolicy(block)
			if index == "" || dir == "" {
				continue
			}
			if _, err := s.runner.Run(ctx, "ip", "xfrm", "policy", "delete", "index", index, "dir", dir); err != nil {
				return err
			}
		}
	}
	return nil
}

func splitBlocks(raw string) []string {
	parts := strings.Split(raw, "\n\n")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		if strings.TrimSpace(part) != "" {
			out = append(out, part)
		}
	}
	return out
}

func parseXfrmState(block string) (src, dst, proto, spi string) {
	fields := strings.Fields(block)
	for i := 0; i < len(fields)-1; i++ {
		switch fields[i] {
		case "src":
			src = fields[i+1]
		case "dst":
			dst = fields[i+1]
		case "proto":
			proto = fields[i+1]
		case "spi":
			spi = fields[i+1]
		}
	}
	return
}

func parseXfrmPolicy(block string) (index, dir string) {
	fields := strings.Fields(block)
	for i := 0; i < len(fields)-1; i++ {
		switch fields[i] {
		case "index":
			index = fields[i+1]
		case "dir":
			dir = fields[i+1]
		}
	}
	return
}
