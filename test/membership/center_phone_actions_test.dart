import 'package:dr_tarek_platform/features/membership/presentation/widgets/center_phone_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Center phone URI builders', () {
    test('normalizes Egyptian local mobile to WhatsApp wa.me URI', () {
      expect(normalizeEgyptianWhatsAppNumber('01098282915'), '201098282915');
      expect(normalizeEgyptianWhatsAppNumber('+20 109-828-2915'), '201098282915');
      expect(
        buildWhatsAppUri('01098282915').toString(),
        'https://wa.me/201098282915',
      );
      expect(buildPhoneCallUri('01098282915').toString(), 'tel:01098282915');
    });
  });

  group('CenterPhoneActions widget', () {
    testWidgets('renders Copy, Call, and WhatsApp buttons and handles taps', (
      tester,
    ) async {
      final launched = <Uri>[];
      String? copiedText;

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CenterPhoneActions(
              phoneNumber: '01098282915',
              launchUriOverride: (uri) async {
                launched.add(uri);
                return true;
              },
            ),
          ),
        ),
      );

      expect(find.text('01098282915'), findsOneWidget);
      expect(find.byKey(const ValueKey('center_phone_copy_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('center_phone_call_btn')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('center_phone_whatsapp_btn')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('center_phone_copy_btn')));
      await tester.pump();
      expect(copiedText, '01098282915');
      expect(find.text('تم نسخ الرقم'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('center_phone_call_btn')));
      await tester.tap(find.byKey(const ValueKey('center_phone_whatsapp_btn')));
      await tester.pump();

      expect(launched.map((u) => u.toString()).toList(), [
        'tel:01098282915',
        'https://wa.me/201098282915',
      ]);
    });
  });
}
