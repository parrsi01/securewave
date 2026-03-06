| Protocol | Provisioning Path | Negotiation | Egress Proof | PASS/FAIL | Reason |
|---|---|---|---|---|---|
| OpenVPN | Manual client cert/profile (API returned 409 `openvpn_server_misconfigured`) | PASS | PASS | PASS | `tun0` full tunnel, public IP changed to `138.199.204.139`, server `tun0` counters increased |
| IKEv2 | Manual EAP user/config (API returned 409 `ikev2_server_misconfigured`) | PASS | PASS | PASS | CHILD_SA `10.10.0.11/32 === 0.0.0.0/0`, route via table `220`, public IP changed to `138.199.204.139`, ESP-in-UDP observed |
