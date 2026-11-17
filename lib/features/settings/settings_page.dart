import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/build_info.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../data/data_page.dart';
import '../lock/lock_settings_page.dart';
import '../privacy/privacy_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
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
        listenable: Listenable.merge([settings, scope.network, scope.lock]),
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
            section('Use mobile data'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Right now: ${scope.network.label}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final option in MobileDataUse.values)
              ListTile(
                title: Text(option.label),
                subtitle: Text(option.description),
                trailing: settings.mobileData == option
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () => settings.setMobileData(option),
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
            if (scope.lock case final lock?)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('App lock'),
                subtitle: Text(lock.enabled ? 'On' : 'Off'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => LockSettingsPage(lock: lock)),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('What leaves this device'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PrivacyPage()),
              ),
            ),
            if (scope.reminders case final reminders?) ...[
              section('Notifications'),
              SwitchListTile(
                title: const Text('New episode reminders'),
                subtitle: const Text(
                  'For shows you follow (Series → Edit → Episodes). About '
                  'once a day the app asks TVmaze for their episode lists; '
                  'the phone then reminds you on the air date.',
                ),
                value: settings.episodeReminders,
                onChanged: (on) async {
                  if (!on) {
                    await settings.setEpisodeReminders(false);
                    await reminders.cancelAll();
                    return;
                  }
                  final allowed = await reminders.requestPermission();
                  if (!allowed) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Notifications are blocked for this '
                              'app in your phone settings.')));
                    }
                    return;
                  }
                  await settings.setEpisodeReminders(true);
                  await reminders.run(force: true);
                },
              ),
            ],
            section('Your data'),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Import, export and backup'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DataPage()),
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
