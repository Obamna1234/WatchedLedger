import 'dart:async';

import 'package:flutter/services.dart';

/// Text shared into the app from another app (Android "Share" menu).
class ShareReceiver {
  ShareReceiver._();

  static const MethodChannel _channel = MethodChannel('watchedledger/share');

  /// Calls [onText] with any text shared at launch and whenever more is
  /// shared while the app is open.
  static void listen(void Function(String text) onText) {
    Future<void> take() async {
      try {
        final text = await _channel.invokeMethod<String>('takeShared');
        if (text != null && text.trim().isNotEmpty) onText(text);
      } on MissingPluginException {
        // iOS and tests: no share channel.
      } on PlatformException {
        // Ignore.
      }
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') await take();
    });
    unawaited(take());
  }
}
