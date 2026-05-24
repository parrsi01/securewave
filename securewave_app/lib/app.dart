import 'package:flutter/material.dart';

class SecureWaveApp extends StatelessWidget {
  const SecureWaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureWave',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F6F5E),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F6F3),
        useMaterial3: true,
      ),
      home: const AppWorkspace(),
    );
  }
}

class AppWorkspace extends StatefulWidget {
  const AppWorkspace({super.key});

  @override
  State<AppWorkspace> createState() => _AppWorkspaceState();
}

class _AppWorkspaceState extends State<AppWorkspace> {
  int _index = 0;

  static const _items = <_NavItem>[
    _NavItem('Connection', Icons.power_settings_new),
    _NavItem('Servers', Icons.dns_outlined),
    _NavItem('Account', Icons.person_outline),
    _NavItem('Settings', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 780;
    final page = _WorkspacePage(item: _items[_index]);

    return Scaffold(
      body: SafeArea(
        child: compact
            ? page
            : Row(
                children: [
                  _SideNav(
                    selectedIndex: _index,
                    onSelected: (index) => setState(() => _index = index),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: page),
                ],
              ),
      ),
      bottomNavigationBar: compact
          ? NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              destinations: [
                for (final item in _items)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    label: item.label,
                  ),
              ],
            )
          : null,
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 232,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SecureWave',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < _AppWorkspaceState._items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _NavButton(
                  item: _AppWorkspaceState._items[i],
                  selected: selectedIndex == i,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(item.icon, size: 20),
            const SizedBox(width: 12),
            Text(item.label),
          ],
        ),
      ),
    );
  }
}

class _WorkspacePage extends StatelessWidget {
  const _WorkspacePage({required this.item});

  final _NavItem item;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          item.label,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(item.icon, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    '${item.label} workspace',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'This is a clean frontend placeholder for the next design pass.',
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {},
                child: const Text('Primary action'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: const Color(0xFFD8D8D2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon);

  final String label;
  final IconData icon;
}
