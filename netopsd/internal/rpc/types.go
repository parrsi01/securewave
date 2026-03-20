package rpc

import "encoding/json"

const Version = "v1"

type Request struct {
	Version string          `json:"version"`
	ID      string          `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type Response struct {
	Version string      `json:"version"`
	ID      string      `json:"id"`
	OK      bool        `json:"ok"`
	Result  any         `json:"result,omitempty"`
	Error   *ErrorBody  `json:"error,omitempty"`
}

type ErrorBody struct {
	Code    string         `json:"code"`
	Message string         `json:"message"`
	Details map[string]any `json:"details,omitempty"`
}

type HealthPingParams struct{}

type HealthPingResult struct {
	Status string `json:"status"`
}

type NetSetupProtocolParams struct {
	Protocol    string `json:"protocol"`
	SourceCIDR  string `json:"source_cidr"`
	TunnelIface string `json:"tunnel_iface"`
	EgressIface string `json:"egress_iface"`
}

type NetTeardownProtocolParams struct {
	Protocol        string `json:"protocol"`
	SourceCIDR      string `json:"source_cidr"`
	TunnelIface     string `json:"tunnel_iface"`
	EgressIface     string `json:"egress_iface"`
	BringLinkDown   bool   `json:"bring_link_down"`
	CleanupXfrmMark string `json:"cleanup_xfrm_mark,omitempty"`
}

type WireGuardCreateInterfaceParams struct {
	Interface string `json:"interface"`
}

type WireGuardDeleteInterfaceParams struct {
	Interface string `json:"interface"`
}

type WireGuardSetMTUParams struct {
	Interface string `json:"interface"`
	MTU       int    `json:"mtu"`
}

type WireGuardAddressParams struct {
	Interface string   `json:"interface"`
	Addresses []string `json:"addresses"`
}

type WireGuardLinkParams struct {
	Interface string `json:"interface"`
	State     string `json:"state"`
}

type WireGuardPeerConfig struct {
	PublicKey           string   `json:"public_key"`
	PresharedKey        string   `json:"preshared_key,omitempty"`
	Endpoint            string   `json:"endpoint,omitempty"`
	AllowedIPs          []string `json:"allowed_ips"`
	PersistentKeepalive int      `json:"persistent_keepalive,omitempty"`
}

type WireGuardApplyConfigParams struct {
	Interface    string                `json:"interface"`
	PrivateKey   string                `json:"private_key"`
	ListenPort   int                   `json:"listen_port,omitempty"`
	FirewallMark string                `json:"firewall_mark,omitempty"`
	Peers        []WireGuardPeerConfig `json:"peers,omitempty"`
}

type WireGuardStatusParams struct {
	Interface string `json:"interface"`
}

type RouteAddParams struct {
	Destination string `json:"destination"`
	Dev         string `json:"dev,omitempty"`
	Via         string `json:"via,omitempty"`
	Table       string `json:"table,omitempty"`
	Replace     bool   `json:"replace"`
}

type RouteDeleteParams struct {
	Destination string `json:"destination"`
	Dev         string `json:"dev,omitempty"`
	Via         string `json:"via,omitempty"`
	Table       string `json:"table,omitempty"`
}

type VpnCleanupParams struct {
	Protocol        string `json:"protocol"`
	SourceCIDR      string `json:"source_cidr"`
	TunnelIface     string `json:"tunnel_iface"`
	EgressIface     string `json:"egress_iface"`
	CleanupXfrmMark string `json:"cleanup_xfrm_mark,omitempty"`
}

type WireGuardStatusResult struct {
	Interface string   `json:"interface"`
	Exists    bool     `json:"exists"`
	LinkUp    bool     `json:"link_up"`
	Addresses []string `json:"addresses,omitempty"`
	WGDump    string   `json:"wg_dump,omitempty"`
}
