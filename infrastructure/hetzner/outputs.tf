output "server_ids" {
  value = [for s in hcloud_server.securewave : s.id]
}

output "server_names" {
  value = [for s in hcloud_server.securewave : s.name]
}

output "server_ipv4" {
  value = [for s in hcloud_server.securewave : s.ipv4_address]
}

output "server_ipv6" {
  value = [for s in hcloud_server.securewave : s.ipv6_address]
}

output "firewall_id" {
  value = hcloud_firewall.securewave.id
}
