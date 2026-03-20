package server

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"os"
	"time"

	"github.com/parrsi01/securewave/netopsd/internal/config"
	"github.com/parrsi01/securewave/netopsd/internal/netops"
	"github.com/parrsi01/securewave/netopsd/internal/rpc"
)

type Server struct {
	cfg     config.Config
	logger  *slog.Logger
	service *netops.Service
	ln      *net.UnixListener
}

func New(cfg config.Config, logger *slog.Logger, service *netops.Service) *Server {
	return &Server{cfg: cfg, logger: logger, service: service}
}

func (s *Server) ListenAndServe(ctx context.Context) error {
	_ = os.Remove(s.cfg.SocketPath)
	ln, err := net.Listen("unix", s.cfg.SocketPath)
	if err != nil {
		return fmt.Errorf("listen unix socket: %w", err)
	}
	unixLn, ok := ln.(*net.UnixListener)
	if !ok {
		return fmt.Errorf("unexpected listener type")
	}
	s.ln = unixLn
	if err := os.Chmod(s.cfg.SocketPath, s.cfg.SocketMode); err != nil {
		return fmt.Errorf("chmod socket: %w", err)
	}

	go func() {
		<-ctx.Done()
		_ = s.ln.Close()
	}()

	for {
		conn, err := s.ln.AcceptUnix()
		if err != nil {
			if errors.Is(err, net.ErrClosed) || ctx.Err() != nil {
				return nil
			}
			return fmt.Errorf("accept unix connection: %w", err)
		}
		go s.handleConn(ctx, conn)
	}
}

func (s *Server) handleConn(ctx context.Context, conn *net.UnixConn) {
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(s.cfg.RequestTimeout))

	var req rpc.Request
	decoder := json.NewDecoder(conn)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&req); err != nil {
		s.writeResponse(conn, rpc.Response{
			Version: rpc.Version,
			OK:      false,
			Error:   &rpc.ErrorBody{Code: "bad_request", Message: "invalid JSON request", Details: map[string]any{"error": err.Error()}},
		})
		return
	}
	if req.Version != rpc.Version {
		s.writeResponse(conn, rpc.Response{
			Version: rpc.Version,
			ID:      req.ID,
			OK:      false,
			Error:   &rpc.ErrorBody{Code: "version_mismatch", Message: "unsupported protocol version"},
		})
		return
	}

	reqCtx, cancel := context.WithTimeout(ctx, s.cfg.RequestTimeout)
	defer cancel()

	result, err := s.dispatch(reqCtx, req)
	if err != nil {
		s.writeResponse(conn, rpc.Response{
			Version: rpc.Version,
			ID:      req.ID,
			OK:      false,
			Error:   &rpc.ErrorBody{Code: "operation_failed", Message: err.Error()},
		})
		return
	}
	s.writeResponse(conn, rpc.Response{Version: rpc.Version, ID: req.ID, OK: true, Result: result})
}

func (s *Server) dispatch(ctx context.Context, req rpc.Request) (any, error) {
	switch req.Method {
	case "health.ping":
		return s.service.HealthPing(ctx)
	case "net.setup_protocol":
		var p rpc.NetSetupProtocolParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.NetSetupProtocol(ctx, p)
	case "net.teardown_protocol":
		var p rpc.NetTeardownProtocolParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.NetTeardownProtocol(ctx, p)
	case "wg.create_interface":
		var p rpc.WireGuardCreateInterfaceParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.WireGuardCreateInterface(ctx, p)
	case "wg.delete_interface":
		var p rpc.WireGuardDeleteInterfaceParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.WireGuardDeleteInterface(ctx, p)
	case "wg.set_mtu":
		var p rpc.WireGuardSetMTUParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.WireGuardSetMTU(ctx, p)
	case "wg.set_addresses":
		var p rpc.WireGuardAddressParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.WireGuardAssignAddress(ctx, p)
	case "wg.set_link_state":
		var p rpc.WireGuardLinkParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.WireGuardSetLinkState(ctx, p)
	case "wg.apply_config":
		var p rpc.WireGuardApplyConfigParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.WireGuardApplyConfig(ctx, p)
	case "wg.status":
		var p rpc.WireGuardStatusParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.WireGuardStatus(ctx, p)
	case "route.add":
		var p rpc.RouteAddParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.RouteAdd(ctx, p)
	case "route.delete":
		var p rpc.RouteDeleteParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.RouteDelete(ctx, p)
	case "vpn.cleanup":
		var p rpc.VpnCleanupParams
		if err := decodeParams(req.Params, &p); err != nil {
			return nil, err
		}
		return s.service.VpnCleanup(ctx, p)
	case "openvpn.stub":
		return s.service.OpenVPNStub(ctx)
	case "ikev2.stub":
		return s.service.IKEv2Stub(ctx)
	default:
		return nil, fmt.Errorf("unsupported method %q", req.Method)
	}
}

func decodeParams(raw json.RawMessage, target any) error {
	if len(raw) == 0 {
		raw = []byte("{}")
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("invalid params: %w", err)
	}
	return nil
}

func (s *Server) writeResponse(conn *net.UnixConn, resp rpc.Response) {
	_ = json.NewEncoder(conn).Encode(resp)
}
