import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/nip46/presentation/nip46_qr_scan_screen.dart';

const _nostrconnect =
    'nostrconnect://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    '?relay=wss%3A%2F%2Frelay.example.com&secret=s1';

void main() {
  late void Function(String code) scan;
  late void Function() cameraFails;
  String? result;

  Future<void> open(WidgetTester tester) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => Nip46QrScanScreen(
                    readerBuilder: (onCode, onCameraError) {
                      scan = onCode;
                      cameraFails = onCameraError;
                      return const SizedBox.expand();
                    },
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('Nip46QrScanScreen (#31)', () {
    testWidgets('returns the first nostrconnect:// code', (tester) async {
      await open(tester);

      scan(_nostrconnect);
      scan('nostrconnect://another');
      await tester.pumpAndSettle();

      expect(result, _nostrconnect);
      expect(find.byType(Nip46QrScanScreen), findsNothing);
    });

    testWidgets('ignores other codes, with a hint', (tester) async {
      await open(tester);

      scan('bunker://abc?secret=x');
      scan('https://example.com');
      await tester.pumpAndSettle();

      expect(find.byType(Nip46QrScanScreen), findsOneWidget);
      expect(find.textContaining('isn’t a nostrconnect:// code'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('says so when the camera can’t be used', (tester) async {
      await open(tester);

      cameraFails();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nip46ScanCameraError')), findsOneWidget);
    });
  });
}
