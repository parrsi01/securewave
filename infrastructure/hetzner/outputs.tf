output "server_id" {
  value = hcloud_server.securewave.id
}

output "server_name" {
  value = hcloud_server.securewave.name
}

output "server_ipv4" {
  value = hcloud_server.securewave.ipv4_address
}

output "server_ipv6" {
  value = hcloud_server.securewave.ipv6_address
}

output "firewall_id" {
  value = hcloud_firewall.securewave.id
}
