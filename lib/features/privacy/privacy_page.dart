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
              'Only these, and only when lookups are on and Offline mode '
              'is off:\n'
              '1. The title you type, sent when you add a title, import a '
              'list (one title at a time) or tap "Look up details".\n'
              '2. A request for a cover picture, the first time a cover is '
              'shown. After that it is kept on this device.\n'
              '3. A director, author or host name, only when you tap '
              '"More by…".\n'
              '4. A show\u2019s TVmaze number, when you open its episode '
              'list, and about once a day for shows you follow if "New '
              'episode reminders" is on. The phone then sets its own '
              'reminders; there is no push server or account.\n\n'
              'Nothing else is sent: no account, no device ID, no list '
              'contents, no cookies. Requests use HTTPS and a generic app '
              'name. Like any internet request, the service can see your IP '
              'address.',
            ),
            body(
              'Mobile data: by default nothing is fetched on mobile data '
              '(Settings > Use mobile data). Titles added then are saved as '
              'typed and looked up once you are back on Wi-Fi.',
            ),
            heading('Who receives it'),
            service('Movies', 'Wikipedia (Wikimedia Foundation), then iTunes'),
            service('Series', 'TVmaze, then iTunes Search if needed'),
            service('Books', 'Open Library (Internet Archive), then Google Books'),
            service('Audiobooks', 'iTunes Search, then Open Library'),
            service('Podcasts', 'iTunes Search; Wikipedia only to fix a '
                'misspelled show name'),
            service('Games', 'Wikipedia'),
            service('Niche titles', 'Wikidata, only if the services above '
                'find nothing'),
            service('Links', 'Only the link you paste, sent to the site it '
                'points to (YouTube, Vimeo, TikTok, Dailymotion, Spotify, '
                'SoundCloud, Reddit) to get the title and thumbnail. '
                'Facebook and Instagram are not contacted.'),
            service('Covers', 'The same services’ image servers '
                '(mzstatic.com, static.tvmaze.com, covers.openlibrary.org / '
                'archive.org, books.google.com, upload.wikimedia.org)'),
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
            const SizedBox(height: 8),
            body(
              'Phone-to-phone sync: only when you start it, and only on '
              'your home network (never the internet). Everything sent is '
              'encrypted with the one-time code shown on the other phone.',
            ),
            const SizedBox(height: 8),
            body(
              'Home screen widget (Android): if you add it, the few titles it '
              "shows are kept in the app's private storage so the widget can "
              'draw them. Remove the widget and they are deleted. While the '
              'app lock is on it only says "Locked".',
            ),
            const SizedBox(height: 8),
            body(
              'Shared folders: when you tap Share on a folder, your phone '
              'opens its normal share menu with a plain message (titles and '
              'links). Nothing is uploaded anywhere by WatchedLedger, and '
              'private items are never included.',
            ),
            const SizedBox(height: 8),
            body(
              'Recently deleted and private items stay in the encrypted '
              'database on this phone. Deleted items are erased for good '
              'after 30 days.',
            ),
          ],
        ),
      ),
    );
  }
}
