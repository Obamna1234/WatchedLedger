import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/net/net_client.dart';
import '../../data/covers/cover_cache.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';

/// Placeholder shown when there is no cover.
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    required this.category,
    this.width = 40,
    this.height = 56,
  });

  final MediaCategory category;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(category.icon, color: scheme.onSurfaceVariant),
    );
  }
}

/// A cover for a search result that isn't saved yet. Downloaded through
/// [NetClient] (never directly), kept in memory only.
class RemoteThumb extends StatefulWidget {
  const RemoteThumb({
    super.key,
    required this.url,
    required this.category,
    this.width = 40,
    this.height = 56,
  });

  final String? url;
  final MediaCategory category;
  final double width;
  final double height;

  @override
  State<RemoteThumb> createState() => _RemoteThumbState();
}

class _RemoteThumbState extends State<RemoteThumb> {
  static final Map<String, Uint8List> _memory = {};
  Uint8List? _bytes;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final url = widget.url;
    if (url == null) return;
    final cached = _memory[url];
    if (cached != null) {
      _bytes = cached;
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    AppScope.of(context)
        .net
        .getBytes(uri, maxBytes: NetClient.maxImageBytes, accept: 'image/*')
        .then((bytes) {
      if (!CoverCache.looksLikeImage(bytes)) return;
      if (_memory.length > 80) _memory.clear();
      _memory[url] = bytes;
      if (mounted) setState(() => _bytes = bytes);
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final placeholder = CoverPlaceholder(
      category: widget.category,
      width: widget.width,
      height: widget.height,
    );
    if (bytes == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        cacheWidth: (widget.width * 3).round(),
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

/// The cover for a saved item: shows the cached file, and fetches it once
/// if the item has a cover URL but no cached file yet.
class ItemCover extends StatefulWidget {
  const ItemCover({
    super.key,
    required this.item,
    this.width = 40,
    this.height = 56,
  });

  final MediaItem item;
  final double width;
  final double height;

  @override
  State<ItemCover> createState() => _ItemCoverState();
}

class _ItemCoverState extends State<ItemCover> {
  String? _requestedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeFetch();
  }

  @override
  void didUpdateWidget(ItemCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.coverUrl != widget.item.coverUrl) _maybeFetch();
  }

  void _maybeFetch() {
    final item = widget.item;
    final url = item.coverUrl;
    if (url == null || item.coverFile != null || _requestedFor == url) return;
    final scope = AppScope.of(context);
    if (scope.settings.offlineMode) return;
    _requestedFor = url;
    scope.covers.ensure(url).then((name) {
      if (name != null) scope.db.setCoverFile(item.id, name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final placeholder = CoverPlaceholder(
      category: item.category,
      width: widget.width,
      height: widget.height,
    );
    final name = item.coverFile;
    if (name == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        AppScope.of(context).covers.fileFor(name),
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        cacheWidth: (widget.width * 3).round(),
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}
