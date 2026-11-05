import 'package:flutter/material.dart';

/// Plain statement of what leaves the device. Keep in sync with PRIVACY.md.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(text, style: theme.textTheme.titleMedium),
        );
    Widget body(String text) =>
        Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4));

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          heading('In this version: nothing'),
          body(
            'This version of WatchedLedger makes no network requests at all. '
            'Everything you add stays in an encrypted database on this '
            'device.',
          ),
          heading('Never collected'),
          body(
            'No account. No analytics. No ads. No crash reporting. '
            'No tracking or advertising identifiers. The app contains no '
            'third-party SDKs that phone home.',
          ),
          heading('Coming with title lookup'),
          body(
            'When title lookup is added, the only things that will leave '
            'the device are:\n'
            '• the title text you type, sent to the lookup service for that '
            'category (TMDB, Open Library, Google Books, iTunes Search or '
            'TVmaze), and\n'
            '• requests to download cover images from those services.\n\n'
            'All requests use HTTPS. Offline mode blocks every one of them. '
            'This page will list each service and exactly when it is '
            'contacted.',
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
    );
  }
}
