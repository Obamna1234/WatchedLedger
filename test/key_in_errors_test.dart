// Regression (v1.3.0 security review, L2): an error from opening the library
// is logged and shown on the recovery screen, so it must never contain the
// database key.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/data/db/open.dart';
import 'package:watchedledger/features/recovery/recovery_page.dart';

const _key =
    '0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0';

void main() {
  test('hideKeys removes anything that looks like a key', () {
    final text = "SqliteException(1): near \"x\": syntax error\n"
        "  Causing statement: PRAGMA key = '$_key';";
    final shown = hideKeys(text);
    expect(shown, isNot(contains(_key)));
    expect(shown, contains('<hidden>'));
    expect(shown, contains('syntax error'), reason: 'the rest is kept');
    expect(hideKeys('no key here, error 1234'), 'no key here, error 1234');
  });

  test('DbFailed.message never contains the key', () {
    final failed = DbFailed(StateError("PRAGMA key = '$_key' failed"));
    expect(failed.message, isNot(contains(_key)));
  });

  testWidgets('the recovery screen does not show the key', (t) async {
    final failed = DbFailed(StateError("PRAGMA key = '$_key' failed"));
    await t.pumpWidget(MaterialApp(
        home: RecoveryPage(failure: failed, onRetry: () async {})));
    await t.pump();
    expect(find.textContaining(_key), findsNothing);
    expect(find.textContaining('<hidden>'), findsOneWidget);
  });
}
