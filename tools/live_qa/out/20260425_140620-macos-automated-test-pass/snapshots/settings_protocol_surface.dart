                    ref
                        .read(clientSettingsProvider.notifier)
                        .setBestEffortKillSwitch(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Protocol', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: RadioGroup<VpnProtocol>(
              groupValue: protocol,
              onChanged: (value) {
                if (value == null) return;
                ref.read(vpnStateProvider.notifier).selectProtocol(value);
              },
              child: const Column(
                children: [
                  RadioListTile<VpnProtocol>(
                    title: Text('WireGuard'),
                    subtitle: Text('Balanced speed and privacy.'),
                    value: VpnProtocol.wireGuard,
                  ),
                  Divider(height: 1),
                  RadioListTile<VpnProtocol>(
                    title: Text('IKEv2'),
                    subtitle: Text('Reliable on mobile networks.'),
                    value: VpnProtocol.ikev2,
                  ),
                  Divider(height: 1),
                  RadioListTile<VpnProtocol>(
                    title: Text('OpenVPN'),
                    subtitle: Text('Compatibility mode.'),
                    value: VpnProtocol.openVpn,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Ad blocking', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space2),
          Text(
            'Ad blocking works at the DNS level inside the VPN tunnel. '
            'When enabled, known ad and tracker domains are resolved to '
            'a sinkhole address, preventing connections before they start. '
            'No content inspection is performed on your traffic.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
