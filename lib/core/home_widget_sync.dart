import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/db/database.dart';
import '../data/models.dart';
import 'lock/app_lock.dart';

/// Keeps the Android home screen widget ("Up next") in step with the lists.
/// Titles are only handed to the widget while one is on the home screen,
/// and never while the app lock is on.
class HomeWidgetSync {
  HomeWidgetSync(this.db, this.lock);

  final AppDatabase db;
  final AppLock? lock;

  static const MethodChannel _channel = MethodChannel('watchedledger/widget');
  static const int rows = 5;

  StreamSubscription<List<MediaItem>>? _sub;
  List<MediaItem> _latest = const [];
  Timer? _debounce;
  bool _started = false;

  /// The widget's lines: newest additions across all To Watch / To Read /
  /// To Listen lists.
  static List<String> linesFor(List<MediaItem> items) {
    final todo = [
      for (final i in items)
        if (i.status == ListStatus.todo && !i.isPrivate) i,
    ]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return [
      for (final i in todo.take(rows))
        '${i.title}${i.year == null ? '' : ' (${i.year})'} · '
            '${i.category.singular}',
    ];
  }

  void start({required VoidCallback onQuickAdd}) {
    if (_started || defaultTargetPlatform != TargetPlatform.android) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'quickAdd') onQuickAdd();
    });
    unawaited(_takeQuickAdd(onQuickAdd));
    _sub = db.watchAll().listen((items) {
      _latest = items;
      _schedule();
    });
    lock?.addListener(_schedule);
  }

  Future<void> _takeQuickAdd(VoidCallback onQuickAdd) async {
    try {
      if (await _channel.invokeMethod<bool>('takeQuickAdd') ?? false) {
        onQuickAdd();
      }
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // Ignore.
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _push);
  }

  Future<void> _push() async {
    final locked = lock?.enabled ?? false;
    try {
      await _channel.invokeMethod<void>('update', {
        'lines': locked ? const <String>[] : linesFor(_latest),
        'locked': locked,
      });
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // Ignore: the widget just keeps its last state.
    }
  }

  void dispose() {
    _debounce?.cancel();
    unawaited(_sub?.cancel());
    lock?.removeListener(_schedule);
  }
}
