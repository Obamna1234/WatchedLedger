import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'sanitise.dart';

/// Opens a saved link in another app (YouTube, NewPipe, the browser...).
/// The phone decides which app, or asks. Nothing is fetched by WatchedLedger.
Future<void> openLink(BuildContext context, String raw) async {
  final link = cleanLink(raw);
  final messenger = ScaffoldMessenger.of(context);
  if (link == null) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Add a web link first.')));
    return;
  }
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(link),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    messenger.showSnackBar(
        const SnackBar(content: Text('No app on this phone can open it.')));
  }
}

/// Opens a YouTube search for [query] in YouTube, NewPipe or the browser.
/// Nothing is searched by WatchedLedger itself.
Future<void> searchYouTube(BuildContext context, String query) =>
    openLink(context,
        Uri.https('www.youtube.com', '/results', {'search_query': query.trim()})
            .toString());
