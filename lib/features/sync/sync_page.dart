import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/net/net_client.dart';
import '../../data/sync/sync_merge.dart';
import '../../data/sync/sync_service.dart';

/// Phone-to-phone sync over home Wi-Fi. One phone shows an address and a
/// one-time code; the other types them in. Everything sent is encrypted with
/// that code. No server, no account, nothing leaves your home network.
class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

enum _Mode { choose, hosting, joining }

class _SyncPageState extends State<SyncPage> {
  _Mode _mode = _Mode.choose;
  SyncHost? _host;
  bool _working = false;
  String? _error;
  SyncResult? _result;
  final _address = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    final host = _host;
    if (host != null) unawaited(host.stop());
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _startHost() async {
    final scope = AppScope.of(context);
    setState(() {
      _mode = _Mode.hosting;
      _error = null;
      _result = null;
    });
    try {
      final host =
          await SyncHost.start(scope.db, offline: scope.settings.offlineMode);
      if (!mounted) {
        await host.stop();
        return;
      }
      setState(() => _host = host);
      final result = await host.done;
      if (mounted) setState(() => _result = result);
    } on SyncException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(() => _error = "Couldn't start. Check this phone is on Wi-Fi.");
      }
    } finally {
      _host = null;
    }
  }

  Future<void> _join() async {
    final scope = AppScope.of(context);
    final address = parseSyncAddress(_address.text);
    final code = SyncCode.normalise(_code.text);
    if (address == null) {
      setState(() => _error = 'Type the address exactly as the other phone '
          'shows it, e.g. 192.168.1.23:41234');
      return;
    }
    if (code == null) {
      setState(() => _error = 'The code is 8 letters and numbers, e.g. '
          'K7Q2-9XMF');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final result = await syncWith(
          db: scope.db, net: scope.net, address: address, code: code);
      if (mounted) setState(() => _result = result);
    } on SyncException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on OfflineException {
      if (mounted) setState(() => _error = 'Offline mode is on.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    if (_result case final r?) {
      children.addAll([
        Icon(Icons.check_circle_outline,
            size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text('Synced', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          r.nothingChanged
              ? 'Both phones were already the same.'
              : [
                  if (r.added > 0) '${r.added} added',
                  if (r.updated > 0) '${r.updated} updated',
                  if (r.deleted > 0) '${r.deleted} deleted',
                  if (r.diaryEntries > 0) '${r.diaryEntries} diary entries',
                ].join(' · '),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ]);
    } else if (_mode == _Mode.choose) {
      children.addAll([
        Text(
          'Sync two phones on the same Wi-Fi. Open this screen on both, '
          'then:',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Show a code on this phone'),
          onPressed: _startHost,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.keyboard_outlined),
          label: const Text('Enter the code from the other phone'),
          onPressed: () => setState(() {
            _mode = _Mode.joining;
            _error = null;
          }),
        ),
        const SizedBox(height: 24),
        Text(
          'Everything sent is encrypted with the one-time code and stays '
          'on your home network. The newest edit of each title wins; '
          'deletions sync too. Settings and the app lock are not synced.',
          style: theme.textTheme.bodySmall,
        ),
      ]);
    } else if (_mode == _Mode.hosting) {
      final host = _host;
      children.addAll([
        if (host == null && _error == null) const CircularProgressIndicator(),
        if (host != null) ...[
          Text('On the other phone, choose "Enter the code" and type:',
              textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          _BigValue(label: 'Address', value: host.address),
          const SizedBox(height: 12),
          _BigValue(label: 'Code', value: host.code),
          const SizedBox(height: 24),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text('Waiting for the other phone (up to 5 minutes)…',
              style: theme.textTheme.bodySmall),
        ],
      ]);
    } else {
      children.addAll([
        TextField(
          controller: _address,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.:]')),
            LengthLimitingTextInputFormatter(21),
          ],
          decoration: const InputDecoration(
            labelText: 'Address',
            hintText: '192.168.1.23:41234',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [LengthLimitingTextInputFormatter(9)],
          decoration: const InputDecoration(
            labelText: 'Code',
            hintText: 'K7Q2-9XMF',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _join(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _working ? null : _join,
          child: Text(_working ? 'Syncing…' : 'Sync'),
        ),
      ]);
    }

    if (_error != null) {
      children.addAll([
        const SizedBox(height: 16),
        Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error)),
        if (_mode == _Mode.hosting) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: _startHost, child: const Text('Try again')),
        ],
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sync with another phone')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _BigValue extends StatelessWidget {
  const _BigValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        SelectableText(
          value,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
