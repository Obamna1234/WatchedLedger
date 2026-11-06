import 'package:flutter/material.dart';

import 'app.dart';
import 'core/net/net_client.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'data/covers/cover_cache.dart';
import 'data/db/open.dart';
import 'data/lookup/lookup_service.dart';
import 'features/recovery/recovery_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootApp());
}

/// Opens the encrypted database, then shows either the app or a recovery
/// screen if the database can't be unlocked.
class BootApp extends StatefulWidget {
  const BootApp({super.key});

  @override
  State<BootApp> createState() => _BootAppState();
}

class _BootAppState extends State<BootApp> {
  OpenResult? _result;
  AppServices? _services;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    if (_result != null) setState(() => _result = null);
    final result = await openAppDatabase();
    AppServices? services;
    if (result is DbOpened) {
      final settings = SettingsController(result.db);
      await settings.load();
      final net = NetClient(isOffline: () => settings.offlineMode);
      services = AppServices(
        db: result.db,
        settings: settings,
        net: net,
        lookup: LookupService(net),
        covers: await CoverCache.open(net),
      );
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _services = services;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final services = _services;
    if (result is DbOpened && services != null) {
      return WatchedLedgerApp(services: services);
    }
    return MaterialApp(
      title: 'WatchedLedger',
      debugShowCheckedModeBanner: false,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      home: switch (result) {
        null => const Scaffold(body: Center(child: CircularProgressIndicator())),
        final DbKeyProblem problem => RecoveryPage(
            problem: problem,
            onStartFresh: () async {
              await moveUnreadableDatabaseAside(problem.file);
              await _open();
            },
            onRetry: _open,
          ),
        final DbFailed failure => RecoveryPage(failure: failure, onRetry: _open),
        DbOpened() => const SizedBox.shrink(),
      },
    );
  }
}
