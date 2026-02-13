import os
import socket
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

import pytest


def _free_port() -> int:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(("127.0.0.1", 0))
            return int(s.getsockname()[1])
    except PermissionError:
        # This sandbox forbids opening TCP sockets, which makes preview-stack
        # (uvicorn+nginx) integration tests impossible to run here.
        pytest.skip("Sandbox forbids TCP sockets; skipping preview-stack tests.")


def _wait_http_ok(url: str, timeout_s: float = 10.0) -> bool:
    import urllib.request

    start = time.time()
    while time.time() - start <= timeout_s:
        try:
            req = urllib.request.Request(url, method="GET")
            with urllib.request.urlopen(req, timeout=2) as resp:  # nosec - local test server
                if 200 <= resp.status < 300:
                    return True
        except Exception:
            time.sleep(0.1)
    return False


@dataclass(frozen=True)
class PreviewStack:
    base_url: str
    backend_url: str
    nginx_used: bool


@pytest.fixture(scope="session")
def preview_stack(tmp_path_factory: pytest.TempPathFactory) -> PreviewStack:
    repo_root = Path(__file__).resolve().parents[2]
    python_bin = os.getenv("PYTHON_BIN") or str(repo_root / ".venv" / "bin" / "python")
    if not Path(python_bin).exists():
        python_bin = "python3"

    backend_port = _free_port()
    nginx_port = _free_port()
    tmp_dir = tmp_path_factory.mktemp("preview_stack")

    env = os.environ.copy()
    env.update(
        {
            "ENVIRONMENT": "preview",
            "DEMO_MODE": "true",
            "WG_MOCK_MODE": "true",
            "TESTING": "true",
            "EMAIL_PROVIDER": "smtp",
            "DATABASE_URL": f"sqlite:///{tmp_dir}/preview.db",
        }
    )

    backend_cmd = [
        python_bin,
        "-m",
        "uvicorn",
        "main:app",
        "--host",
        "127.0.0.1",
        "--port",
        str(backend_port),
        "--log-level",
        "warning",
    ]
    backend_log = (tmp_dir / "backend.log").open("w", encoding="utf-8")
    backend_proc = subprocess.Popen(  # nosec - local test server
        backend_cmd,
        cwd=str(repo_root),
        env=env,
        stdout=backend_log,
        stderr=subprocess.STDOUT,
    )

    backend_url = f"http://127.0.0.1:{backend_port}"
    if not _wait_http_ok(f"{backend_url}/api/health", timeout_s=15.0):
        backend_proc.terminate()
        backend_proc.wait(timeout=10)
        raise RuntimeError("backend did not become healthy in time")

    nginx_bin = os.getenv("NGINX_BIN") or "nginx"
    nginx_used = False
    nginx_proc: subprocess.Popen[str] | None = None
    base_url = backend_url

    # Prefer exercising the proxy layer when nginx is available.
    try:
        subprocess.run([nginx_bin, "-v"], capture_output=True, text=True, check=False)  # nosec B603
        nginx_used = True
    except Exception:
        nginx_used = False

    if nginx_used:
        nginx_conf = tmp_dir / "nginx.conf"
        nginx_conf.write_text(
            "\n".join(
                [
                    "worker_processes  1;",
                    f"error_log {tmp_dir}/nginx_error.log info;",
                    f"pid {tmp_dir}/nginx.pid;",
                    "events { worker_connections 1024; }",
                    "http {",
                    f"  access_log {tmp_dir}/nginx_access.log;",
                    "  server {",
                    f"    listen 127.0.0.1:{nginx_port};",
                    "    server_name localhost;",
                    "    location / {",
                    "      proxy_http_version 1.1;",
                    "      proxy_set_header Host $host;",
                    "      proxy_set_header X-Real-IP $remote_addr;",
                    "      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;",
                    "      proxy_set_header X-Forwarded-Proto $scheme;",
                    "      proxy_set_header Connection \"\";",
                    f"      proxy_pass http://127.0.0.1:{backend_port};",
                    "    }",
                    "  }",
                    "}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

        nginx_cmd = [nginx_bin, "-c", str(nginx_conf), "-p", str(tmp_dir), "-g", "daemon off;"]
        nginx_proc = subprocess.Popen(  # nosec - local test server
            nginx_cmd,
            cwd=str(repo_root),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        base_url = f"http://127.0.0.1:{nginx_port}"
        if not _wait_http_ok(f"{base_url}/api/health", timeout_s=10.0):
            # Fall back to direct backend if nginx failed to start.
            nginx_proc.terminate()
            try:
                nginx_proc.wait(timeout=5)
            except Exception:
                nginx_proc.kill()
            nginx_used = False
            base_url = backend_url

    yield PreviewStack(base_url=base_url, backend_url=backend_url, nginx_used=nginx_used)

    # Teardown
    if nginx_proc is not None:
        nginx_proc.terminate()
        try:
            nginx_proc.wait(timeout=5)
        except Exception:
            nginx_proc.kill()

    backend_proc.terminate()
    try:
        backend_proc.wait(timeout=10)
    except Exception:
        backend_proc.kill()
    backend_log.close()
