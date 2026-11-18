import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/net/net_client.dart';
import '../../core/sanitise.dart';
import '../../data/lookup/candidate.dart';
import '../../data/lookup/more_by.dart';
import '../../data/models.dart';
import '../lookup/remote_thumb.dart';

/// Other works by the same director / author / host, with one-tap add.
class MoreByPage extends StatefulWidget {
  const MoreByPage({super.key, required this.creator, required this.category});
  final String creator;
  final MediaCategory category;

  @override
  State<MoreByPage> createState() => _MoreByPageState();
}

class _MoreByPageState extends State<MoreByPage> {
  Future<List<LookupCandidate>>? _results;
  Set<String> _inLibrary = {};
  final Set<String> _added = {};

  String get _name => MoreByService.primaryName(widget.creator);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _results ??= _load();
  }

  Future<List<LookupCandidate>> _load() async {
    final scope = AppScope.of(context);
    final db = scope.db;
    final service = MoreByService(scope.net);
    if (!scope.settings.lookupsEnabled) {
      throw const _LookupsOff();
    }
    final items = await db.select(db.items).get();
    _inLibrary = {
      for (final i in items)
        if (i.category == widget.category) i.matchKey,
    };
    return service.worksBy(widget.creator, widget.category);
  }

  Future<void> _add(LookupCandidate c) async {
    final scope = AppScope.of(context);
    final candidate = await scope.lookup.details(c);
    await scope.db.addItem(
      category: widget.category,
      status: ListStatus.todo,
      title: candidate.title,
      year: candidate.year,
      genre: candidate.genre,
      creator: candidate.creator,
      coverUrl: candidate.coverUrl,
      pages: candidate.pages,
      source: candidate.source,
      sourceId: candidate.sourceId,
      matchState: MatchState.matched,
    );
    if (!mounted) return;
    setState(() => _added.add(matchKey(c.title)));
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(
              'Added "${candidate.title}" to ${widget.category.todoLabel}')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('More by $_name')),
      body: FutureBuilder<List<LookupCandidate>>(
        future: _results,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final e = snap.error;
            final message = e is NotOnWifiException
                ? "You're on mobile data. This works on Wi-Fi, or allow "
                    'lookups on mobile data in More.'
                : e is OfflineException
                    ? 'Offline mode is on, so nothing can be looked up.'
                    : e is _LookupsOff
                        ? 'Lookups are switched off in More.'
                        : "Couldn't reach the service. Try again later.";
            return _Message(text: message);
          }
          final list = snap.data ?? const [];
          if (list.isEmpty) {
            return _Message(text: 'Nothing else found for $_name.');
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Only the name "$_name" was sent to look this up.',
                    style: theme.textTheme.bodySmall,
                  ),
                );
              }
              final c = list[i - 1];
              final key = matchKey(c.title);
              final have = _inLibrary.contains(key) || _added.contains(key);
              return ListTile(
                leading:
                    RemoteThumb(url: c.coverUrl, category: widget.category),
                title: Text(c.title),
                subtitle: Text([
                  if (c.year != null) '${c.year}',
                  if (c.genre != kUncategorised) c.genre,
                ].join(' · ')),
                trailing: have
                    ? const Tooltip(
                        message: 'Already in your lists',
                        child: Icon(Icons.check_circle_outline),
                      )
                    : IconButton(
                        tooltip: 'Add to ${widget.category.todoLabel}',
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () => _add(c),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LookupsOff implements Exception {
  const _LookupsOff();
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}
