#!/usr/bin/env python3
"""
SecureWave VPN - Comprehensive Test Suite
Tests all API endpoints and functionality
"""

import requests
import json
import sys
from typing import Dict, Optional
import time

# Configuration
BASE_URL = "https://securewave-app.azurewebsites.net"
# For local testing, use: BASE_URL = "http://localhost:8080"

class Colors:
    """Terminal colors for output"""
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    BOLD = '\033[1m'
    END = '\033[0m'

class SecureWaveTest:
    def __init__(self, base_url: str = BASE_URL):
        self.base_url = base_url
        self.session = requests.Session()
        self.test_email = f"test_{int(time.time())}@example.com"
        self.test_password = "SecurePass123!"
        self.access_token: Optional[str] = None
        self.refresh_token: Optional[str] = None
        self.passed_tests = 0
        self.failed_tests = 0
        self.total_tests = 0

    def print_header(self, text: str):
        """Print section header"""
        print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*70}{Colors.END}")
        print(f"{Colors.BOLD}{Colors.BLUE}{text}{Colors.END}")
        print(f"{Colors.BOLD}{Colors.BLUE}{'='*70}{Colors.END}\n")

    def print_test(self, test_name: str, passed: bool, message: str = ""):
        """Print test result"""
        self.total_tests += 1
        status = f"{Colors.GREEN}✓ PASS{Colors.END}" if passed else f"{Colors.RED}✗ FAIL{Colors.END}"
        self.passed_tests += passed
        self.failed_tests += (not passed)

        print(f"[{self.total_tests}] {test_name}: {status}")
        if message:
            print(f"    {message}")

    def test_health_check(self):
        """Test 1: Health Check Endpoint"""
        try:
            response = self.session.get(f"{self.base_url}/api/health", timeout=10)
            data = response.json()

            passed = (
                response.status_code == 200 and
                data.get("status") == "ok" and
                "service" in data
            )

            self.print_test(
                "Health Check",
                passed,
                f"Status: {response.status_code}, Data: {data}"
            )
            return passed
        except Exception as e:
            self.print_test("Health Check", False, f"Error: {str(e)}")
            return False

    def test_ready_check(self):
        """Test 2: Ready Check Endpoint"""
        try:
            response = self.session.get(f"{self.base_url}/api/ready", timeout=10)

            passed = response.status_code == 200

            self.print_test(
                "Ready Check",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("Ready Check", False, f"Error: {str(e)}")
            return False

    def test_registration(self):
        """Test 3: User Registration"""
        try:
            payload = {
                "email": self.test_email,
                "password": self.test_password
            }

            response = self.session.post(
                f"{self.base_url}/api/auth/register",
                json=payload,
                headers={"Content-Type": "application/json"},
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                self.access_token = data.get("access_token")
                self.refresh_token = data.get("refresh_token")

                passed = (
                    self.access_token is not None and
                    self.refresh_token is not None and
                    data.get("token_type") == "bearer"
                )
            else:
                passed = False

            self.print_test(
                "User Registration",
                passed,
                f"Status: {response.status_code}, Email: {self.test_email}"
            )
            return passed
        except Exception as e:
            self.print_test("User Registration", False, f"Error: {str(e)}")
            return False

    def test_duplicate_registration(self):
        """Test 4: Duplicate Registration Prevention"""
        try:
            payload = {
                "email": self.test_email,
                "password": self.test_password
            }

            response = self.session.post(
                f"{self.base_url}/api/auth/register",
                json=payload,
                headers={"Content-Type": "application/json"},
                timeout=10
            )

            # Should fail with 400 Bad Request
            passed = response.status_code == 400

            self.print_test(
                "Duplicate Registration Prevention",
                passed,
                f"Status: {response.status_code} (expected 400)"
            )
            return passed
        except Exception as e:
            self.print_test("Duplicate Registration Prevention", False, f"Error: {str(e)}")
            return False

    def test_login(self):
        """Test 5: User Login"""
        try:
            # Create a new user for login test
            new_email = f"login_test_{int(time.time())}@example.com"

            # Register first
            reg_response = self.session.post(
                f"{self.base_url}/api/auth/register",
                json={"email": new_email, "password": self.test_password},
                headers={"Content-Type": "application/json"},
                timeout=10
            )

            # Now login
            payload = {
                "email": new_email,
                "password": self.test_password
            }

            response = self.session.post(
                f"{self.base_url}/api/auth/login",
                json=payload,
                headers={"Content-Type": "application/json"},
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                passed = (
                    "access_token" in data and
                    "refresh_token" in data and
                    data.get("token_type") == "bearer"
                )
            else:
                passed = False

            self.print_test(
                "User Login",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("User Login", False, f"Error: {str(e)}")
            return False

    def test_invalid_login(self):
        """Test 6: Invalid Login Credentials"""
        try:
            payload = {
                "email": "nonexistent@example.com",
                "password": "wrongpassword"
            }

            response = self.session.post(
                f"{self.base_url}/api/auth/login",
                json=payload,
                headers={"Content-Type": "application/json"},
                timeout=10
            )

            # Should fail with 401 Unauthorized
            passed = response.status_code == 401

            self.print_test(
                "Invalid Login Credentials",
                passed,
                f"Status: {response.status_code} (expected 401)"
            )
            return passed
        except Exception as e:
            self.print_test("Invalid Login Credentials", False, f"Error: {str(e)}")
            return False

    def test_dashboard_info_authenticated(self):
        """Test 7: Dashboard Info (Authenticated)"""
        if not self.access_token:
            self.print_test("Dashboard Info (Authenticated)", False, "No access token available")
            return False

        try:
            headers = {
                "Authorization": f"Bearer {self.access_token}"
            }

            response = self.session.get(
                f"{self.base_url}/api/dashboard/info",
                headers=headers,
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                passed = "email" in data
            else:
                passed = False

            self.print_test(
                "Dashboard Info (Authenticated)",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("Dashboard Info (Authenticated)", False, f"Error: {str(e)}")
            return False

    def test_dashboard_info_unauthenticated(self):
        """Test 8: Dashboard Info (Unauthenticated)"""
        try:
            response = self.session.get(
                f"{self.base_url}/api/dashboard/info",
                timeout=10
            )

            # Should fail with 401 or 403
            passed = response.status_code in [401, 403]

            self.print_test(
                "Dashboard Info (Unauthenticated)",
                passed,
                f"Status: {response.status_code} (expected 401/403)"
            )
            return passed
        except Exception as e:
            self.print_test("Dashboard Info (Unauthenticated)", False, f"Error: {str(e)}")
            return False

    def test_vpn_generate(self):
        """Test 9: VPN Config Generation"""
        if not self.access_token:
            self.print_test("VPN Config Generation", False, "No access token available")
            return False

        try:
            headers = {
                "Authorization": f"Bearer {self.access_token}",
                "Content-Type": "application/json"
            }

            response = self.session.post(
                f"{self.base_url}/api/vpn/generate",
                headers=headers,
                json={},
                timeout=10
            )

            passed = response.status_code == 200

            self.print_test(
                "VPN Config Generation",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("VPN Config Generation", False, f"Error: {str(e)}")
            return False

    def test_vpn_download(self):
        """Test 10: VPN Config Download"""
        if not self.access_token:
            self.print_test("VPN Config Download", False, "No access token available")
            return False

        try:
            headers = {
                "Authorization": f"Bearer {self.access_token}",
                "Content-Type": "application/json"
            }

            response = self.session.post(
                f"{self.base_url}/api/vpn/config/download",
                headers=headers,
                json={},
                timeout=10
            )

            passed = response.status_code == 200

            self.print_test(
                "VPN Config Download",
                passed,
                f"Status: {response.status_code}, Content-Type: {response.headers.get('content-type', 'N/A')}"
            )
            return passed
        except Exception as e:
            self.print_test("VPN Config Download", False, f"Error: {str(e)}")
            return False

    def test_vpn_qr_code(self):
        """Test 11: VPN QR Code Generation"""
        if not self.access_token:
            self.print_test("VPN QR Code Generation", False, "No access token available")
            return False

        try:
            headers = {
                "Authorization": f"Bearer {self.access_token}"
            }

            response = self.session.get(
                f"{self.base_url}/api/vpn/config/qr",
                headers=headers,
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                passed = "qr_base64" in data
            else:
                passed = False

            self.print_test(
                "VPN QR Code Generation",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("VPN QR Code Generation", False, f"Error: {str(e)}")
            return False

    def test_token_refresh(self):
        """Test 12: Token Refresh"""
        if not self.refresh_token:
            self.print_test("Token Refresh", False, "No refresh token available")
            return False

        try:
            payload = {
                "refresh_token": self.refresh_token
            }

            response = self.session.post(
                f"{self.base_url}/api/auth/refresh",
                json=payload,
                headers={"Content-Type": "application/json"},
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                passed = "access_token" in data and "refresh_token" in data
            else:
                passed = False

            self.print_test(
                "Token Refresh",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("Token Refresh", False, f"Error: {str(e)}")
            return False

    def test_frontend_home(self):
        """Test 13: Frontend Home Page"""
        try:
            response = self.session.get(f"{self.base_url}/home.html", timeout=10)

            passed = (
                response.status_code == 200 and
                "SecureWave" in response.text and
                "html" in response.text.lower()
            )

            self.print_test(
                "Frontend Home Page",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("Frontend Home Page", False, f"Error: {str(e)}")
            return False

    def test_frontend_login(self):
        """Test 14: Frontend Login Page"""
        try:
            response = self.session.get(f"{self.base_url}/login.html", timeout=10)

            passed = response.status_code == 200

            self.print_test(
                "Frontend Login Page",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("Frontend Login Page", False, f"Error: {str(e)}")
            return False

    def test_frontend_register(self):
        """Test 15: Frontend Register Page"""
        try:
            response = self.session.get(f"{self.base_url}/register.html", timeout=10)

            passed = response.status_code == 200

            self.print_test(
                "Frontend Register Page",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("Frontend Register Page", False, f"Error: {str(e)}")
            return False

    def test_frontend_dashboard(self):
        """Test 16: Frontend Dashboard Page"""
        try:
            response = self.session.get(f"{self.base_url}/dashboard.html", timeout=10)

            passed = response.status_code == 200

            self.print_test(
                "Frontend Dashboard Page",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("Frontend Dashboard Page", False, f"Error: {str(e)}")
            return False

    def test_api_docs(self):
        """Test 17: API Documentation"""
        try:
            response = self.session.get(f"{self.base_url}/api/docs", timeout=10)

            passed = response.status_code == 200

            self.print_test(
                "API Documentation",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("API Documentation", False, f"Error: {str(e)}")
            return False

    def test_static_css(self):
        """Test 18: Static CSS Loading"""
        try:
            response = self.session.get(f"{self.base_url}/css/professional.css", timeout=10)

            passed = (
                response.status_code == 200 and
                ("primary" in response.text.lower() or "gradient" in response.text.lower())
            )

            self.print_test(
                "Static CSS Loading",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("Static CSS Loading", False, f"Error: {str(e)}")
            return False

    def test_static_js(self):
        """Test 19: Static JavaScript Loading"""
        try:
            response = self.session.get(f"{self.base_url}/js/main.js", timeout=10)

            passed = (
                response.status_code == 200 and
                "function" in response.text.lower()
            )

            self.print_test(
                "Static JavaScript Loading",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("Static JavaScript Loading", False, f"Error: {str(e)}")
            return False

    def test_logo_svg(self):
        """Test 20: Logo SVG Loading"""
        try:
            response = self.session.get(f"{self.base_url}/img/logo.svg", timeout=10)

            passed = (
                response.status_code == 200 and
                "svg" in response.text.lower()
            )

            self.print_test(
                "Logo SVG Loading",
                passed,
                f"Status: {response.status_code}"
            )
            return passed
        except Exception as e:
            self.print_test("Logo SVG Loading", False, f"Error: {str(e)}")
            return False

    def run_all_tests(self):
        """Run all tests"""
        print(f"\n{Colors.BOLD}SecureWave VPN - Comprehensive Test Suite{Colors.END}")
        print(f"Testing: {self.base_url}")

        # Infrastructure Tests
        self.print_header("INFRASTRUCTURE TESTS")
        self.test_health_check()
        self.test_ready_check()

        # Authentication Tests
        self.print_header("AUTHENTICATION TESTS")
        self.test_registration()
        self.test_duplicate_registration()
        self.test_login()
        self.test_invalid_login()
        self.test_token_refresh()

        # API Endpoint Tests
        self.print_header("API ENDPOINT TESTS")
        self.test_dashboard_info_authenticated()
        self.test_dashboard_info_unauthenticated()
        self.test_vpn_generate()
        self.test_vpn_download()
        self.test_vpn_qr_code()

        # Frontend Tests
        self.print_header("FRONTEND TESTS")
        self.test_frontend_home()
        self.test_frontend_login()
        self.test_frontend_register()
        self.test_frontend_dashboard()

        # Static Asset Tests
        self.print_header("STATIC ASSET TESTS")
        self.test_static_css()
        self.test_static_js()
        self.test_logo_svg()
        self.test_api_docs()

        # Summary
        self.print_summary()

    def print_summary(self):
        """Print test summary"""
        self.print_header("TEST SUMMARY")

        pass_rate = (self.passed_tests / self.total_tests * 100) if self.total_tests > 0 else 0

        print(f"Total Tests:  {self.total_tests}")
        print(f"{Colors.GREEN}Passed:       {self.passed_tests}{Colors.END}")
        print(f"{Colors.RED}Failed:       {self.failed_tests}{Colors.END}")
        print(f"Pass Rate:    {pass_rate:.1f}%\n")

        if self.failed_tests == 0:
            print(f"{Colors.GREEN}{Colors.BOLD}ALL TESTS PASSED!{Colors.END}\n")
            return 0
        else:
            print(f"{Colors.RED}{Colors.BOLD}SOME TESTS FAILED{Colors.END}\n")
            return 1

def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description='SecureWave VPN Test Suite')
    parser.add_argument('--url', default=BASE_URL, help='Base URL to test (default: production)')
    parser.add_argument('--local', action='store_true', help='Test local instance (http://localhost:8080)')

    args = parser.parse_args()

    base_url = "http://localhost:8080" if args.local else args.url

    tester = SecureWaveTest(base_url=base_url)
    exit_code = tester.run_all_tests()

    sys.exit(exit_code)

if __name__ == "__main__":
    main()
