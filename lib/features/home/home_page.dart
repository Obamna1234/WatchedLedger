import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../add/quick_add_bar.dart';
import '../lists/category_page.dart';
import '../settings/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: MediaCategory.values.length, vsync: this)
        ..addListener(_onTabChanged);

  MediaCategory get _current => MediaCategory.values[_tabs.index];

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WatchedLedger'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final c in MediaCategory.values)
              Tab(icon: Icon(c.icon), text: c.tabLabel),
          ],
        ),
      ),
      body: Column(
        children: [
          QuickAddBar(category: _current),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final c in MediaCategory.values)
                  CategoryPage(key: PageStorageKey(c), category: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
