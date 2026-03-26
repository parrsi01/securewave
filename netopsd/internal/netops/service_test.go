package netops

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"strings"
	"testing"

	"github.com/parrsi01/securewave/netopsd/internal/rpc"
)

type fakeRunnerResult struct {
	output string
	err    error
}

type fakeRunner struct {
	results map[string]fakeRunnerResult
	calls   []string
}

func (f *fakeRunner) Run(_ context.Context, name string, args ...string) (string, error) {
	call := strings.TrimSpace(name + " " + strings.Join(args, " "))
	f.calls = append(f.calls, call)
	if result, ok := f.results[call]; ok {
		return result.output, result.err
	}
	return "", nil
}

func newTestService(runner *fakeRunner) *Service {
	return New(runner, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

func TestWireGuardApplyConfigRejectsInvalidPrivateKey(t *testing.T) {
	runner := &fakeRunner{results: map[string]fakeRunnerResult{}}
	service := newTestService(runner)

	_, err := service.WireGuardApplyConfig(context.Background(), rpc.WireGuardApplyConfigParams{
		Interface:  "wg0",
		PrivateKey: "not-base64",
	})
	if err == nil || !strings.Contains(err.Error(), "private_key") {
		t.Fatalf("expected private_key validation error, got %v", err)
	}
	if len(runner.calls) != 0 {
		t.Fatalf("expected no runner calls, got %v", runner.calls)
	}
}

func TestRouteDeleteIgnoresMissingRouteError(t *testing.T) {
	runner := &fakeRunner{
		results: map[string]fakeRunnerResult{
			"ip -4 route del 10.8.0.0/24": {err: errors.New("No such process")},
		},
	}
	service := newTestService(runner)

	result, err := service.RouteDelete(context.Background(), rpc.RouteDeleteParams{
		Destination: "10.8.0.0/24",
	})
	if err != nil {
		t.Fatalf("expected missing route to be ignored, got %v", err)
	}
	if result["status"] != "ok" {
		t.Fatalf("expected ok status, got %#v", result)
	}
}

func TestWireGuardStatusReturnsMissingDeviceWithoutError(t *testing.T) {
	runner := &fakeRunner{
		results: map[string]fakeRunnerResult{
			"ip link show dev wg0": {err: errors.New("Cannot find device \"wg0\"")},
		},
	}
	service := newTestService(runner)

	status, err := service.WireGuardStatus(context.Background(), rpc.WireGuardStatusParams{
		Interface: "wg0",
	})
	if err != nil {
		t.Fatalf("expected missing device status without error, got %v", err)
	}
	if status.Exists {
		t.Fatalf("expected interface to be absent, got %#v", status)
	}
}

func TestBuildWGConfigIncludesPeersAndOptionalFields(t *testing.T) {
	config := buildWGConfig(rpc.WireGuardApplyConfigParams{
		Interface:    "wg0",
		PrivateKey:   "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
		ListenPort:   51820,
		FirewallMark: "0x64",
		Peers: []rpc.WireGuardPeerConfig{
			{
				PublicKey:           "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
				PresharedKey:        "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=",
				Endpoint:            "198.51.100.20:51820",
				AllowedIPs:          []string{"10.0.0.2/32", "fd00::2/128"},
				PersistentKeepalive: 25,
			},
		},
	})

	for _, fragment := range []string{
		"[Interface]",
		"ListenPort = 51820",
		"FwMark = 0x64",
		"[Peer]",
		"Endpoint = 198.51.100.20:51820",
		"AllowedIPs = 10.0.0.2/32, fd00::2/128",
		"PersistentKeepalive = 25",
	} {
		if !strings.Contains(config, fragment) {
			t.Fatalf("expected config to contain %q, got:\n%s", fragment, config)
		}
	}
}
