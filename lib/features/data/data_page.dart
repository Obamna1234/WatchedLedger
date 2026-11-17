import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/transfer/backup.dart';
import '../../data/transfer/export.dart';

/// Settings > Your data: export, encrypted backup and restore.
class DataPage extends StatefulWidget {
  const DataPage({super.key});

  @override
  State<DataPage> createState() => _DataPageState();
}

const int _maxBackupBytes = 100 * 1024 * 1024;

String _today() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _DataPageState extends State<DataPage> {
  bool _busy = false;
  String? _busyText;

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<T?> _working<T>(String text, Future<T> Function() task) async {
    setState(() {
      _busy = true;
      _busyText = text;
    });
    try {
      return await task();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyText = null;
        });
      }
    }
  }

  Future<void> _save(String fileName, Uint8List bytes, String mime) async {
    final where = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mime,
      dialogTitle: 'Save $fileName',
    );
    if (!mounted) return;
    _toast(where == null ? 'Not saved' : 'Saved $fileName');
  }

  Future<void> _export() async {
    final format = await showModalBottomSheet<ExportFormat>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in ExportFormat.values)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(f.label),
                onTap: () => Navigator.pop(context, f),
              ),
          ],
        ),
      ),
    );
    if (format == null || !mounted) return;
    final db = AppScope.of(context).db;
    final items = await db.select(db.items).get();
    final text = exportAs(format, items);
    await _save('WatchedLedger-${_today()}.${format.extension}',
        Uint8List.fromList(utf8.encode(text)), format.mimeType);
  }

  Future<void> _backup() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(confirm: true),
    );
    if (password == null || !mounted) return;
    final db = AppScope.of(context).db;
    final bytes = await _working('Encrypting backup…', () async {
      return encryptBackup(await buildSnapshot(db), password);
    });
    if (bytes == null || !mounted) return;
    await _save('WatchedLedger-${_today()}.wlbackup', bytes,
        'application/octet-stream');
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Choose a backup');
    if (picked == null || !mounted) return;
    final bytes = await picked.xFile.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxBackupBytes) {
      _toast('That file is too large to be a backup.');
      return;
    }
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(confirm: false),
    );
    if (password == null || !mounted) return;

    Map<String, Object?>? snapshot;
    try {
      snapshot = await _working(
          'Unlocking backup…', () => decryptBackup(bytes, password));
    } on BackupPasswordException catch (e) {
      if (mounted) _toast(e.toString());
      return;
    } on BackupFormatException catch (e) {
      if (mounted) _toast(e.toString());
      return;
    }
    if (snapshot == null || !mounted) return;

    final summary = summarise(snapshot);
    final created = summary.created;
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup'),
        content: Text(
          'This backup has ${summary.items} titles'
          '${created == null ? '' : ' and was made on ${created.day}/${created.month}/${created.year}'}.\n\n'
          "Merge: adds titles you don't have and keeps the newest edits.\n"
          'Replace: your library becomes exactly this backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (replace == null || !mounted) return;
    if (replace) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace your library?'),
          content: const Text(
              'Everything currently in WatchedLedger will be replaced by the '
              'backup. Consider making a backup of it first.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }
    final db = AppScope.of(context).db;
    final settings = AppScope.of(context).settings;
    final data = snapshot;
    final result = await _working(
        'Restoring…', () => restoreSnapshot(db, data, replace: replace));
    if (result == null || !mounted) return;
    if (replace) await settings.load();
    if (!mounted) return;
    _toast('Restored: ${result.added} added, ${result.updated} updated'
        '${result.skipped == 0 ? '' : ', ${result.skipped} skipped'}.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Your data')),
      body: Stack(
        children: [
          ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Export list'),
                subtitle: const Text('Text, spreadsheet (CSV) or JSON. '
                    'Not encrypted: anyone with the file can read it.'),
                onTap: _busy ? null : _export,
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Create encrypted backup'),
                subtitle: const Text('A password-protected file you save '
                    'wherever you like (Drive, USB, another phone).'),
                onTap: _busy ? null : _backup,
              ),
              ListTile(
                leading: const Icon(Icons.settings_backup_restore),
                title: const Text('Restore from backup'),
                subtitle: const Text('Merge with or replace your library.'),
                onTap: _busy ? null : _restore,
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Backups are encrypted with AES-256 using a key made from '
                  'your password (Argon2id). Without the password nobody, '
                  'including the app, can open them. Cover pictures are not '
                  'included; they download again after a restore.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (_busy)
            ColoredBox(
              color: theme.colorScheme.surface.withValues(alpha: 0.85),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_busyText ?? ''),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.confirm});

  /// Ask twice (new backups) or once (restores).
  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _first.text;
    if (widget.confirm) {
      if (p.length < 8) {
        setState(() => _error = 'Use at least 8 characters.');
        return;
      }
      if (p != _second.text) {
        setState(() => _error = "The passwords don't match.");
        return;
      }
    } else if (p.isEmpty) {
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.confirm ? 'Backup password' : 'Enter backup password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _first,
            obscureText: !_show,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide' : 'Show',
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
            onSubmitted: widget.confirm ? null : (_) => _submit(),
          ),
          if (widget.confirm)
            TextField(
              controller: _second,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Repeat password'),
              onSubmitted: (_) => _submit(),
            ),
          if (widget.confirm)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text("If you forget this password the backup can't be "
                  'opened. Store it in your password manager.'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
