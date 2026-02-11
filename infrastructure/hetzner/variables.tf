variable "hcloud_token" {
  description = "Hetzner Cloud API token (set via TF_VAR_hcloud_token from HETZNER_API_TOKEN)."
  type        = string
  sensitive   = true
}

variable "server_type" {
  description = "Server type (cx33 only)."
  type        = string
  default     = "cx33"

  validation {
    condition     = var.server_type == "cx33"
    error_message = "server_type must be cx33."
  }
}

variable "node_count" {
  description = "Number of servers to provision (default: 1)."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count == 1 || var.allow_scale
    error_message = "node_count > 1 requires allow_scale = true."
  }
}

variable "allow_scale" {
  description = "Manual flag required to scale beyond 1 server."
  type        = bool
  default     = false
}

variable "image" {
  description = "Ubuntu LTS image only."
  type        = string
  default     = "ubuntu-22.04"

  validation {
    condition     = contains(["ubuntu-22.04", "ubuntu-24.04"], var.image)
    error_message = "image must be an Ubuntu LTS release (ubuntu-22.04 or ubuntu-24.04)."
  }
}

variable "location" {
  description = "Hetzner location code. Default balances Barbados + Europe latency."
  type        = string
  default     = "ash"
}

variable "ssh_key_names" {
  description = "List of Hetzner SSH key names to attach to the server."
  type        = list(string)

  validation {
    condition     = length(var.ssh_key_names) > 0
    error_message = "ssh_key_names must include at least one key name."
  }
}

variable "server_name_prefix" {
  description = "Prefix for server names."
  type        = string
  default     = "securewave"
}

variable "firewall_name" {
  description = "Firewall name."
  type        = string
  default     = "securewave-fw"
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH in."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "allow_http_https" {
  description = "Optional: open 80/443. Defaults to false to deny all else."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to Hetzner resources."
  type        = list(string)
  default     = ["securewave"]
}
