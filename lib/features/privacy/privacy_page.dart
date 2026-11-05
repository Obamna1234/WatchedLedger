import 'package:flutter/material.dart';

import '../../core/app_scope.dart';

/// Plain statement of what leaves the device. Keep in sync with PRIVACY.md
/// and NetClient.allowedHosts.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = AppScope.of(context).settings;

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(text, style: theme.textTheme.titleMedium),
        );
    Widget body(String text) =>
        Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4));

    Widget service(String name, String what) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(name, style: theme.textTheme.titleSmall),
              ),
              Expanded(child: body(what)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  settings.offlineMode
                      ? 'Offline mode is ON. Nothing is leaving this device.'
                      : settings.lookupsEnabled
                          ? 'Lookups are ON. Only the items below are ever sent.'
                          : 'Lookups are OFF. Only cover images for titles you '
                              'matched earlier may still be downloaded.',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
            heading('What leaves this device'),
            body(
              'Only two things, and only when lookups are on and Offline mode '
              'is off:\n'
              '1. The title you type, sent when you add a title or tap '
              '"Look up details".\n'
              '2. A request for a cover picture, the first time a cover is '
              'shown. After that it is kept on this device.\n\n'
              'Nothing else is sent: no account, no device ID, no list '
              'contents, no cookies. Requests use HTTPS and a generic app '
              'name. Like any internet request, the service can see your IP '
              'address.',
            ),
            heading('Who receives it'),
            service('Movies', 'iTunes Search (Apple)'),
            service('Series', 'TVmaze, then iTunes Search if needed'),
            service('Books', 'Open Library (Internet Archive), then Google Books'),
            service('Audiobooks', 'iTunes Search, then Open Library'),
            service('Podcasts', 'iTunes Search'),
            service('Covers', 'The same services’ image servers '
                '(mzstatic.com, static.tvmaze.com, covers.openlibrary.org / '
                'archive.org, books.google.com)'),
            body('The app refuses to contact any other address.'),
            heading('Never collected'),
            body(
              'No account. No analytics. No ads. No crash reporting. '
              'No tracking or advertising identifiers. No third-party SDKs.',
            ),
            heading('Your data on this device'),
            body(
              'Your library is encrypted with a random key kept in the '
              "phone's secure storage (Android Keystore / iOS Keychain), and "
              'that key never leaves this phone. Android device backups are '
              'switched off for this app; an iCloud device backup would only '
              'ever hold the encrypted file, which cannot be opened without '
              'the key. Your real backups are files you create yourself and '
              'save wherever you choose.',
            ),
          ],
        ),
      ),
    );
  }
}
