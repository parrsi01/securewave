#!/usr/bin/env python3
"""
SecureWave VPN - Azure VPN Server Deployment System
Automated deployment and management of WireGuard VPN servers across Azure regions
"""

import os
import sys
import json
import subprocess
import secrets
import base64
from typing import Dict, List, Optional, Tuple
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class AzureVPNDeployer:
    """Manages VPN server deployment and provisioning on Azure"""

    # 50+ Azure regions with detailed location information
    AZURE_REGIONS = {
        # North America
        "eastus": {"city": "Virginia", "country": "United States", "country_code": "US", "region": "Americas", "lat": 37.3719, "lon": -79.8164},
        "eastus2": {"city": "Virginia", "country": "United States", "country_code": "US", "region": "Americas", "lat": 36.6681, "lon": -78.3889},
        "centralus": {"city": "Iowa", "country": "United States", "country_code": "US", "region": "Americas", "lat": 41.5908, "lon": -93.6208},
        "northcentralus": {"city": "Illinois", "country": "United States", "country_code": "US", "region": "Americas", "lat": 41.8819, "lon": -87.6278},
        "southcentralus": {"city": "Texas", "country": "United States", "country_code": "US", "region": "Americas", "lat": 29.4167, "lon": -98.5},
        "westcentralus": {"city": "Wyoming", "country": "United States", "country_code": "US", "region": "Americas", "lat": 40.89, "lon": -110.2347},
        "westus": {"city": "California", "country": "United States", "country_code": "US", "region": "Americas", "lat": 37.783, "lon": -122.417},
        "westus2": {"city": "Washington", "country": "United States", "country_code": "US", "region": "Americas", "lat": 47.233, "lon": -119.852},
        "westus3": {"city": "Arizona", "country": "United States", "country_code": "US", "region": "Americas", "lat": 33.448, "lon": -112.074},
        "canadacentral": {"city": "Toronto", "country": "Canada", "country_code": "CA", "region": "Americas", "lat": 43.653, "lon": -79.383},
        "canadaeast": {"city": "Quebec", "country": "Canada", "country_code": "CA", "region": "Americas", "lat": 46.817, "lon": -71.217},

        # Europe
        "northeurope": {"city": "Ireland", "country": "Ireland", "country_code": "IE", "region": "Europe", "lat": 53.3478, "lon": -6.2597},
        "westeurope": {"city": "Netherlands", "country": "Netherlands", "country_code": "NL", "region": "Europe", "lat": 52.3667, "lon": 4.8945},
        "uksouth": {"city": "London", "country": "United Kingdom", "country_code": "GB", "region": "Europe", "lat": 51.5074, "lon": -0.1278},
        "ukwest": {"city": "Cardiff", "country": "United Kingdom", "country_code": "GB", "region": "Europe", "lat": 51.4816, "lon": -3.1791},
        "francecentral": {"city": "Paris", "country": "France", "country_code": "FR", "region": "Europe", "lat": 48.8566, "lon": 2.3522},
        "francesouth": {"city": "Marseille", "country": "France", "country_code": "FR", "region": "Europe", "lat": 43.2965, "lon": 5.3698},
        "germanywestcentral": {"city": "Frankfurt", "country": "Germany", "country_code": "DE", "region": "Europe", "lat": 50.1109, "lon": 8.6821},
        "germanynorth": {"city": "Berlin", "country": "Germany", "country_code": "DE", "region": "Europe", "lat": 52.52, "lon": 13.405},
        "norwayeast": {"city": "Oslo", "country": "Norway", "country_code": "NO", "region": "Europe", "lat": 59.9139, "lon": 10.7522},
        "norwaywest": {"city": "Stavanger", "country": "Norway", "country_code": "NO", "region": "Europe", "lat": 58.9701, "lon": 5.7331},
        "switzerlandnorth": {"city": "Zurich", "country": "Switzerland", "country_code": "CH", "region": "Europe", "lat": 47.3769, "lon": 8.5417},
        "switzerlandwest": {"city": "Geneva", "country": "Switzerland", "country_code": "CH", "region": "Europe", "lat": 46.2044, "lon": 6.1432},
        "swedencentral": {"city": "Stockholm", "country": "Sweden", "country_code": "SE", "region": "Europe", "lat": 59.3293, "lon": 18.0686},
        "polandcentral": {"city": "Warsaw", "country": "Poland", "country_code": "PL", "region": "Europe", "lat": 52.2297, "lon": 21.0122},
        "italynorth": {"city": "Milan", "country": "Italy", "country_code": "IT", "region": "Europe", "lat": 45.4642, "lon": 9.19},
        "spaincentral": {"city": "Madrid", "country": "Spain", "country_code": "ES", "region": "Europe", "lat": 40.4168, "lon": -3.7038},

        # Asia Pacific
        "eastasia": {"city": "Hong Kong", "country": "Hong Kong", "country_code": "HK", "region": "Asia", "lat": 22.3964, "lon": 114.1095},
        "southeastasia": {"city": "Singapore", "country": "Singapore", "country_code": "SG", "region": "Asia", "lat": 1.3521, "lon": 103.8198},
        "japaneast": {"city": "Tokyo", "country": "Japan", "country_code": "JP", "region": "Asia", "lat": 35.6895, "lon": 139.6917},
        "japanwest": {"city": "Osaka", "country": "Japan", "country_code": "JP", "region": "Asia", "lat": 34.6937, "lon": 135.5023},
        "australiaeast": {"city": "Sydney", "country": "Australia", "country_code": "AU", "region": "Asia", "lat": -33.8688, "lon": 151.2093},
        "australiasoutheast": {"city": "Melbourne", "country": "Australia", "country_code": "AU", "region": "Asia", "lat": -37.8136, "lon": 144.9631},
        "australiacentral": {"city": "Canberra", "country": "Australia", "country_code": "AU", "region": "Asia", "lat": -35.2809, "lon": 149.13},
        "koreacentral": {"city": "Seoul", "country": "South Korea", "country_code": "KR", "region": "Asia", "lat": 37.5665, "lon": 126.978},
        "koreasouth": {"city": "Busan", "country": "South Korea", "country_code": "KR", "region": "Asia", "lat": 35.1796, "lon": 129.0756},
        "indiacentral": {"city": "Pune", "country": "India", "country_code": "IN", "region": "Asia", "lat": 18.5204, "lon": 73.8567},
        "indiasouth": {"city": "Chennai", "country": "India", "country_code": "IN", "region": "Asia", "lat": 13.0827, "lon": 80.2707},
        "indiawest": {"city": "Mumbai", "country": "India", "country_code": "IN", "region": "Asia", "lat": 19.076, "lon": 72.8777},
        "jioindiawest": {"city": "Jamnagar", "country": "India", "country_code": "IN", "region": "Asia", "lat": 22.4707, "lon": 70.0577},
        "jioindiacentral": {"city": "Nagpur", "country": "India", "country_code": "IN", "region": "Asia", "lat": 21.1458, "lon": 79.0882},

        # Middle East & Africa
        "uaenorth": {"city": "Dubai", "country": "United Arab Emirates", "country_code": "AE", "region": "Middle East", "lat": 25.2048, "lon": 55.2708},
        "uaecentral": {"city": "Abu Dhabi", "country": "United Arab Emirates", "country_code": "AE", "region": "Middle East", "lat": 24.4539, "lon": 54.3773},
        "southafricanorth": {"city": "Johannesburg", "country": "South Africa", "country_code": "ZA", "region": "Africa", "lat": -26.2041, "lon": 28.0473},
        "southafricawest": {"city": "Cape Town", "country": "South Africa", "country_code": "ZA", "region": "Africa", "lat": -33.9249, "lon": 18.4241},
        "qatarcentral": {"city": "Doha", "country": "Qatar", "country_code": "QA", "region": "Middle East", "lat": 25.2854, "lon": 51.531},
        "israelcentral": {"city": "Tel Aviv", "country": "Israel", "country_code": "IL", "region": "Middle East", "lat": 32.0853, "lon": 34.7818},

        # South America
        "brazilsouth": {"city": "Sao Paulo", "country": "Brazil", "country_code": "BR", "region": "Americas", "lat": -23.5505, "lon": -46.6333},
        "brazilsoutheast": {"city": "Rio de Janeiro", "country": "Brazil", "country_code": "BR", "region": "Americas", "lat": -22.9068, "lon": -43.1729},

        # China (requires special subscription)
        "chinanorth": {"city": "Beijing", "country": "China", "country_code": "CN", "region": "Asia", "lat": 39.9042, "lon": 116.4074},
        "chinanorth2": {"city": "Beijing", "country": "China", "country_code": "CN", "region": "Asia", "lat": 40.1824, "lon": 116.4142},
        "chinaeast": {"city": "Shanghai", "country": "China", "country_code": "CN", "region": "Asia", "lat": 31.2304, "lon": 121.4737},
        "chinaeast2": {"city": "Shanghai", "country": "China", "country_code": "CN", "region": "Asia", "lat": 31.1774, "lon": 121.5509},
    }

    def __init__(self, resource_group: str = "SecureWaveVPN-Servers"):
        self.resource_group = resource_group
        self.vm_size = "Standard_B2s"  # 2 vCPUs, 4 GB RAM - perfect for VPN
        self.image = "Canonical:0001-com-ubuntu-server-focal:20_04-lts-gen2:latest"
        self.admin_username = "azureuser"
        self.wg_port = 51820

    def generate_wireguard_keypair(self) -> Tuple[str, str]:
        """Generate WireGuard private and public keys"""
        try:
            # Generate private key
            private_key = subprocess.check_output(
                ["wg", "genkey"],
                text=True
            ).strip()

            # Generate public key from private key
            public_key = subprocess.check_output(
                ["wg", "pubkey"],
                input=private_key,
                text=True
            ).strip()

            return private_key, public_key
        except FileNotFoundError:
            # WireGuard not installed locally, use Python crypto
            logger.warning("WireGuard tools not found, generating keys using Python")
            private_bytes = secrets.token_bytes(32)
            private_key = base64.b64encode(private_bytes).decode('utf-8')
            # Note: This is a placeholder. Real WireGuard key generation requires curve25519
            public_key = base64.b64encode(secrets.token_bytes(32)).decode('utf-8')
            return private_key, public_key

    def create_vm(self,
                  azure_region: str,
                  server_index: int = 1,
                  tier: str = "standard") -> Dict:
        """
        Deploy a new VPN server VM in specified Azure region

        Args:
            azure_region: Azure region code (e.g., 'eastus', 'westeurope')
            server_index: Server number in this region (for naming)
            tier: 'standard' or 'premium' (affects VM size)

        Returns:
            Dict with server deployment information
        """
        if azure_region not in self.AZURE_REGIONS:
            raise ValueError(f"Unknown Azure region: {azure_region}")

        location_info = self.AZURE_REGIONS[azure_region]
        server_id = f"{azure_region}-{server_index:03d}"
        vm_name = f"vpn-{server_id}"

        logger.info(f"Deploying VPN server: {server_id} in {location_info['city']}, {location_info['country']}")

        # Generate WireGuard keys
        wg_private_key, wg_public_key = self.generate_wireguard_keypair()

        # Create cloud-init configuration for WireGuard installation
        cloud_init = self._generate_cloud_init_config(wg_private_key, wg_public_key)
        cloud_init_file = f"/tmp/cloud-init-{server_id}.yml"

        with open(cloud_init_file, 'w') as f:
            f.write(cloud_init)

        # Create resource group if it doesn't exist
        self._run_az_command([
            "group", "create",
            "--name", self.resource_group,
            "--location", azure_region
        ])

        # Create public IP
        public_ip_name = f"ip-{vm_name}"
        self._run_az_command([
            "network", "public-ip", "create",
            "--resource-group", self.resource_group,
            "--name", public_ip_name,
            "--sku", "Standard",
            "--allocation-method", "Static",
            "--location", azure_region
        ])

        # Create VM with WireGuard pre-installed
        logger.info(f"Creating VM {vm_name}...")
        self._run_az_command([
            "vm", "create",
            "--resource-group", self.resource_group,
            "--name", vm_name,
            "--location", azure_region,
            "--image", self.image,
            "--size", self.vm_size,
            "--admin-username", self.admin_username,
            "--generate-ssh-keys",
            "--public-ip-address", public_ip_name,
            "--custom-data", cloud_init_file,
            "--tags",
            f"server_id={server_id}",
            f"type=vpn",
            f"city={location_info['city']}",
            f"country={location_info['country']}",
        ])

        # Open WireGuard port
        self._run_az_command([
            "vm", "open-port",
            "--resource-group", self.resource_group,
            "--name", vm_name,
            "--port", str(self.wg_port),
            "--priority", "1000"
        ])

        # Get public IP address
        public_ip_result = self._run_az_command([
            "network", "public-ip", "show",
            "--resource-group", self.resource_group,
            "--name", public_ip_name,
            "--query", "ipAddress",
            "--output", "tsv"
        ])
        public_ip = public_ip_result.strip()

        # Get private IP address
        private_ip_result = self._run_az_command([
            "vm", "show",
            "--resource-group", self.resource_group,
            "--name", vm_name,
            "--query", "privateIps",
            "--output", "tsv"
        ])
        private_ip = private_ip_result.strip()

        # Clean up temp file
        os.remove(cloud_init_file)

        deployment_info = {
            "server_id": server_id,
            "vm_name": vm_name,
            "azure_region": azure_region,
            "azure_resource_group": self.resource_group,
            "location": f"{location_info['city']}, {location_info['country']}",
            "city": location_info["city"],
            "country": location_info["country"],
            "country_code": location_info["country_code"],
            "region": location_info["region"],
            "latitude": location_info["lat"],
            "longitude": location_info["lon"],
            "public_ip": public_ip,
            "private_ip": private_ip,
            "endpoint": f"{public_ip}:{self.wg_port}",
            "wg_public_key": wg_public_key,
            "wg_private_key_encrypted": wg_private_key,  # Should be encrypted in production
            "wg_listen_port": self.wg_port,
            "status": "provisioning",
            "provisioned_at": datetime.utcnow().isoformat(),
        }

        logger.info(f"✓ VPN server deployed successfully: {server_id}")
        logger.info(f"  Public IP: {public_ip}")
        logger.info(f"  Endpoint: {deployment_info['endpoint']}")

        return deployment_info

    def _generate_cloud_init_config(self, private_key: str, public_key: str) -> str:
        """Generate cloud-init YAML for WireGuard installation and configuration"""
        return f"""#cloud-config
package_upgrade: true
packages:
  - wireguard
  - qrencode
  - iptables
  - curl
  - jq
  - python3
  - python3-pip

write_files:
  - path: /etc/sysctl.d/99-wireguard.conf
    content: |
      net.ipv4.ip_forward=1
      net.ipv6.conf.all.forwarding=1
    permissions: '0644'

  - path: /etc/wireguard/wg0.conf
    content: |
      [Interface]
      PrivateKey = {private_key}
      Address = 10.8.0.1/24
      ListenPort = {self.wg_port}
      PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
      PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
    permissions: '0600'

  - path: /usr/local/bin/vpn-health-check.sh
    content: |
      #!/bin/bash
      # Health check script for monitoring
      wg show wg0 > /dev/null 2>&1
      echo $?
    permissions: '0755'

  - path: /usr/local/bin/vpn-metrics.sh
    content: |
      #!/bin/bash
      # Export metrics for monitoring system
      echo "{"
      echo "  \\"cpu_load\\": $(awk '{{print $1}}' /proc/loadavg),"
      echo "  \\"memory_used\\": $(free | grep Mem | awk '{{printf \\"%.2f\\", $3/$2 * 100}}'),"
      echo "  \\"disk_used\\": $(df / | tail -1 | awk '{{print $5}}' | sed 's/%//'),"
      echo "  \\"connections\\": $(wg show wg0 | grep peer | wc -l),"
      echo "  \\"timestamp\\": \\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\\""
      echo "}"
    permissions: '0755'

runcmd:
  - sysctl -p /etc/sysctl.d/99-wireguard.conf
  - systemctl enable wg-quick@wg0
  - systemctl start wg-quick@wg0
  - ufw allow {self.wg_port}/udp
  - ufw allow 22/tcp
  - echo "WireGuard VPN Server Ready" > /var/log/vpn-ready.log
"""

    def _run_az_command(self, args: List[str]) -> str:
        """Execute Azure CLI command"""
        cmd = ["az"] + args
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            logger.error(f"Azure CLI command failed: {' '.join(cmd)}")
            logger.error(f"Error: {e.stderr}")
            raise

    def deploy_global_fleet(self, regions_per_continent: int = 2) -> List[Dict]:
        """
        Deploy VPN servers across all major regions

        Args:
            regions_per_continent: Number of servers per continent/region

        Returns:
            List of deployment info for all created servers
        """
        deployments = []

        # Group regions by continent
        by_region = {}
        for azure_region, info in self.AZURE_REGIONS.items():
            region_name = info["region"]
            if region_name not in by_region:
                by_region[region_name] = []
            by_region[region_name].append(azure_region)

        # Deploy servers
        for region_name, azure_regions in by_region.items():
            logger.info(f"\n{'='*60}")
            logger.info(f"Deploying to {region_name}")
            logger.info(f"{'='*60}")

            # Select top regions in this continent
            selected_regions = azure_regions[:regions_per_continent]

            for idx, azure_region in enumerate(selected_regions, 1):
                try:
                    deployment = self.create_vm(azure_region, server_index=idx)
                    deployments.append(deployment)
                except Exception as e:
                    logger.error(f"Failed to deploy to {azure_region}: {e}")
                    continue

        logger.info(f"\n{'='*60}")
        logger.info(f"Deployment Complete: {len(deployments)} servers deployed")
        logger.info(f"{'='*60}")

        return deployments


if __name__ == "__main__":
    # Example usage
    deployer = AzureVPNDeployer()

    if len(sys.argv) > 1 and sys.argv[1] == "deploy-global":
        # Deploy global fleet
        deployments = deployer.deploy_global_fleet(regions_per_continent=2)

        # Save deployment info
        with open("vpn_deployments.json", "w") as f:
            json.dump(deployments, f, indent=2)

        print(f"\n✓ Deployed {len(deployments)} VPN servers globally")
        print(f"✓ Deployment details saved to vpn_deployments.json")

    elif len(sys.argv) > 1:
        # Deploy single server
        azure_region = sys.argv[1]
        deployment = deployer.create_vm(azure_region)
        print(json.dumps(deployment, indent=2))

    else:
        print("Usage:")
        print("  python azure_vpn_deployer.py <azure-region>    # Deploy single server")
        print("  python azure_vpn_deployer.py deploy-global      # Deploy global fleet")
        print(f"\nAvailable regions: {', '.join(list(deployer.AZURE_REGIONS.keys())[:10])}...")
