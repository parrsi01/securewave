# Rollback Notes

- Server config backups were created during this run:
  - /etc/openvpn/server/server.conf.bak.20260227_202241
  - /etc/openvpn/server/server.conf.bak.20260227_202256
- Direct OpenVPN client config backup was created:
  - /root/securewave_runtime_validation_20260227_142705/ovpn_client.ovpn.bak.<timestamp>

Current blocker:
- VPS host `138.199.204.139` became unreachable (persistent packet loss, SSH timeout).
- Automatic rollback execution could not be completed while host is offline.

Rollback command set to run once host is reachable:
1) Restore server config from latest backup and restart:
   cp -a /etc/openvpn/server/server.conf.bak.<ts> /etc/openvpn/server/server.conf
   systemctl restart openvpn-server@server
2) Restore direct client config from backup and restart client process.
