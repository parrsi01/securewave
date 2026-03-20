package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	SocketPath      string
	SocketMode      os.FileMode
	RequestTimeout  time.Duration
	ShutdownTimeout time.Duration
	LogLevel        string
}

func Load() (Config, error) {
	socketPath := strings.TrimSpace(os.Getenv("SECUREWAVE_NETOPSD_SOCKET_PATH"))
	if socketPath == "" {
		socketPath = "/run/securewave/netops.sock"
	}

	socketModeRaw := strings.TrimSpace(os.Getenv("SECUREWAVE_NETOPSD_SOCKET_MODE"))
	socketMode := os.FileMode(0o660)
	if socketModeRaw != "" {
		parsed, err := strconv.ParseUint(socketModeRaw, 8, 32)
		if err != nil {
			return Config{}, fmt.Errorf("invalid SECUREWAVE_NETOPSD_SOCKET_MODE: %w", err)
		}
		socketMode = os.FileMode(parsed)
	}

	requestTimeout := durationFromEnv("SECUREWAVE_NETOPSD_REQUEST_TIMEOUT_MS", 10*time.Second)
	shutdownTimeout := durationFromEnv("SECUREWAVE_NETOPSD_SHUTDOWN_TIMEOUT_MS", 15*time.Second)
	logLevel := strings.ToLower(strings.TrimSpace(os.Getenv("SECUREWAVE_NETOPSD_LOG_LEVEL")))
	if logLevel == "" {
		logLevel = "info"
	}

	if err := os.MkdirAll(filepath.Dir(socketPath), 0o750); err != nil {
		return Config{}, fmt.Errorf("ensure socket dir: %w", err)
	}

	return Config{
		SocketPath:      socketPath,
		SocketMode:      socketMode,
		RequestTimeout:  requestTimeout,
		ShutdownTimeout: shutdownTimeout,
		LogLevel:        logLevel,
	}, nil
}

func durationFromEnv(name string, fallback time.Duration) time.Duration {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return fallback
	}
	ms, err := strconv.Atoi(raw)
	if err != nil || ms <= 0 {
		return fallback
	}
	return time.Duration(ms) * time.Millisecond
}
