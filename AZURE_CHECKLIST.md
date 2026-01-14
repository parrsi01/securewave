Azure VM + VPN deployment checklist

Account/subscription
- az login
- az account show
- az account list --output table

Check existing VM
- az vm list --output table
- az vm show -g <resource-group> -n <vm-name>
- az network public-ip list --output table

WireGuard VM requirements
- Ubuntu LTS VM with public IP
- UDP 51820 open on NSG and OS firewall
- /dev/net/tun available

Firewall/NSG
- az network nsg rule list -g <resource-group> --nsg-name <nsg>
- Allow UDP 51820 inbound

Next actions if VM missing
- Create resource group
- Create B1s/B1ms VM
- Install WireGuard and configure wg0

Note: az login needs network access and will write config under AZURE_CONFIG_DIR.
