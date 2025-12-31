"""
Comprehensive Dashboard Test Suite
Tests VPN toggle, server selection, config generation, and download functionality
"""

import requests
import json
import sys
from typing import Optional


class DashboardTester:
    def __init__(self, base_url: str = "https://securewave-app.azurewebsites.net"):
        self.base_url = base_url.rstrip('/')
        self.session = requests.Session()
        self.access_token: Optional[str] = None
        self.refresh_token: Optional[str] = None
        self.test_email = f"dashtest_{id(self)}@example.com"
        self.test_password = "SecureDash123!@#"
        self.selected_server_id: Optional[str] = None

    def log(self, message: str, status: str = "INFO"):
        """Print formatted log message"""
        symbols = {
            "PASS": "✓",
            "FAIL": "✗",
            "INFO": "ℹ",
            "WARN": "⚠"
        }
        symbol = symbols.get(status, "•")
        print(f"[{status}] {symbol} {message}")

    def test_1_register_user(self) -> bool:
        """Test user registration for dashboard access"""
        try:
            self.log("Registering new test user for dashboard", "INFO")
            response = self.session.post(
                f"{self.base_url}/api/auth/register",
                json={"email": self.test_email, "password": self.test_password},
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                self.access_token = data.get("access_token")
                self.refresh_token = data.get("refresh_token")

                if self.access_token:
                    self.log(f"User registered successfully: {self.test_email}", "PASS")
                    return True
                else:
                    self.log("Registration succeeded but no token returned", "FAIL")
                    return False
            else:
                self.log(f"Registration failed: {response.status_code} - {response.text}", "FAIL")
                return False

        except Exception as e:
            self.log(f"Registration error: {str(e)}", "FAIL")
            return False

    def test_2_get_user_info(self) -> bool:
        """Test /api/auth/users/me endpoint for dashboard user info"""
        try:
            self.log("Testing GET /api/auth/users/me endpoint", "INFO")

            if not self.access_token:
                self.log("No access token available", "FAIL")
                return False

            response = self.session.get(
                f"{self.base_url}/api/auth/users/me",
                headers={"Authorization": f"Bearer {self.access_token}"},
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                required_fields = ["id", "email", "subscription_status"]

                missing = [f for f in required_fields if f not in data]
                if missing:
                    self.log(f"Missing required fields: {missing}", "FAIL")
                    return False

                self.log(f"User info retrieved: {data.get('email')}", "PASS")
                return True
            else:
                self.log(f"Failed to get user info: {response.status_code}", "FAIL")
                return False

        except Exception as e:
            self.log(f"Error getting user info: {str(e)}", "FAIL")
            return False

    def test_3_load_servers(self) -> bool:
        """Test /api/optimizer/servers endpoint for server dropdown"""
        try:
            self.log("Testing GET /api/optimizer/servers endpoint", "INFO")

            if not self.access_token:
                self.log("No access token available", "FAIL")
                return False

            response = self.session.get(
                f"{self.base_url}/api/optimizer/servers",
                headers={"Authorization": f"Bearer {self.access_token}"},
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                servers = data.get("servers", [])

                if not servers:
                    self.log("No servers returned", "FAIL")
                    return False

                # Store first server for later tests
                self.selected_server_id = servers[0].get("server_id")

                required_fields = ["server_id", "location", "latency_ms", "bandwidth_mbps"]
                for server in servers[:3]:  # Check first 3 servers
                    missing = [f for f in required_fields if f not in server]
                    if missing:
                        self.log(f"Server missing fields: {missing}", "FAIL")
                        return False

                self.log(f"Loaded {len(servers)} servers successfully", "PASS")
                return True
            else:
                self.log(f"Failed to load servers: {response.status_code}", "FAIL")
                return False

        except Exception as e:
            self.log(f"Error loading servers: {str(e)}", "FAIL")
            return False

    def test_4_generate_vpn_config(self) -> bool:
        """Test POST /api/vpn/generate with server_id"""
        try:
            self.log("Testing POST /api/vpn/generate endpoint", "INFO")

            if not self.access_token:
                self.log("No access token available", "FAIL")
                return False

            payload = {}
            if self.selected_server_id:
                payload["server_id"] = self.selected_server_id

            response = self.session.post(
                f"{self.base_url}/api/vpn/generate",
                headers={
                    "Authorization": f"Bearer {self.access_token}",
                    "Content-Type": "application/json"
                },
                json=payload,
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()

                if "config" not in data:
                    self.log("No config in response", "FAIL")
                    return False

                config = data["config"]
                if not config or len(config) < 100:
                    self.log("Config seems invalid or too short", "FAIL")
                    return False

                # Check for WireGuard config markers
                required_sections = ["[Interface]", "[Peer]"]
                missing_sections = [s for s in required_sections if s not in config]
                if missing_sections:
                    self.log(f"Config missing sections: {missing_sections}", "FAIL")
                    return False

                self.log("VPN configuration generated successfully", "PASS")
                return True
            else:
                self.log(f"Failed to generate config: {response.status_code} - {response.text}", "FAIL")
                return False

        except Exception as e:
            self.log(f"Error generating config: {str(e)}", "FAIL")
            return False

    def test_5_download_vpn_config(self) -> bool:
        """Test POST /api/vpn/config/download"""
        try:
            self.log("Testing POST /api/vpn/config/download endpoint", "INFO")

            if not self.access_token:
                self.log("No access token available", "FAIL")
                return False

            payload = {}
            if self.selected_server_id:
                payload["server_id"] = self.selected_server_id

            response = self.session.post(
                f"{self.base_url}/api/vpn/config/download",
                headers={
                    "Authorization": f"Bearer {self.access_token}",
                    "Content-Type": "application/json"
                },
                json=payload,
                timeout=10
            )

            if response.status_code == 200:
                # Check content type
                content_type = response.headers.get("Content-Type", "")
                if "text/plain" not in content_type:
                    self.log(f"Unexpected content type: {content_type}", "WARN")

                # Check content
                content = response.text
                if len(content) < 100:
                    self.log("Downloaded config seems too short", "FAIL")
                    return False

                # Verify WireGuard format
                if "[Interface]" not in content or "[Peer]" not in content:
                    self.log("Downloaded config doesn't appear to be valid WireGuard format", "FAIL")
                    return False

                self.log(f"Config downloaded successfully ({len(content)} bytes)", "PASS")
                return True
            else:
                self.log(f"Failed to download config: {response.status_code}", "FAIL")
                return False

        except Exception as e:
            self.log(f"Error downloading config: {str(e)}", "FAIL")
            return False

    def test_6_dashboard_html_loads(self) -> bool:
        """Test that dashboard.html loads successfully"""
        try:
            self.log("Testing dashboard.html loads", "INFO")

            response = self.session.get(f"{self.base_url}/dashboard.html", timeout=10)

            if response.status_code == 200:
                html = response.text

                # Check for required elements
                required_elements = [
                    'id="vpnToggle"',
                    'id="serverSelect"',
                    'id="downloadConfigBtn"',
                    'id="connectionStatus"',
                    'id="statLatency"',
                    'id="statBandwidth"',
                    'id="statLocation"',
                    'id="statEncryption"',
                    'id="userEmail"',
                    'id="logoutBtn"',
                    'src="/js/dashboard.js"'
                ]

                missing = [elem for elem in required_elements if elem not in html]
                if missing:
                    self.log(f"Dashboard HTML missing elements: {missing}", "FAIL")
                    return False

                self.log("Dashboard HTML loaded with all required elements", "PASS")
                return True
            else:
                self.log(f"Failed to load dashboard.html: {response.status_code}", "FAIL")
                return False

        except Exception as e:
            self.log(f"Error loading dashboard.html: {str(e)}", "FAIL")
            return False

    def test_7_dashboard_js_loads(self) -> bool:
        """Test that dashboard.js loads successfully"""
        try:
            self.log("Testing dashboard.js loads", "INFO")

            response = self.session.get(f"{self.base_url}/js/dashboard.js", timeout=10)

            if response.status_code == 200:
                js_content = response.text

                # Check for key functionality
                required_functions = [
                    "class VPNDashboard",
                    "loadServers",
                    "handleVPNToggle",
                    "connectVPN",
                    "disconnectVPN",
                    "downloadConfig",
                    "loadUserInfo"
                ]

                missing = [func for func in required_functions if func not in js_content]
                if missing:
                    self.log(f"dashboard.js missing functions: {missing}", "FAIL")
                    return False

                self.log(f"dashboard.js loaded successfully ({len(js_content)} bytes)", "PASS")
                return True
            else:
                self.log(f"Failed to load dashboard.js: {response.status_code}", "FAIL")
                return False

        except Exception as e:
            self.log(f"Error loading dashboard.js: {str(e)}", "FAIL")
            return False

    def test_8_no_qr_code_references(self) -> bool:
        """Test that QR code functionality has been removed"""
        try:
            self.log("Testing QR code removal from dashboard", "INFO")

            # Check dashboard.html
            html_response = self.session.get(f"{self.base_url}/dashboard.html", timeout=10)
            js_response = self.session.get(f"{self.base_url}/js/dashboard.js", timeout=10)

            html_content = html_response.text
            js_content = js_response.text

            # Look for QR code references
            qr_references_html = [
                'showQR',
                'qrCode',
                'QR Code',
                'qr_base64'
            ]

            qr_references_js = [
                'showQR',
                'qrCode',
                '/api/vpn/config/qr'
            ]

            found_in_html = [ref for ref in qr_references_html if ref in html_content]
            found_in_js = [ref for ref in qr_references_js if ref in js_content]

            if found_in_html or found_in_js:
                self.log(f"QR code references still present - HTML: {found_in_html}, JS: {found_in_js}", "FAIL")
                return False

            self.log("QR code functionality successfully removed", "PASS")
            return True

        except Exception as e:
            self.log(f"Error checking QR code removal: {str(e)}", "FAIL")
            return False

    def test_9_professional_css_loaded(self) -> bool:
        """Test that professional.css is loaded and accessible"""
        try:
            self.log("Testing professional.css loads", "INFO")

            response = self.session.get(f"{self.base_url}/css/professional.css", timeout=10)

            if response.status_code == 200:
                css_content = response.text

                # Check for design system variables
                required_css = [
                    "--primary-",
                    "--gradient-primary",
                    "--shadow-",
                    ".btn-primary"
                ]

                missing = [rule for rule in required_css if rule not in css_content]
                if missing:
                    self.log(f"CSS missing design tokens: {missing}", "FAIL")
                    return False

                self.log(f"professional.css loaded successfully ({len(css_content)} bytes)", "PASS")
                return True
            else:
                self.log(f"Failed to load professional.css: {response.status_code}", "FAIL")
                return False

        except Exception as e:
            self.log(f"Error loading professional.css: {str(e)}", "FAIL")
            return False

    def test_10_auth_protection(self) -> bool:
        """Test that dashboard endpoints require authentication"""
        try:
            self.log("Testing authentication protection on endpoints", "INFO")

            # Create a new session without auth token
            unauth_session = requests.Session()

            protected_endpoints = [
                "/api/auth/users/me",
                "/api/optimizer/servers",
                "/api/vpn/config/download"
            ]

            for endpoint in protected_endpoints:
                # Try GET first
                response = unauth_session.get(f"{self.base_url}{endpoint}", timeout=10)

                # If GET returns 405 (Method Not Allowed), try POST
                if response.status_code == 405:
                    response = unauth_session.post(
                        f"{self.base_url}{endpoint}",
                        json={},
                        headers={"Content-Type": "application/json"},
                        timeout=10
                    )

                if response.status_code != 401:
                    self.log(f"Endpoint {endpoint} not properly protected (got {response.status_code})", "FAIL")
                    return False

            self.log("All protected endpoints require authentication", "PASS")
            return True

        except Exception as e:
            self.log(f"Error testing auth protection: {str(e)}", "FAIL")
            return False

    def run_all_tests(self):
        """Run all dashboard tests"""
        print("\n" + "="*70)
        print("SECUREWAVE DASHBOARD TEST SUITE")
        print("="*70 + "\n")

        tests = [
            self.test_1_register_user,
            self.test_2_get_user_info,
            self.test_3_load_servers,
            self.test_4_generate_vpn_config,
            self.test_5_download_vpn_config,
            self.test_6_dashboard_html_loads,
            self.test_7_dashboard_js_loads,
            self.test_8_no_qr_code_references,
            self.test_9_professional_css_loaded,
            self.test_10_auth_protection
        ]

        results = []
        for test in tests:
            try:
                result = test()
                results.append(result)
            except Exception as e:
                self.log(f"Test {test.__name__} crashed: {str(e)}", "FAIL")
                results.append(False)
            print()  # Add spacing between tests

        # Print summary
        print("="*70)
        print("TEST SUMMARY")
        print("="*70)
        passed = sum(results)
        total = len(results)
        percentage = (passed / total * 100) if total > 0 else 0

        print(f"\nTotal Tests: {total}")
        print(f"Passed: {passed}")
        print(f"Failed: {total - passed}")
        print(f"Success Rate: {percentage:.1f}%\n")

        if percentage == 100:
            print("✓ ALL TESTS PASSED - Dashboard is fully functional!")
        elif percentage >= 80:
            print("⚠ MOST TESTS PASSED - Minor issues detected")
        else:
            print("✗ MULTIPLE FAILURES - Dashboard needs attention")

        print("="*70 + "\n")

        return percentage == 100


def main():
    """Main test runner"""
    tester = DashboardTester()
    success = tester.run_all_tests()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
