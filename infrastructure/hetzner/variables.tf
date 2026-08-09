variable "hcloud_token" {
  description = "Hetzner Cloud API token (set via TF_VAR_hcloud_token from HETZNER_API_TOKEN)."
  type        = string
  sensitive   = true
}

variable "server_type" {
  description = "Server type (cx23 or cx33 only)."
  type        = string
  default     = "cx33"

  validation {
    condition     = contains(["cx23", "cx33"], var.server_type)
    error_message = "server_type must be cx23 or cx33."
  }
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
  description = "The one Hetzner location for the beta target."
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

variable "server_name" {
  description = "Name of the one SecureWave WireGuard server."
  type        = string
  default     = "securewave-beta"
}

variable "firewall_name" {
  description = "Firewall name."
  type        = string
  default     = "securewave-fw"
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH in."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.ssh_allowed_cidrs, "0.0.0.0/0") && !contains(var.ssh_allowed_cidrs, "::/0")
    error_message = "ssh_allowed_cidrs must not allow the entire internet (0.0.0.0/0 or ::/0)."
  }
}
