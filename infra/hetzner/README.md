# Hetzner Terraform (Guardrailed)

This module provisions SecureWave VPN nodes on Hetzner Cloud only.

## Guardrails
- `server_type` is restricted to `cx33`.
- `node_count > 1` requires `allow_scale=true`.
- Destroy operations must be explicitly confirmed in automation.
- SSH ingress is CIDR-restricted via `ssh_allowed_cidrs`.

## Quick start
```bash
cp infra/hetzner/terraform.tfvars.example infra/hetzner/terraform.tfvars
export TF_VAR_hcloud_token="$HETZNER_API_TOKEN"
bash infra/hetzner/check_guardrails.sh
terraform -chdir=infra/hetzner init -input=false
terraform -chdir=infra/hetzner apply -auto-approve
```

## Safe destroy
Use `scripts/release_hetzner.sh destroy` with:
- `CONFIRM_DESTROY=YES`
- `ALLOW_DESTROY=true`
