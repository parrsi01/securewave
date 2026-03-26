package server

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/parrsi01/securewave/netopsd/internal/config"
	"github.com/parrsi01/securewave/netopsd/internal/netops"
	"github.com/parrsi01/securewave/netopsd/internal/rpc"
)

type fakeRunner struct{}

func (fakeRunner) Run(_ context.Context, name string, args ...string) (string, error) {
	return "", fmt.Errorf("unexpected command: %s %s", name, strings.Join(args, " "))
}

func newTestServer(t *testing.T) *Server {
	t.Helper()
	cfg := config.Config{
		SocketPath:     filepath.Join(t.TempDir(), "securewave-netd.sock"),
		SocketMode:     0o660,
		RequestTimeout: 2 * time.Second,
	}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	service := netops.New(fakeRunner{}, logger)
	return New(cfg, logger, service)
}

func unixConnPair(t *testing.T) (*net.UnixConn, *net.UnixConn) {
	t.Helper()
	socketPath := filepath.Join(t.TempDir(), "pair.sock")
	addr := &net.UnixAddr{Name: socketPath, Net: "unix"}
	ln, err := net.ListenUnix("unix", addr)
	if err != nil {
		t.Fatalf("listen unix: %v", err)
	}
	t.Cleanup(func() { _ = ln.Close() })

	serverConnCh := make(chan *net.UnixConn, 1)
	errCh := make(chan error, 1)
	go func() {
		conn, acceptErr := ln.AcceptUnix()
		if acceptErr != nil {
			errCh <- acceptErr
			return
		}
		serverConnCh <- conn
	}()

	clientConn, err := net.DialUnix("unix", nil, addr)
	if err != nil {
		t.Fatalf("dial unix: %v", err)
	}
	t.Cleanup(func() { _ = clientConn.Close() })

	select {
	case acceptErr := <-errCh:
		t.Fatalf("accept unix: %v", acceptErr)
	case serverConn := <-serverConnCh:
		t.Cleanup(func() { _ = serverConn.Close() })
		return serverConn, clientConn
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for unix socket accept")
	}
	return nil, nil
}

func TestDecodeParamsRejectsUnknownFields(t *testing.T) {
	var params rpc.HealthPingParams
	err := decodeParams(json.RawMessage(`{"extra":true}`), &params)
	if err == nil {
		t.Fatal("expected decodeParams to reject unknown fields")
	}
}

func TestDispatchRejectsUnsupportedMethod(t *testing.T) {
	srv := newTestServer(t)
	_, err := srv.dispatch(context.Background(), rpc.Request{
		Version: rpc.Version,
		ID:      "1",
		Method:  "unsupported.method",
	})
	if err == nil {
		t.Fatal("expected unsupported method error")
	}
}

func TestHandleConnReturnsBadRequestOnInvalidJSON(t *testing.T) {
	srv := newTestServer(t)
	serverConn, clientConn := unixConnPair(t)

	go srv.handleConn(context.Background(), serverConn)

	if _, err := clientConn.Write([]byte("not-json\n")); err != nil {
		t.Fatalf("write request: %v", err)
	}
	_ = clientConn.CloseWrite()

	var resp rpc.Response
	if err := json.NewDecoder(clientConn).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp.OK || resp.Error == nil || resp.Error.Code != "bad_request" {
		t.Fatalf("expected bad_request response, got %#v", resp)
	}
}

func TestHandleConnReturnsVersionMismatch(t *testing.T) {
	srv := newTestServer(t)
	serverConn, clientConn := unixConnPair(t)

	go srv.handleConn(context.Background(), serverConn)

	req := rpc.Request{
		Version: "v0",
		ID:      "abc",
		Method:  "health.ping",
	}
	if err := json.NewEncoder(clientConn).Encode(req); err != nil {
		t.Fatalf("encode request: %v", err)
	}
	_ = clientConn.CloseWrite()

	var resp rpc.Response
	if err := json.NewDecoder(clientConn).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp.OK || resp.Error == nil || resp.Error.Code != "version_mismatch" {
		t.Fatalf("expected version_mismatch response, got %#v", resp)
	}
}
