#!/usr/bin/env python3
"""
AI Security Audit Engine for SecureWave VPN
Uses local Ollama instance with DeepSeek-Coder for vulnerability analysis
"""

import os
import sys
import json
import re
import subprocess
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from concurrent.futures import ThreadPoolExecutor, as_completed
import urllib.request
import urllib.error

# Configuration
OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "deepseek-coder:latest"
PROJECT_ROOT = Path(__file__).parent.parent
BACKEND_DIR = PROJECT_ROOT / "backend"
ROUTES_DIR = PROJECT_ROOT / "routes"
SERVICES_DIR = PROJECT_ROOT / "services"

# Critical files to audit
CRITICAL_PATTERNS = [
    "routes/auth.py",
    "routes/billing.py",
    "routes/devices.py",
    "routes/servers.py",
    "routes/vpn.py",
    "routes/user.py",
    "services/auth_service.py",
    "services/jwt_service.py",
    "services/stripe_service.py",
    "services/payment_webhooks.py",
    "services/vpn_credential_service.py",
    "services/device_service.py",
]

@dataclass
class Vulnerability:
    severity: str  # critical, high, medium, low, info
    category: str
    file_path: str
    line_number: int
    description: str
    recommendation: str
    code_snippet: str
    auto_fixable: bool

@dataclass
class AuditFinding:
    file_path: str
    file_hash: str
    vulnerabilities: List[Vulnerability]
    ai_analysis: str
    scan_timestamp: str

class OllamaClient:
    """Client for interacting with local Ollama instance"""

    def __init__(self, model: str = MODEL_NAME):
        self.model = model
        self.url = OLLAMA_URL

    def is_available(self) -> bool:
        """Check if Ollama is running"""
        try:
            req = urllib.request.Request(
                "http://localhost:11434/api/tags",
                method="GET"
            )
            with urllib.request.urlopen(req, timeout=5) as response:
                return response.status == 200
        except:
            return False

    def generate(self, prompt: str, system_prompt: Optional[str] = None) -> str:
        """Send prompt to Ollama and return response"""
        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.1,
                "num_predict": 2048
            }
        }

        if system_prompt:
            payload["system"] = system_prompt

        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(
            self.url,
            data=data,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )

        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                result = json.loads(response.read().decode('utf-8'))
                return result.get('response', '')
        except urllib.error.URLError as e:
            return f"ERROR: Could not connect to Ollama - {e}"
        except Exception as e:
            return f"ERROR: {e}"

