package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/parrsi01/securewave/netopsd/internal/config"
	"github.com/parrsi01/securewave/netopsd/internal/netops"
	"github.com/parrsi01/securewave/netopsd/internal/server"
	"github.com/parrsi01/securewave/netopsd/internal/system"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		panic(err)
	}

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: parseLevel(cfg.LogLevel)}))
	svc := netops.New(system.ExecRunner{}, logger)
	srv := server.New(cfg, logger, svc)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	logger.Info("securewave-netd starting", "socket_path", cfg.SocketPath)
	if err := srv.ListenAndServe(ctx); err != nil {
		logger.Error("securewave-netd stopped with error", "error", err.Error())
		os.Exit(1)
	}
	logger.Info("securewave-netd stopped cleanly")
}

func parseLevel(level string) slog.Level {
	switch level {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
