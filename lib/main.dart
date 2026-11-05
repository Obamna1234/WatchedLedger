import 'package:flutter/material.dart';

import 'app.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'data/db/open.dart';
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
  SettingsController? _settings;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    if (_result != null) setState(() => _result = null);
    final result = await openAppDatabase();
    SettingsController? settings;
    if (result is DbOpened) {
      settings = SettingsController(result.db);
      await settings.load();
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _settings = settings;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final settings = _settings;
    if (result is DbOpened && settings != null) {
      return WatchedLedgerApp(db: result.db, settings: settings);
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
