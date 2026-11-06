import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'list_layout.dart';

/// A thin index strip on the right edge. Tap or drag along it to jump
/// between sections (genres, letters, years...). While touching, a bubble
/// shows the full section name.
class FastScrollBar extends StatefulWidget {
  const FastScrollBar({
    super.key,
    required this.sections,
    required this.onJump,
    required this.onActiveLabel,
  });

  final List<ListSection> sections;
  final ValueChanged<ListSection> onJump;

  /// Called with the section label while dragging, and null on release.
  final ValueChanged<String?> onActiveLabel;

  @override
  State<FastScrollBar> createState() => _FastScrollBarState();
}

class _FastScrollBarState extends State<FastScrollBar> {
  int? _active;

  void _handle(double dy, double height) {
    final n = widget.sections.length;
    if (n == 0 || height <= 0) return;
    final index = (dy / height * n).floor().clamp(0, n - 1);
    if (index == _active) return;
    setState(() => _active = index);
    HapticFeedback.selectionClick();
    final section = widget.sections[index];
    widget.onActiveLabel(section.label);
    widget.onJump(section);
  }

  void _end() {
    setState(() => _active = null);
    widget.onActiveLabel(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = widget.sections;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        const slot = 18.0;
        // Show every label if they fit, otherwise every k-th one.
        final step = height.isFinite && height > slot
            ? (sections.length * slot / height).ceil().clamp(1, 1000)
            : 1000;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) => _handle(d.localPosition.dy, height),
          onVerticalDragUpdate: (d) => _handle(d.localPosition.dy, height),
          onVerticalDragEnd: (_) => _end(),
          onVerticalDragCancel: _end,
          onTapDown: (d) => _handle(d.localPosition.dy, height),
          onTapUp: (_) => _end(),
          onTapCancel: _end,
          child: Semantics(
            label: 'Section index',
            child: Container(
              width: 30,
              decoration: BoxDecoration(
                color: _active == null
                    ? Colors.transparent
                    : theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < sections.length; i += step)
                    Text(
                      sections[i].shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight:
                            i == _active ? FontWeight.bold : FontWeight.w500,
                        color: i == _active
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The large label shown in the middle of the list while fast-scrolling.
class FastScrollBubble extends StatelessWidget {
  const FastScrollBubble({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Text(
            label,
            style: theme.textTheme.headlineSmall
                ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
      ),
    );
  }
}
