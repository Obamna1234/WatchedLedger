import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/net/net_client.dart';
import '../../data/db/database.dart';
import '../../data/lookup/candidate.dart';
import '../../data/lookup/link_lookup.dart';
import '../../data/models.dart';
import '../edit/edit_item_page.dart';

/// Opens the Edit screen for a just-added item.
Future<void> openNewItemEditor(
    BuildContext context, AppDatabase db, int id) async {
  final item = await db.itemById(id);
  if (item == null || !context.mounted) return;
  await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EditItemPage(item: item)));
}

/// Adds a pasted or shared link: title, channel and thumbnail from the
/// site when it offers them (YouTube, Vimeo, TikTok, Dailymotion, Spotify,
/// SoundCloud). Otherwise (Facebook, Instagram, other sites, offline) it is
/// saved with the link and the Edit screen opens to type the title.
/// Returns true if something was added.
Future<bool> addLinkItem(
  BuildContext context,
  Uri link, {
  required MediaCategory fallback,
  required ListStatus status,
}) async {
  final scope = AppScope.of(context);
  final category = LinkLookup.categoryFor(link) ?? fallback;
  LookupCandidate? found;
  if (!scope.settings.offlineMode &&
      scope.settings.lookupsEnabled &&
      scope.net.mayUse(NetPurpose.lookup)) {
    try {
      found = await LinkLookup(scope.net).lookup(link);
    } on OfflineException {
      found = null;
    }
  }
  if (!context.mounted) return false;
  final linkText = link.toString();
  final existing = (await scope.db.select(scope.db.items).get())
      .where((i) => i.link == linkText)
      .firstOrNull;
  if (!context.mounted) return false;
  if (existing != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${existing.title}" is already in your lists.')));
    return false;
  }
  final title =
      found?.title ?? 'Link from ${link.host.replaceFirst('www.', '')}';
  final id = await scope.db.addItem(
    category: category,
    status: status,
    title: title,
    creator: found?.creator,
    coverUrl: found?.coverUrl,
    link: linkText,
    source: found?.source,
    sourceId: found?.sourceId,
    matchState: found != null ? MatchState.matched : MatchState.manual,
  );
  final cover = found?.coverUrl;
  if (cover != null) {
    unawaited(scope.covers.ensure(cover).then((name) async {
      if (name != null) await scope.db.setCoverFile(id, name);
    }));
  }
  if (!context.mounted) return true;
  if (found == null) {
    await openNewItemEditor(context, scope.db, id);
    return true;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Added "$title" to ${category.tabLabel} › '
          '${category.labelFor(status)}'),
      persist: false,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => scope.db.deleteItem(id),
      ),
    ));
  return true;
}
