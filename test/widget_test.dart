import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omr_scanner/main.dart';
import 'package:omr_scanner/services/storage_service.dart';

void main() {
  testWidgets('OMR Scanner home screen smoke test', (WidgetTester tester) async {
    await StorageService().init(inMemoryOnly: true);
    await tester.pumpWidget(const OMRScannerApp());
    await tester.pumpAndSettle();

    expect(find.text('OMR Scanner'), findsOneWidget);
    expect(find.text('Recent Scans History'), findsOneWidget);
    expect(find.text('Upload File'), findsOneWidget);
    expect(find.text('User Manual'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_rounded), findsWidgets);
  });
}
