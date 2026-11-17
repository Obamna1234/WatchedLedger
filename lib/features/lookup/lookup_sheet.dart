import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/net/net_client.dart';
import '../../core/open_link.dart';
import '../../core/sanitise.dart';
import '../../data/lookup/candidate.dart';
import '../../data/lookup/lookup_service.dart';
import '../../data/models.dart';
import 'remote_thumb.dart';

/// What the user chose on the "Did you mean…?" sheet.
sealed class LookupChoice {
  const LookupChoice();
}

class PickedCandidate extends LookupChoice {
  const PickedCandidate(this.candidate);
  final LookupCandidate candidate;
}

/// Keep the title exactly as typed (free text, no lookup data).
class SaveAsTyped extends LookupChoice {
  const SaveAsTyped(this.text, {this.fillInDetails = false});
  final String text;

  /// Open the Edit screen straight away to fill in year, genre, where to
  /// watch, a link and so on by hand.
  final bool fillInDetails;
}

/// Shows matches for [query]. The user can pick one, keep typing and search
/// again, or save their text as it is. Returns null if dismissed.
Future<LookupChoice?> showLookupSheet(
  BuildContext context, {
  required MediaCategory category,
  required String query,
  LookupResult? initial,
}) {
  return showModalBottomSheet<LookupChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _LookupSheet(
      category: category,
      query: query,
      initial: initial,
    ),
  );
}

class _LookupSheet extends StatefulWidget {
  const _LookupSheet({
    required this.category,
    required this.query,
    required this.initial,
  });

  final MediaCategory category;
  final String query;
  final LookupResult? initial;

  @override
  State<_LookupSheet> createState() => _LookupSheetState();
}

class _LookupSheetState extends State<_LookupSheet> {
  late final TextEditingController _text =
      TextEditingController(text: widget.query);
  late LookupResult? _result = widget.initial;
  bool _loading = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = cleanTitle(_text.text);
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _problem = null;
    });
    final lookup = AppScope.of(context).lookup;
    try {
      final result = await lookup.search(query, widget.category);
      if (!mounted) return;
      setState(() {
        _result = result;
        if (result.couldNotReach) {
          _problem = "Couldn't reach ${result.sourcesTried.join(' or ')}. "
              'Check your connection, or save the title as typed.';
        }
      });
    } on NotOnWifiException {
      if (mounted) {
        setState(() => _problem = "You're on mobile data and lookups are set "
            'to Wi-Fi only (Settings > Use mobile data).');
      }
    } on OfflineException {
      if (mounted) {
        setState(() => _problem = 'Offline mode is on, so nothing was looked up.');
      }
    } catch (e) {
      if (mounted) setState(() => _problem = 'Lookup failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _saveAsTyped({bool fillIn = false}) {
    final text = cleanTitle(_text.text);
    if (text.isEmpty) return;
    Navigator.pop(context, SaveAsTyped(text, fillInDetails: fillIn));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final candidates = result?.candidates ?? const <LookupCandidate>[];
    final typed = _text.text.trim();

    String status;
    if (_loading) {
      status = 'Searching…';
    } else if (_problem != null) {
      status = _problem!;
    } else if (result == null) {
      status = '';
    } else if (candidates.isEmpty) {
      status = 'No matches in ${result.sourcesTried.join(' or ')}. '
          'Keep typing to search again, or save it as typed.';
    } else {
      status = 'From ${result.sourcesTried.last}. Tap the right one.';
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Did you mean…?', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _text,
                textInputAction: TextInputAction.search,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kMaxTitleLength),
                ],
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: 'Title',
                  suffixIcon: IconButton(
                    tooltip: 'Search again',
                    icon: const Icon(Icons.search),
                    onPressed: _loading ? null : _search,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(status, style: theme.textTheme.bodySmall),
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: candidates.length,
                itemBuilder: (context, i) {
                  final c = candidates[i];
                  final details = [
                    if (c.year != null) '${c.year}',
                    if (c.creator != null) c.creator!,
                    if (c.genre != kUncategorised) c.genre,
                  ].join('  ·  ');
                  return ListTile(
                    leading: RemoteThumb(
                      key: ValueKey(c.coverUrl),
                      url: c.coverUrl,
                      category: widget.category,
                    ),
                    title: Text(c.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: details.isEmpty
                        ? null
                        : Text(details,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, PickedCandidate(c)),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: FilledButton.tonalIcon(
                onPressed: typed.isEmpty ? null : _saveAsTyped,
                icon: const Icon(Icons.edit_note),
                label: Text(
                  typed.isEmpty ? 'Save as typed' : 'Save "$typed" as typed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (widget.category == MediaCategory.video)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: OutlinedButton.icon(
                  onPressed: typed.isEmpty
                      ? null
                      : () => searchYouTube(context, typed),
                  icon: const Icon(Icons.smart_display_outlined),
                  label:
                      const Text('Search YouTube, then share the video here'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: TextButton.icon(
                onPressed:
                    typed.isEmpty ? null : () => _saveAsTyped(fillIn: true),
                icon: const Icon(Icons.tune),
                label: const Text(
                    'Not listed? Save and fill in the details yourself'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
