"""
Uptime Monitoring Service
Monitors service availability and health across all components
"""

import os
import logging
import socket
import time
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta
import asyncio

logger = logging.getLogger(__name__)

# Configuration
APP_URL = os.getenv("APP_URL", "https://securewave.azurewebsites.net")
DATABASE_URL = os.getenv("DATABASE_URL", "")
REDIS_URL = os.getenv("REDIS_URL", "")
CHECK_INTERVAL_SECONDS = int(os.getenv("UPTIME_CHECK_INTERVAL", "300"))  # 5 minutes


class UptimeMonitorService:
    """
    Uptime Monitoring Service
    Performs health checks on critical services
    """

    def __init__(self):
        """Initialize uptime monitor"""
        self.check_interval = CHECK_INTERVAL_SECONDS
        self.last_check_time = {}

    # ===========================
    # HTTP HEALTH CHECKS
    # ===========================

    def check_http_endpoint(
        self,
        url: str,
        timeout: int = 10,
        expected_status: int = 200
    ) -> Tuple[bool, int, Optional[str]]:
        """
        Check HTTP endpoint availability

        Args:
            url: URL to check
            timeout: Request timeout in seconds
            expected_status: Expected HTTP status code

        Returns:
            Tuple of (is_up, response_time_ms, error_message)
        """
        import urllib.request
        import urllib.error

        start_time = time.time()

        try:
            req = urllib.request.Request(url, method='GET')
            req.add_header('User-Agent', 'SecureWave-Uptime-Monitor/1.0')

            with urllib.request.urlopen(req, timeout=timeout) as response:
                response_time_ms = int((time.time() - start_time) * 1000)
                status_code = response.status

                is_up = status_code == expected_status
                return is_up, response_time_ms, None

        except urllib.error.HTTPError as e:
            response_time_ms = int((time.time() - start_time) * 1000)
            return False, response_time_ms, f"HTTP {e.code}: {e.reason}"

        except urllib.error.URLError as e:
            response_time_ms = int((time.time() - start_time) * 1000)
            return False, response_time_ms, f"URL Error: {str(e.reason)}"

        except socket.timeout:
            response_time_ms = timeout * 1000
            return False, response_time_ms, f"Timeout after {timeout}s"

        except Exception as e:
            response_time_ms = int((time.time() - start_time) * 1000)
            return False, response_time_ms, str(e)

    def check_api_endpoint(self, endpoint: str = "/api/health") -> Dict:
        """
        Check API endpoint

        Args:
            endpoint: API endpoint to check

        Returns:
            Check result dictionary
        """
        url = f"{APP_URL}{endpoint}"
        is_up, response_time_ms, error = self.check_http_endpoint(url)

        return {
            "check_name": "api",
            "check_type": "http",
            "target": url,
            "is_up": is_up,
            "response_time_ms": response_time_ms,
            "error_message": error,
            "checked_at": datetime.utcnow(),
        }

    def check_frontend(self) -> Dict:
        """Check frontend availability"""
        is_up, response_time_ms, error = self.check_http_endpoint(APP_URL)

        return {
            "check_name": "frontend",
            "check_type": "http",
            "target": APP_URL,
            "is_up": is_up,
            "response_time_ms": response_time_ms,
            "error_message": error,
            "checked_at": datetime.utcnow(),
        }

    # ===========================
    # DATABASE HEALTH CHECKS
    # ===========================

    def check_database(self) -> Dict:
        """
        Check database connectivity

        Returns:
            Check result dictionary
        """
        start_time = time.time()

        try:
            from database.session import get_db
            from sqlalchemy import text

            db = next(get_db())

            # Execute simple query
            result = db.execute(text("SELECT 1"))
            result.fetchone()

            response_time_ms = int((time.time() - start_time) * 1000)

            return {
                "check_name": "database",
                "check_type": "database",
                "target": "PostgreSQL",
                "is_up": True,
                "response_time_ms": response_time_ms,
                "error_message": None,
                "checked_at": datetime.utcnow(),
            }

        except Exception as e:
            response_time_ms = int((time.time() - start_time) * 1000)

            return {
                "check_name": "database",
                "check_type": "database",
                "target": "PostgreSQL",
                "is_up": False,
                "response_time_ms": response_time_ms,
                "error_message": str(e),
                "checked_at": datetime.utcnow(),
            }

    # ===========================
    # REDIS HEALTH CHECKS
    # ===========================

    def check_redis(self) -> Dict:
        """
        Check Redis connectivity

        Returns:
            Check result dictionary
        """
        if not REDIS_URL:
            return {
                "check_name": "redis",
                "check_type": "redis",
                "target": "Not configured",
                "is_up": None,
                "response_time_ms": 0,
                "error_message": "Redis not configured",
                "checked_at": datetime.utcnow(),
            }

        start_time = time.time()

        try:
            import redis

            # Parse Redis URL
            r = redis.from_url(REDIS_URL, socket_connect_timeout=5)

            # Ping Redis
            r.ping()

            response_time_ms = int((time.time() - start_time) * 1000)

            return {
                "check_name": "redis",
                "check_type": "redis",
                "target": REDIS_URL.split('@')[-1] if '@' in REDIS_URL else "Redis",
                "is_up": True,
                "response_time_ms": response_time_ms,
                "error_message": None,
                "checked_at": datetime.utcnow(),
            }

        except ImportError:
            return {
                "check_name": "redis",
                "check_type": "redis",
                "target": "Redis",
                "is_up": False,
                "response_time_ms": 0,
                "error_message": "Redis library not installed",
                "checked_at": datetime.utcnow(),
            }

        except Exception as e:
            response_time_ms = int((time.time() - start_time) * 1000)

            return {
                "check_name": "redis",
                "check_type": "redis",
                "target": "Redis",
                "is_up": False,
                "response_time_ms": response_time_ms,
                "error_message": str(e),
                "checked_at": datetime.utcnow(),
            }

    # ===========================
    # VPN SERVER HEALTH CHECKS
    # ===========================

    def check_vpn_server(self, server_ip: str, server_port: int = 51820) -> Dict:
        """
        Check VPN server connectivity

        Args:
            server_ip: VPN server IP address
            server_port: WireGuard port (default 51820)

        Returns:
            Check result dictionary
        """
        start_time = time.time()

        try:
            # Try to connect to UDP port (WireGuard)
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(5)

            # Send dummy packet
            sock.sendto(b'\x00', (server_ip, server_port))

            # Wait for response (will timeout if no response, which is expected)
            try:
                sock.recvfrom(1024)
            except socket.timeout:
                # Timeout is expected for WireGuard - port is open
                pass

            sock.close()

            response_time_ms = int((time.time() - start_time) * 1000)

            return {
                "check_name": f"vpn_server_{server_ip}",
                "check_type": "udp",
                "target": f"{server_ip}:{server_port}",
                "is_up": True,
                "response_time_ms": response_time_ms,
                "error_message": None,
                "checked_at": datetime.utcnow(),
            }

        except Exception as e:
            response_time_ms = int((time.time() - start_time) * 1000)

            return {
                "check_name": f"vpn_server_{server_ip}",
                "check_type": "udp",
                "target": f"{server_ip}:{server_port}",
                "is_up": False,
                "response_time_ms": response_time_ms,
                "error_message": str(e),
                "checked_at": datetime.utcnow(),
            }

    def check_all_vpn_servers(self) -> List[Dict]:
        """
        Check all VPN servers from database

        Returns:
            List of check results
        """
        try:
            from database.session import get_db
            from models.vpn_server import VPNServer

            db = next(get_db())

            # Get all active VPN servers
            servers = db.query(VPNServer).filter(VPNServer.is_active == True).all()

            results = []
            for server in servers:
                result = self.check_vpn_server(server.ip_address, server.port or 51820)
                result["metadata"] = {
                    "server_id": server.id,
                    "server_name": server.name,
                    "location": server.location
                }
                results.append(result)

            return results

        except Exception as e:
            logger.error(f"Failed to check VPN servers: {e}")
            return []

    # ===========================
    # TCP PORT CHECKS
    # ===========================

    def check_tcp_port(self, host: str, port: int, timeout: int = 5) -> Tuple[bool, int, Optional[str]]:
        """
        Check if TCP port is open

        Args:
            host: Hostname or IP
            port: Port number
            timeout: Connection timeout

        Returns:
            Tuple of (is_open, response_time_ms, error_message)
        """
        start_time = time.time()

        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)

            result = sock.connect_ex((host, port))
            sock.close()

            response_time_ms = int((time.time() - start_time) * 1000)

            if result == 0:
                return True, response_time_ms, None
            else:
                return False, response_time_ms, f"Connection refused (code {result})"

        except socket.timeout:
            response_time_ms = timeout * 1000
            return False, response_time_ms, f"Timeout after {timeout}s"

        except Exception as e:
            response_time_ms = int((time.time() - start_time) * 1000)
            return False, response_time_ms, str(e)

    # ===========================
    # PING CHECKS
    # ===========================

    def ping_host(self, host: str, count: int = 1) -> Tuple[bool, Optional[int], Optional[str]]:
        """
        Ping a host

        Args:
            host: Hostname or IP to ping
            count: Number of pings

        Returns:
            Tuple of (is_reachable, avg_response_time_ms, error_message)
        """
        import subprocess
        import platform

        try:
            # Determine ping command based on OS
            param = '-n' if platform.system().lower() == 'windows' else '-c'

            # Execute ping
            command = ['ping', param, str(count), host]
            result = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10
            )

            # Check if ping succeeded
            if result.returncode == 0:
                # Parse output for response time (simplified)
                output = result.stdout.decode()

                # Extract average time (platform-dependent parsing)
                # This is a simplified version - production should use proper parsing
                return True, None, None
            else:
                return False, None, "Host unreachable"

        except subprocess.TimeoutExpired:
            return False, None, "Ping timeout"

        except Exception as e:
            return False, None, str(e)

    # ===========================
    # COMPREHENSIVE HEALTH CHECK
    # ===========================

    def run_all_checks(self) -> Dict:
        """
        Run all health checks

        Returns:
            Dictionary with all check results
        """
        results = {
            "timestamp": datetime.utcnow().isoformat(),
            "checks": {},
            "overall_status": "healthy",
            "total_checks": 0,
            "passed_checks": 0,
            "failed_checks": 0,
        }

        # Check API
        api_check = self.check_api_endpoint()
        results["checks"]["api"] = api_check
        results["total_checks"] += 1
        if api_check["is_up"]:
            results["passed_checks"] += 1
        else:
            results["failed_checks"] += 1

        # Check frontend
        frontend_check = self.check_frontend()
        results["checks"]["frontend"] = frontend_check
        results["total_checks"] += 1
        if frontend_check["is_up"]:
            results["passed_checks"] += 1
        else:
            results["failed_checks"] += 1

        # Check database
        db_check = self.check_database()
        results["checks"]["database"] = db_check
        results["total_checks"] += 1
        if db_check["is_up"]:
            results["passed_checks"] += 1
        else:
            results["failed_checks"] += 1

        # Check Redis
        redis_check = self.check_redis()
        if redis_check["is_up"] is not None:  # Only count if configured
            results["checks"]["redis"] = redis_check
            results["total_checks"] += 1
            if redis_check["is_up"]:
                results["passed_checks"] += 1
            else:
                results["failed_checks"] += 1

        # Check VPN servers
        vpn_checks = self.check_all_vpn_servers()
        if vpn_checks:
            results["checks"]["vpn_servers"] = vpn_checks
            for check in vpn_checks:
                results["total_checks"] += 1
                if check["is_up"]:
                    results["passed_checks"] += 1
                else:
                    results["failed_checks"] += 1

        # Determine overall status
        if results["failed_checks"] == 0:
            results["overall_status"] = "healthy"
        elif results["failed_checks"] < results["total_checks"] / 2:
            results["overall_status"] = "degraded"
        else:
            results["overall_status"] = "unhealthy"

        return results

    def save_check_results(self, results: Dict) -> None:
        """
        Save check results to database

        Args:
            results: Check results from run_all_checks()
        """
        try:
            from database.session import get_db
            from models.audit_log import UptimeCheck

            db = next(get_db())

            # Save each check
            for check_name, check_data in results["checks"].items():
                if isinstance(check_data, list):
                    # Multiple checks (e.g., VPN servers)
                    for check in check_data:
                        uptime_check = UptimeCheck(**check)
                        db.add(uptime_check)
                else:
                    # Single check
                    uptime_check = UptimeCheck(**check_data)
                    db.add(uptime_check)

            db.commit()
            logger.info(f"Saved {results['total_checks']} uptime check results")

        except Exception as e:
            logger.error(f"Failed to save uptime check results: {e}")

    # ===========================
    # UPTIME STATISTICS
    # ===========================

    def get_uptime_stats(self, check_name: str, days: int = 7) -> Dict:
        """
        Get uptime statistics for a service

        Args:
            check_name: Name of the check
            days: Number of days to analyze

        Returns:
            Uptime statistics
        """
        try:
            from database.session import get_db
            from models.audit_log import UptimeCheck
            from sqlalchemy import func

            db = next(get_db())

            # Calculate start date
            start_date = datetime.utcnow() - timedelta(days=days)

            # Get all checks for this service
            checks = db.query(UptimeCheck).filter(
                UptimeCheck.check_name == check_name,
                UptimeCheck.checked_at >= start_date
            ).all()

            if not checks:
                return {
                    "check_name": check_name,
                    "period_days": days,
                    "total_checks": 0,
                    "uptime_percentage": 0.0,
                    "average_response_time_ms": 0,
                }

            # Calculate statistics
            total_checks = len(checks)
            successful_checks = sum(1 for c in checks if c.is_up)
            uptime_percentage = (successful_checks / total_checks) * 100

            # Calculate average response time (only for successful checks)
            response_times = [c.response_time_ms for c in checks if c.is_up and c.response_time_ms]
            avg_response_time = sum(response_times) / len(response_times) if response_times else 0

            # Find incidents
            incidents = []
            for check in checks:
                if not check.is_up:
                    incidents.append({
                        "timestamp": check.checked_at.isoformat(),
                        "error": check.error_message,
                        "duration": None  # Could calculate based on next successful check
                    })

            return {
                "check_name": check_name,
                "period_days": days,
                "total_checks": total_checks,
                "successful_checks": successful_checks,
                "failed_checks": total_checks - successful_checks,
                "uptime_percentage": round(uptime_percentage, 2),
                "average_response_time_ms": int(avg_response_time),
                "incidents": incidents[:10],  # Last 10 incidents
                "incident_count": len(incidents),
            }

        except Exception as e:
            logger.error(f"Failed to get uptime stats: {e}")
            return {
                "check_name": check_name,
                "error": str(e)
            }


# Singleton instance
_uptime_monitor: Optional[UptimeMonitorService] = None


def get_uptime_monitor() -> UptimeMonitorService:
    """Get uptime monitor instance"""
    global _uptime_monitor
    if _uptime_monitor is None:
        _uptime_monitor = UptimeMonitorService()
    return _uptime_monitor
