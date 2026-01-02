#!/usr/bin/env python3
"""
Azure Deployment Test Script
Tests subscription quota, provider registration, and deployment capability
"""

import subprocess
import json
import sys
import time
from typing import Dict, List, Tuple

class AzureDeploymentTester:
    def __init__(self):
        self.subscription_id = None
        self.subscription_name = None
        self.issues = []
        self.fixes_applied = []

    def run_command(self, cmd: List[str], capture_output=True) -> Tuple[int, str, str]:
        """Run Azure CLI command and return exit code, stdout, stderr"""
        try:
            result = subprocess.run(
                cmd,
                capture_output=capture_output,
                text=True,
                timeout=120
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return 1, "", "Command timed out"
        except Exception as e:
            return 1, "", str(e)

    def print_section(self, title: str):
        """Print formatted section header"""
        print(f"\n{'='*70}")
        print(f"  {title}")
        print(f"{'='*70}\n")

    def check_subscription(self) -> bool:
        """Check and display subscription details"""
        self.print_section("Step 1: Checking Subscription")

        code, output, error = self.run_command(["az", "account", "show", "--output", "json"])
        if code != 0:
            print(f"❌ Failed to get subscription details: {error}")
            return False

        try:
            sub_info = json.loads(output)
            self.subscription_id = sub_info.get('id')
            self.subscription_name = sub_info.get('name')

            print(f"✅ Subscription Name: {self.subscription_name}")
            print(f"✅ Subscription ID: {self.subscription_id}")
            print(f"✅ State: {sub_info.get('state')}")
            print(f"✅ Tenant: {sub_info.get('tenantId')}")

            # Check subscription type
            quota_id = sub_info.get('subscriptionPolicies', {}).get('quotaId', 'Unknown')
            print(f"✅ Quota ID: {quota_id}")

            return True
        except json.JSONDecodeError:
            print(f"❌ Failed to parse subscription info")
            return False

    def check_providers(self) -> bool:
        """Check and register required providers"""
        self.print_section("Step 2: Checking Azure Providers")

        required_providers = [
            "Microsoft.Web",
            "Microsoft.DBforPostgreSQL",
            "Microsoft.Compute",
            "Microsoft.Storage"
        ]

        all_registered = True
        for provider in required_providers:
            code, output, error = self.run_command([
                "az", "provider", "show",
                "--namespace", provider,
                "--query", "registrationState",
                "-o", "tsv"
            ])

            if code == 0:
                state = output.strip()
                if state == "Registered":
                    print(f"✅ {provider}: Registered")
                else:
                    print(f"⚠️  {provider}: {state} - Registering now...")
                    self.run_command(["az", "provider", "register", "--namespace", provider])
                    self.fixes_applied.append(f"Registered provider: {provider}")
                    all_registered = False
            else:
                print(f"❌ {provider}: Failed to check")
                all_registered = False

        if not all_registered:
            print("\n⏳ Waiting for provider registration to complete (30 seconds)...")
            time.sleep(30)

        return True

    def test_deployment_skus(self) -> bool:
        """Test different SKUs to find one that works"""
        self.print_section("Step 3: Testing Deployment SKUs")

        test_configs = [
            {"sku": "F1", "name": "Free Tier"},
            {"sku": "B1", "name": "Basic B1"},
            {"sku": "B2", "name": "Basic B2"},
            {"sku": "S1", "name": "Standard S1"},
            {"sku": "P1V2", "name": "Premium V2 P1"},
        ]

        locations = ["eastus", "westus", "centralus"]

        for location in locations:
            print(f"\n📍 Testing location: {location}")

            for config in test_configs:
                sku = config["sku"]
                name = config["name"]

                print(f"  Testing {name} ({sku})...", end=" ")

                # Try to create a test app service plan (dry run)
                test_plan_name = f"test-plan-{int(time.time())}"
                test_rg = "test-quota-check"

                # Create test resource group
                self.run_command([
                    "az", "group", "create",
                    "--name", test_rg,
                    "--location", location,
                    "--output", "none"
                ])

                # Try to create app service plan
                code, output, error = self.run_command([
                    "az", "appservice", "plan", "create",
                    "--name", test_plan_name,
                    "--resource-group", test_rg,
                    "--location", location,
                    "--sku", sku,
                    "--is-linux",
                    "--output", "none"
                ])

                if code == 0:
                    print("✅ Available")
                    # Clean up
                    self.run_command([
                        "az", "appservice", "plan", "delete",
                        "--name", test_plan_name,
                        "--resource-group", test_rg,
                        "--yes",
                        "--output", "none"
                    ])
                    self.run_command([
                        "az", "group", "delete",
                        "--name", test_rg,
                        "--yes",
                        "--no-wait",
                        "--output", "none"
                    ])

                    print(f"\n🎉 SUCCESS! {name} ({sku}) works in {location}")
                    return True
                else:
                    if "quota" in error.lower():
                        print("❌ Quota issue")
                    else:
                        print(f"❌ Error: {error[:50]}")

                    # Clean up test resource group
                    self.run_command([
                        "az", "group", "delete",
                        "--name", test_rg,
                        "--yes",
                        "--no-wait",
                        "--output", "none"
                    ])

        return False

    def check_quota_limits(self) -> bool:
        """Check current quota limits"""
        self.print_section("Step 4: Checking Quota Limits")

        print("Attempting to retrieve quota information...")

        # Try to get compute quotas
        code, output, error = self.run_command([
            "az", "vm", "list-usage",
            "--location", "eastus",
            "--output", "table"
        ])

        if code == 0:
            print("\n📊 Compute Quotas in East US:")
            print(output[:500])  # Print first 500 chars
        else:
            print(f"⚠️  Could not retrieve quota information")

        return True

    def run_full_deployment_test(self) -> bool:
        """Run actual deployment test"""
        self.print_section("Step 5: Running Full Deployment Test")

        print("Setting up deployment environment variables...")

        env_vars = {
            "AZURE_RESOURCE_GROUP": "securewave-rg-test",
            "AZURE_APP_NAME": f"securewave-test-{int(time.time())}",
            "AZURE_LOCATION": "eastus",
            "AZURE_SKU": "F1",  # Start with free tier
            "AZURE_DB_PASSWORD": "SecureWave2026!9ZbURZ"
        }

        print(f"✅ Resource Group: {env_vars['AZURE_RESOURCE_GROUP']}")
        print(f"✅ App Name: {env_vars['AZURE_APP_NAME']}")
        print(f"✅ Location: {env_vars['AZURE_LOCATION']}")
        print(f"✅ SKU: {env_vars['AZURE_SKU']}")

        print("\n🚀 Running deployment script...")

        # Set environment variables and run script
        cmd = f"""
        export AZURE_RESOURCE_GROUP="{env_vars['AZURE_RESOURCE_GROUP']}"
        export AZURE_APP_NAME="{env_vars['AZURE_APP_NAME']}"
        export AZURE_LOCATION="{env_vars['AZURE_LOCATION']}"
        export AZURE_SKU="{env_vars['AZURE_SKU']}"
        export AZURE_DB_PASSWORD="{env_vars['AZURE_DB_PASSWORD']}"
        ./deploy_securewave_single_app.sh
        """

        code, output, error = self.run_command(["bash", "-c", cmd])

        if code == 0:
            print("✅ Deployment succeeded!")
            print(f"\n🌐 App URL: https://{env_vars['AZURE_APP_NAME']}.azurewebsites.net")
            return True
        else:
            print("❌ Deployment failed")
            print(f"\nError output:\n{error}")
            return False

    def generate_report(self):
        """Generate final report"""
        self.print_section("Deployment Test Report")

        print(f"Subscription: {self.subscription_name}")
        print(f"Subscription ID: {self.subscription_id}")

        if self.fixes_applied:
            print(f"\n✅ Fixes Applied ({len(self.fixes_applied)}):")
            for fix in self.fixes_applied:
                print(f"  - {fix}")

        if self.issues:
            print(f"\n⚠️  Issues Found ({len(self.issues)}):")
            for issue in self.issues:
                print(f"  - {issue}")

    def run(self):
        """Run all tests"""
        print("\n" + "="*70)
        print("  AZURE DEPLOYMENT DIAGNOSTIC & TEST TOOL")
        print("  SecureWave VPN Application")
        print("="*70)

        # Run all checks
        if not self.check_subscription():
            print("\n❌ Subscription check failed. Aborting.")
            return False

        self.check_providers()
        self.check_quota_limits()

        # Test deployment
        if self.test_deployment_skus():
            print("\n✅ Found working SKU configuration!")

            # Ask to proceed with full deployment
            print("\n" + "="*70)
            print("Ready to run full deployment with working configuration.")
            print("="*70)

            proceed = input("\nProceed with full deployment? (yes/no): ").strip().lower()
            if proceed == 'yes':
                self.run_full_deployment_test()
        else:
            print("\n❌ No working SKU found. Quota increase required.")
            self.issues.append("All tested SKUs require quota increase")

        self.generate_report()

        return True

if __name__ == "__main__":
    tester = AzureDeploymentTester()
    success = tester.run()
    sys.exit(0 if success else 1)
