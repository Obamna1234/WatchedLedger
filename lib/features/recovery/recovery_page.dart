import 'package:flutter/material.dart';

import '../../data/db/open.dart';

/// Shown when the encrypted database can't be opened. Nothing here deletes
/// data: "Start fresh" moves the unreadable file aside and keeps it.
class RecoveryPage extends StatelessWidget {
  const RecoveryPage({
    super.key,
    this.problem,
    this.failure,
    this.onStartFresh,
    required this.onRetry,
  });

  final DbKeyProblem? problem;
  final DbFailed? failure;
  final Future<void> Function()? onStartFresh;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isKeyProblem = problem != null;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              isKeyProblem
                  ? "Your library can't be unlocked"
                  : "WatchedLedger couldn't start",
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              isKeyProblem
                  ? 'Your library is encrypted with a key kept in this '
                      "phone's secure storage, and that key is "
                      '${problem!.keyMissing ? 'missing' : 'not the right one'}.\n\n'
                      'On iPhone this usually means the app was re-signed with '
                      'a different Apple ID. Re-installing with the original '
                      'Apple ID should bring it back.\n\n'
                      'If that is not possible, you can start fresh and then '
                      'restore one of your backup files. The unreadable library '
                      'is kept, not deleted.'
                  : 'Something went wrong while opening your library. '
                      'Your data has not been changed.',
              style: theme.textTheme.bodyLarge,
            ),
            if (failure != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                failure!.error.toString(),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
            if (onStartFresh != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _confirmStartFresh(context),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Start fresh (keep old file)'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmStartFresh(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start with an empty library?'),
        content: const Text(
          'The unreadable library file will be renamed and kept on this '
          'device. You can restore a backup file afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start fresh'),
          ),
        ],
      ),
    );
    if (ok == true) await onStartFresh?.call();
  }
}