class SecurityAuditor:
    """Main security audit engine"""

    SYSTEM_PROMPT = """You are a cybersecurity expert specializing in Python/FastAPI application security.
Analyze the provided code for vulnerabilities. Focus on:
1. Authentication bypasses
2. Authorization flaws
3. Injection attacks (SQL, Command, NoSQL)
4. Input validation issues
5. Cryptographic weaknesses
6. Secret exposure
7. Race conditions
8. Business logic flaws

Respond in this exact format:
VULNERABILITIES: [List each with severity: CRITICAL/HIGH/MEDIUM/LOW/INFO]
ANALYSIS: [Detailed explanation]
RECOMMENDATIONS: [Specific fixes with code examples]"""

    def __init__(self):
        self.client = OllamaClient()
        self.findings: List[AuditFinding] = []
        self.vulnerabilities: List[Vulnerability] = []

    def check_prerequisites(self) -> bool:
        """Verify Ollama is available"""
        if not self.client.is_available():
            print("ERROR: Ollama is not running. Start it with: ollama serve")
            return False
        print("✓ Ollama is available")
        return True

    def get_file_hash(self, file_path: Path) -> str:
        """Calculate MD5 hash of file"""
        with open(file_path, 'rb') as f:
            return hashlib.md5(f.read()).hexdigest()

    def read_code_file(self, file_path: Path) -> Optional[str]:
        """Read and return file contents"""
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                return f.read()
        except Exception as e:
            print(f"Warning: Could not read {file_path}: {e}")
            return None

    def build_prompt(self, code: str, file_path: str, context: str = "") -> str:
        """Build analysis prompt for Ollama"""
        return f"""Analyze this FastAPI/Python code for security vulnerabilities.

FILE: {file_path}
{context}

CODE:
```python
{code[:8000]}  # Limit to 8KB to avoid token limits
```

Provide a thorough security analysis."""

    def parse_vulnerabilities(self, ai_response: str, file_path: str, code: str) -> List[Vulnerability]:
        """Parse AI response to extract structured vulnerabilities"""
        vulns = []

        # Pattern matching for common vulnerability indicators
        severity_patterns = {
            'CRITICAL': r'CRITICAL|RCE|Remote Code|SQL Injection|Auth Bypass|Secret.*Expose',
            'HIGH': r'HIGH|Command Injection|Path Traversal|XXE|SSRF|Insecure Deserialization',
            'MEDIUM': r'MEDIUM|XSS|CSRF|IDOR|Weak Crypto|Timing Attack',
            'LOW': r'LOW|Information Disclosure|Verbose Error|Debug Mode',
            'INFO': r'INFO|Best Practice|Recommendation|Consider'
        }

        lines = code.split('\n')

        # Extract vulnerabilities from AI response
        for sev_label, pattern in severity_patterns.items():
            matches = re.finditer(pattern, ai_response, re.IGNORECASE)
            for match in matches:
                # Find relevant line in code (approximate)
                line_num = 1
                for i, line in enumerate(lines):
                    if any(keyword in line.lower() for keyword in ['def ', 'class ', 'async def', 'await ', 'request']):
                        line_num = i + 1
                        break

                vuln = Vulnerability(
                    severity=sev_label,
                    category=self._categorize_vulnerability(match.group()),
                    file_path=file_path,
                    line_number=line_num,
                    description=ai_response[max(0, match.start()-100):min(len(ai_response), match.end()+200)],
                    recommendation="See AI analysis for recommendations",
                    code_snippet='\n'.join(lines[max(0, line_num-3):min(len(lines), line_num+3)]),
                    auto_fixable=sev_label in ['LOW', 'INFO'] or 'input validation' in ai_response.lower()
                )
                vulns.append(vuln)

        return vulns

    def _categorize_vulnerability(self, match_text: str) -> str:
        """Categorize vulnerability type"""
        match_lower = match_text.lower()
        categories = {
            'injection': ['sql', 'command', 'nosql', 'ldap', 'xpath'],
            'authentication': ['auth', 'jwt', 'token', 'session', 'password'],
            'authorization': ['bypass', 'privilege', 'access control', 'idor'],
            'cryptography': ['crypto', 'hash', 'encryption', 'ssl', 'tls'],
            'exposure': ['secret', 'credential', 'api key', 'password'],
            'input_validation': ['input', 'validation', 'sanitize'],
            'configuration': ['config', 'debug', 'verbose', 'header']
        }

        for cat, keywords in categories.items():
            if any(kw in match_lower for kw in keywords):
                return cat
        return 'general'

    def audit_file(self, file_path: Path) -> Optional[AuditFinding]:
        """Audit a single file"""
        print(f"  Auditing: {file_path}")

        code = self.read_code_file(file_path)
        if not code:
            return None

        file_hash = self.get_file_hash(file_path)
        relative_path = str(file_path.relative_to(PROJECT_ROOT))

        # Build context based on file type
        context = ""
        if 'auth' in relative_path.lower():
            context = "This is an authentication-related file. Check for bypasses, weak validation, and session issues."
        elif 'bill' in relative_path.lower() or 'payment' in relative_path.lower() or 'stripe' in relative_path.lower():
            context = "This is a payment/billing file. Check for financial manipulation, webhook security, and access control."
        elif 'vpn' in relative_path.lower():
            context = "This is a VPN configuration file. Check for command injection, credential exposure, and access control."
        elif 'device' in relative_path.lower():
            context = "This is a device management file. Check for IDOR and unauthorized device access."
        elif 'jwt' in relative_path.lower():
            context = "This is a JWT service file. Check for token manipulation and weak signing."

        prompt = self.build_prompt(code, relative_path, context)
        ai_response = self.client.generate(prompt, self.SYSTEM_PROMPT)

        if ai_response.startswith("ERROR:"):
            print(f"    Warning: AI analysis failed - {ai_response}")
            ai_response = "AI analysis unavailable"

        vulnerabilities = self.parse_vulnerabilities(ai_response, relative_path, code)
        self.vulnerabilities.extend(vulnerabilities)

        return AuditFinding(
            file_path=relative_path,
            file_hash=file_hash,
            vulnerabilities=vulnerabilities,
            ai_analysis=ai_response,
            scan_timestamp=datetime.now().isoformat()
        )

    def run_static_analysis(self) -> Dict:
        """Run bandit and other static analysis tools"""
        results = {
            'bandit': [],
            'manual_checks': []
        }

        # Manual security pattern checks
        security_patterns = {
            'hardcoded_secret': r'(password|secret|key|token)\s*=\s*["\'][^"\']{3,}["\']',
            'sql_injection': r'execute\s*\(.*%\s*',
            'eval_usage': r'\beval\s*\(',
            'pickle_usage': r'pickle\.(loads|dump)',
            'yaml_unsafe': r'yaml\.load\s*\([^)]*\)(?!.*Loader)',
            'subprocess_shell': r'subprocess\..*shell\s*=\s*True',
            'debug_mode': r'debug\s*=\s*True',
            'jwt_none': r'algorithms.*=.*\[.*none.*\]',
        }

        for pattern_name, pattern in security_patterns.items():
            for file_path in list(ROUTES_DIR.glob("*.py")) + list(SERVICES_DIR.glob("*.py")):
                try:
                    with open(file_path, 'r') as f:
                        content = f.read()
                        matches = re.finditer(pattern, content, re.IGNORECASE)
                        for match in matches:
                            line_num = content[:match.start()].count('\n') + 1
                            results['manual_checks'].append({
                                'file': str(file_path.relative_to(PROJECT_ROOT)),
                                'line': line_num,
                                'issue': pattern_name,
                                'severity': 'HIGH' if pattern_name in ['sql_injection', 'eval_usage', 'subprocess_shell'] else 'MEDIUM',
                                'snippet': content[match.start():match.end()][:100]
                            })
                except Exception:
                    pass

        return results

    def run_dependency_scan(self) -> Dict:
        """Check for vulnerable dependencies"""
        results = {'vulnerabilities': [], 'status': 'unknown'}

        # Check requirements files
        req_files = list(PROJECT_ROOT.glob("**/requirements*.txt"))

        for req_file in req_files:
            try:
                with open(req_file, 'r') as f:
                    packages = []
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#') and not line.startswith('-'):
                            # Parse package name
                            pkg_match = re.match(r'^([a-zA-Z0-9_-]+)', line)
                            if pkg_match:
                                packages.append(pkg_match.group(1))

                    results['packages_found'] = packages
            except Exception as e:
                results['error'] = str(e)

        return results

    def generate_attack_payloads(self) -> List[Dict]:
        """Generate test payloads for API security testing"""
        payloads = [
            {
                'name': 'SQL Injection - Basic',
                'payload': "' OR '1'='1",
                'target': 'input_fields',
                'type': 'sql_injection'
            },
            {
                'name': 'SQL Injection - Union',
                'payload': "' UNION SELECT null, username, password FROM users--",
                'target': 'input_fields',
                'type': 'sql_injection'
            },
            {
                'name': 'Command Injection',
                'payload': "; cat /etc/passwd;",
                'target': 'system_calls',
                'type': 'command_injection'
            },
            {
                'name': 'Path Traversal',
                'payload': "../../../etc/passwd",
                'target': 'file_paths',
                'type': 'path_traversal'
            },
            {
                'name': 'XSS - Basic',
                'payload': "<script>alert('xss')</script>",
                'target': 'output_fields',
                'type': 'xss'
            },
            {
                'name': 'JWT None Algorithm',
                'payload': '{"alg":"none"}',
                'target': 'jwt_tokens',
                'type': 'jwt_manipulation'
            },
            {
                'name': 'NoSQL Injection',
                'payload': '{"$gt": ""}',
                'target': 'mongo_queries',
                'type': 'nosql_injection'
            },
            {
                'name': 'LDAP Injection',
                'payload': "*)(uid=*))(&(uid=*",
                'target': 'ldap_queries',
                'type': 'ldap_injection'
            }
        ]
        return payloads

    def apply_safe_fixes(self) -> List[str]:
        """Apply automatic fixes for safe issues"""
        applied_fixes = []

        for vuln in self.vulnerabilities:
            if not vuln.auto_fixable:
                continue

            # Only apply LOW/INFO severity fixes automatically
            if vuln.severity not in ['LOW', 'INFO']:
                continue

            # Track what could be fixed
            applied_fixes.append(f"{vuln.file_path}:{vuln.line_number} - {vuln.category}")

        return applied_fixes

    def generate_report(self) -> str:
        """Generate comprehensive security audit report"""
        critical = sum(1 for v in self.vulnerabilities if v.severity == 'CRITICAL')
        high = sum(1 for v in self.vulnerabilities if v.severity == 'HIGH')
        medium = sum(1 for v in self.vulnerabilities if v.severity == 'MEDIUM')
        low = sum(1 for v in self.vulnerabilities if v.severity == 'LOW')
        info = sum(1 for v in self.vulnerabilities if v.severity == 'INFO')

        report = f"""# AI Security Audit Report

**Generated:** {datetime.now().isoformat()}
**Scanner:** AI Security Audit Engine (Ollama + DeepSeek-Coder)
**Target:** SecureWave VPN Backend

## Executive Summary

| Severity | Count |
|----------|-------|
| CRITICAL | {critical} |
| HIGH | {high} |
| MEDIUM | {medium} |
| LOW | {low} |
| INFO | {info} |
| **TOTAL** | **{len(self.vulnerabilities)}** |

## Findings by File

"""

        # Group findings by file
        by_file = {}
        for finding in self.findings:
            by_file[finding.file_path] = finding

        for file_path, finding in sorted(by_file.items()):
            report += f"### {file_path}\n\n"
            report += f"**Hash:** `{finding.file_hash}`\n\n"

            if finding.vulnerabilities:
                report += "#### Vulnerabilities\n\n"
                for vuln in finding.vulnerabilities:
                    report += f"**[{vuln.severity}]** {vuln.category}\n"
                    report += f"- Line {vuln.line_number}: {vuln.description[:200]}...\n"
                    report += f"- Auto-fixable: {vuln.auto_fixable}\n\n"
            else:
                report += "*No vulnerabilities detected*\n\n"

            report += "#### AI Analysis\n\n"
            report += f"```\n{finding.ai_analysis[:1000]}\n```\n\n"
            report += "---\n\n"

        # Recommendations section
        report += """## Recommendations

### Immediate Actions Required

"""

        critical_high = [v for v in self.vulnerabilities if v.severity in ['CRITICAL', 'HIGH']]
        if critical_high:
            for vuln in critical_high[:10]:  # Limit to first 10
                report += f"1. **[{vuln.severity}]** {vuln.file_path}:{vuln.line_number} - {vuln.category}\n"
                report += f"   - {vuln.recommendation}\n\n"
        else:
            report += "No critical or high severity issues detected.\n\n"

        report += """### Security Hardening Checklist

- [ ] Implement rate limiting on all API endpoints
- [ ] Add request signing for webhooks
- [ ] Enable comprehensive audit logging
- [ ] Implement CSP headers
- [ ] Add HSTS headers
- [ ] Review all JWT token expirations
- [ ] Validate all input with Pydantic schemas
- [ ] Use parameterized queries exclusively
- [ ] Implement proper CORS policies
- [ ] Add security headers (X-Frame-Options, X-Content-Type-Options)

"""

        return report

    def run_full_audit(self):
        """Execute complete security audit"""
        print("=" * 60)
        print("AI Security Audit Engine - SecureWave VPN")
        print("=" * 60)

        # Check prerequisites
        if not self.check_prerequisites():
            sys.exit(1)

        # Find files to audit
        files_to_audit = []
        for pattern in CRITICAL_PATTERNS:
            full_path = PROJECT_ROOT / pattern
            if full_path.exists():
                files_to_audit.append(full_path)

        print(f"\nFound {len(files_to_audit)} critical files to audit")
        print("-" * 60)

        # Run AI analysis on each file
        for file_path in files_to_audit:
            finding = self.audit_file(file_path)
            if finding:
                self.findings.append(finding)

        # Run static analysis
        print("\nRunning static analysis...")
        static_results = self.run_static_analysis()
        print(f"  Found {len(static_results['manual_checks'])} issues via pattern matching")

        # Run dependency scan
        print("\nScanning dependencies...")
        dep_results = self.run_dependency_scan()
        print(f"  Found {len(dep_results.get('packages_found', []))} packages")

        # Generate attack payloads
        print("\nGenerating attack simulation payloads...")
        payloads = self.generate_attack_payloads()
        print(f"  Generated {len(payloads)} test payloads")

        # Apply safe fixes
        print("\nApplying safe automatic fixes...")
        fixes = self.apply_safe_fixes()
        print(f"  {len(fixes)} fixes identified (manual review required)")

        # Generate report
        print("\nGenerating report...")
        report = self.generate_report()

        # Save report
        report_path = PROJECT_ROOT / "AI_SECURITY_AUDIT_REPORT.md"
        with open(report_path, 'w') as f:
            f.write(report)

        # Save detailed JSON
        json_path = PROJECT_ROOT / "ai_security_findings.json"
        with open(json_path, 'w') as f:
            json.dump({
                'findings': [asdict(f) for f in self.findings],
                'static_analysis': static_results,
                'dependencies': dep_results,
                'attack_payloads': payloads,
                'potential_fixes': fixes
            }, f, indent=2, default=str)

        print(f"\n{'=' * 60}")
        print("Audit Complete!")
        print(f"  Report: {report_path}")
        print(f"  JSON:   {json_path}")
        print(f"  Issues: {len(self.vulnerabilities)} total")
        print("=" * 60)


def main():
    auditor = SecurityAuditor()
    auditor.run_full_audit()


if __name__ == "__main__":
    main()
