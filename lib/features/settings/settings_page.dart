import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/build_info.dart';
import '../../core/theme.dart';
import '../privacy/privacy_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final theme = Theme.of(context);

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          children: [
            section('Appearance'),
            for (final mode in AppThemeMode.values)
              ListTile(
                title: Text(mode.label),
                trailing: settings.themeMode == mode
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () => settings.setThemeMode(mode),
              ),
            section('Privacy'),
            SwitchListTile(
              title: const Text('Look up titles automatically'),
              subtitle: const Text(
                'Finds the proper name, year, genre and cover when you add '
                'something. Off: titles are saved exactly as typed.',
              ),
              value: settings.lookupsEnabled,
              onChanged: settings.setLookupsEnabled,
            ),
            SwitchListTile(
              title: const Text('Offline mode'),
              subtitle: const Text(
                'Blocks every network request, including title lookups and '
                'cover downloads.',
              ),
              value: settings.offlineMode,
              onChanged: settings.setOfflineMode,
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('What leaves this device'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PrivacyPage()),
              ),
            ),
            section('About'),
            const ListTile(
              title: Text('Version'),
              subtitle: Text('$kAppVersion ($kGitCommit)'),
            ),
          ],
        ),
      ),
    );
  }
}
