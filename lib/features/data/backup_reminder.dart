import 'package:flutter/material.dart';

import '../../data/db/database.dart';

const String _kLastBackup = 'last_backup_at';
const String _kSnoozed = 'backup_snoozed_until';
const String _kFirstSeen = 'first_seen_at';

Future<void> markBackedUp(AppDatabase db, {DateTime? now}) =>
    db.writeSetting(_kLastBackup, (now ?? DateTime.now()).toIso8601String());

/// True when it's time to suggest a backup: at least 10 titles, the app
/// in use for a week, no backup for 30 days, and not put off.
Future<bool> backupDue(AppDatabase db, {DateTime? now}) async {
  final ts = now ?? DateTime.now();
  final values = await db.readSettings();
  final first = DateTime.tryParse(values[_kFirstSeen] ?? '');
  if (first == null) {
    await db.writeSetting(_kFirstSeen, ts.toIso8601String());
    return false;
  }
  if (ts.difference(first) < const Duration(days: 7)) return false;
  final snoozed = DateTime.tryParse(values[_kSnoozed] ?? '');
  if (snoozed != null && ts.isBefore(snoozed)) return false;
  final last = DateTime.tryParse(values[_kLastBackup] ?? '');
  if (last != null && ts.difference(last) < const Duration(days: 30)) {
    return false;
  }
  final count = (await db.select(db.items).get()).length;
  return count >= 10;
}

Future<void> snoozeBackup(AppDatabase db, {DateTime? now}) => db.writeSetting(
    _kSnoozed,
    (now ?? DateTime.now()).add(const Duration(days: 7)).toIso8601String());

/// Shows the reminder banner on the home screen when a backup is due.
Future<void> maybeShowBackupReminder(
    BuildContext context, AppDatabase db, VoidCallback openBackup) async {
  if (!await backupDue(db) || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showMaterialBanner(MaterialBanner(
    leading: const Icon(Icons.save_outlined),
    content: const Text("It's been a while since your last backup. Your "
        'lists only live on this phone.'),
    actions: [
      TextButton(
        onPressed: () async {
          messenger.hideCurrentMaterialBanner();
          await snoozeBackup(db);
        },
        child: const Text('Later'),
      ),
      FilledButton(
        onPressed: () {
          messenger.hideCurrentMaterialBanner();
          openBackup();
        },
        child: const Text('Back up now'),
      ),
    ],
  ));
}
