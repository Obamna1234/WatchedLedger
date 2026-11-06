import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/data/db/open.dart';
import 'package:watchedledger/features/recovery/recovery_page.dart';

void main() {
  testWidgets('recovery screen explains a missing key and keeps the file',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecoveryPage(
        problem: DbKeyProblem(File('x.sqlite'), keyMissing: true),
        onStartFresh: () async {},
        onRetry: () async {},
      ),
    ));

    expect(find.text("Your library can't be unlocked"), findsOneWidget);
    expect(find.textContaining('missing'), findsOneWidget);
    expect(find.text('Start fresh (keep old file)'), findsOneWidget);
  });
}
