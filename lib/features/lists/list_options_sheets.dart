import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/genres.dart';
import '../../data/models.dart';
import 'list_layout.dart';

/// Bottom sheet for sorting and grouping. Changes apply immediately.
Future<void> showSortSheet(
  BuildContext context, {
  required ListOptions options,
  required ValueChanged<ListOptions> onChanged,
}) {
  var current = options;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        void apply(ListOptions next) {
          setSheet(() => current = next);
          onChanged(next);
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Group by genre'),
                  value: current.groupByGenre,
                  onChanged: (v) => apply(current.withSorting(groupByGenre: v)),
                ),
                const Divider(),
                for (final mode in SortMode.values)
                  ListTile(
                    title: Text(mode.label),
                    trailing: current.sort == mode
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () => apply(current.withSorting(sort: mode)),
                  ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Reverse order'),
                  value: current.reverse,
                  onChanged: (v) => apply(current.withSorting(reverse: v)),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Bottom sheet for filters. Returns the new options, or null if cancelled.
Future<ListOptions?> showFilterSheet(
  BuildContext context, {
  required ListOptions options,
  required MediaCategory category,
  required ListStatus status,
  required Set<String> genresInList,
  required Set<int> addedYears,
  required Set<int> completedYears,
}) {
  return showModalBottomSheet<ListOptions>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _FilterSheet(
      options: options,
      category: category,
      status: status,
      genresInList: genresInList,
      addedYears: addedYears,
      completedYears: completedYears,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.options,
    required this.category,
    required this.status,
    required this.genresInList,
    required this.addedYears,
    required this.completedYears,
  });

  final ListOptions options;
  final MediaCategory category;
  final ListStatus status;
  final Set<String> genresInList;
  final Set<int> addedYears;
  final Set<int> completedYears;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _genres = {...widget.options.genres};
  late int? _minRating = widget.options.minRating;
  late int? _addedYear = widget.options.addedYear;
  late int? _completedYear = widget.options.completedYear;
  late final TextEditingController _from =
      TextEditingController(text: widget.options.yearFrom?.toString() ?? '');
  late final TextEditingController _to =
      TextEditingController(text: widget.options.yearTo?.toString() ?? '');

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  ListOptions _result() => widget.options.withFilters(
        genres: _genres,
        minRating: _minRating,
        yearFrom: int.tryParse(_from.text),
        yearTo: int.tryParse(_to.text),
        addedYear: _addedYear,
        completedYear: _completedYear,
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _yearChips(Set<int> years, int? selected, ValueChanged<int?> onPick) {
    final sorted = years.toList()..sort((a, b) => b.compareTo(a));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            label: const Text('Any'),
            selected: selected == null,
            onSelected: (_) => onPick(null),
          ),
          for (final y in sorted)
            ChoiceChip(
              label: Text('$y'),
              selected: selected == y,
              onSelected: (_) => onPick(y),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final genres = widget.genresInList.toList()..sort(compareGenres);
    const yearField = InputDecoration(
      border: OutlineInputBorder(),
      isDense: true,
      counterText: '',
    );
    final yearFormatters = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(4),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (genres.isNotEmpty) ...[
                _heading('Genre'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final g in genres)
                        FilterChip(
                          label: Text(g),
                          selected: _genres.contains(g),
                          onSelected: (on) => setState(() {
                            _genres = {..._genres};
                            if (on) {
                              _genres.add(g);
                            } else {
                              _genres.remove(g);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
              _heading('Minimum rating'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Any'),
                      selected: _minRating == null,
                      onSelected: (_) => setState(() => _minRating = null),
                    ),
                    for (var r = 1; r <= 5; r++)
                      ChoiceChip(
                        label: Text('$r★'),
                        selected: _minRating == r,
                        onSelected: (_) => setState(() => _minRating = r),
                      ),
                  ],
                ),
              ),
              _heading('Release year'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _from,
                        keyboardType: TextInputType.number,
                        inputFormatters: yearFormatters,
                        decoration: yearField.copyWith(labelText: 'From'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _to,
                        keyboardType: TextInputType.number,
                        inputFormatters: yearFormatters,
                        decoration: yearField.copyWith(labelText: 'To'),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.addedYears.length > 1) ...[
                _heading('Added in'),
                _yearChips(widget.addedYears, _addedYear,
                    (y) => setState(() => _addedYear = y)),
              ],
              if (widget.status == ListStatus.done &&
                  widget.completedYears.isNotEmpty) ...[
                _heading('${widget.category.doneLabel} in'),
                _yearChips(widget.completedYears, _completedYear,
                    (y) => setState(() => _completedYear = y)),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(
                        context,
                        widget.options.withFilters(),
                      ),
                      child: const Text('Clear all'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _result()),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
