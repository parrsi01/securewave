part of '../app.dart';

class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  int _index = 0;

  static const _tabs = [
    _ShellTab('Connect', Icons.power_settings_new_rounded),
    _ShellTab('Servers', Icons.public_rounded),
    _ShellTab('Account', Icons.person_rounded),
    _ShellTab('Settings', Icons.tune_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final bootMessage = ref.watch(bootControllerProvider).state.errorMessage;
    final wide = MediaQuery.sizeOf(context).width >= FreshTheme.mobileMax;
    final title = _tabs[_index].label;
    final child = switch (_index) {
      0 => const _ConnectScreen(),
      1 => const _ServersScreen(),
      2 => const _AccountScreen(),
      _ => const _SettingsScreen(),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: wide
            ? PreferredSize(
                preferredSize: const Size.fromHeight(50),
                child: _TopTabs(
                  tabs: _tabs,
                  index: _index,
                  onChanged: (next) => setState(() => _index = next),
                ),
              )
            : null,
      ),
      body: _PageFrame(
        child: Column(
          children: [
            if (bootMessage != null) ...[
              _InlineMessage(
                icon: Icons.warning_amber_rounded,
                message: 'Limited mode: some local startup checks failed.',
                tone: _Tone.warning,
                actionLabel: 'Open diagnostics',
                onAction: () => _showDiagnostics(context),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (next) => setState(() => _index = next),
              destinations: [
                for (final tab in _tabs)
                  NavigationDestination(icon: Icon(tab.icon), label: tab.label),
              ],
            ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<_ShellTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FreshTheme.line)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                _TopTabButton(
                  tab: tabs[i],
                  selected: index == i,
                  onTap: () => onChanged(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopTabButton extends StatelessWidget {
  const _TopTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _ShellTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 49),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? FreshTheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                tab.icon,
                size: 18,
                color: selected ? FreshTheme.primary : FreshTheme.graphiteMuted,
              ),
              const SizedBox(width: 8),
              Text(
                tab.label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected ? FreshTheme.graphite : FreshTheme.graphiteMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
