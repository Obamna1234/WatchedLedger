import 'package:flutter/services.dart';

/// Opens the phone's own share menu with [text] (Messages, WhatsApp,
/// email...). Nothing passes through WatchedLedger or any server.
/// Returns false if sharing isn't available; the text is then copied.
Future<bool> shareText(String text) async {
  try {
    await const MethodChannel('watchedledger/share')
        .invokeMethod<void>('shareText', text);
    return true;
  } on MissingPluginException {
    await Clipboard.setData(ClipboardData(text: text));
    return false;
  } on PlatformException {
    await Clipboard.setData(ClipboardData(text: text));
    return false;
  }
}
