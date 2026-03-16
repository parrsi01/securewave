provider "hcloud" {
  token = var.hcloud_token
}

data "hcloud_ssh_key" "keys" {
  for_each = toset(var.ssh_key_names)
  name     = each.value
}

resource "hcloud_firewall" "securewave" {
  name = var.firewall_name

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  dynamic "rule" {
    for_each = var.allow_http_https ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "80"
      source_ips = ["0.0.0.0/0", "::/0"]
    }
  }

  dynamic "rule" {
    for_each = var.allow_http_https ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "443"
      source_ips = ["0.0.0.0/0", "::/0"]
    }
  }

  labels = {
    "app" = "securewave"
  }
}

resource "hcloud_server" "securewave" {
  count       = var.node_count
  name        = format("%s-%02d", var.server_name_prefix, count.index + 1)
  server_type = var.server_type
  image       = var.image
  location    = var.location
  ssh_keys    = [for key in data.hcloud_ssh_key.keys : key.id]
  firewall_ids = [hcloud_firewall.securewave.id]

  backups = true

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = {
    "app" = "securewave"
  }
}
