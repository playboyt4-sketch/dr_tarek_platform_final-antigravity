import 'dart:typed_data';

import 'package:drtarek_dashboard/core/widgets/file_drop_upload_zone.dart';
import 'package:drtarek_dashboard/core/widgets/web_file_drop.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/add_attachment_resource_overlay.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/add_pdf_resource_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateUploadFile', () {
    test('accepts valid PDF up to 50MB and rejects non-PDF or >50MB', () {
      expect(
        validateUploadFile(
          fileName: 'lecture_01.pdf',
          byteCount: 1024 * 1024,
          allowedExtensions: kAllowedPdfExtensions,
          maxBytes: kMaxPdfUploadBytes,
        ).isValid,
        isTrue,
      );

      final wrongExt = validateUploadFile(
        fileName: 'notes.docx',
        byteCount: 1024,
        allowedExtensions: kAllowedPdfExtensions,
        maxBytes: kMaxPdfUploadBytes,
      );
      expect(wrongExt.isValid, isFalse);
      expect(wrongExt.errorMessage, contains('PDF'));

      final tooLarge = validateUploadFile(
        fileName: 'huge.pdf',
        byteCount: kMaxPdfUploadBytes + 1,
        allowedExtensions: kAllowedPdfExtensions,
        maxBytes: kMaxPdfUploadBytes,
      );
      expect(tooLarge.isValid, isFalse);
      expect(tooLarge.errorMessage, contains('50 MB'));
    });

    test('accepts JPG/JPEG/PNG/WEBP images up to 10MB and rejects >10MB or invalid format', () {
      for (final ext in const ['jpg', 'jpeg', 'png', 'webp']) {
        expect(
          validateUploadFile(
            fileName: 'poster.$ext',
            byteCount: 2 * 1024 * 1024,
            allowedExtensions: kAllowedImageExtensions,
            maxBytes: kMaxImageUploadBytes,
          ).isValid,
          isTrue,
        );
      }

      expect(
        validateUploadFile(
          fileName: 'poster.gif',
          byteCount: 1024,
          allowedExtensions: kAllowedImageExtensions,
          maxBytes: kMaxImageUploadBytes,
        ).isValid,
        isFalse,
      );

      final tooBigImage = validateUploadFile(
        fileName: 'poster.png',
        byteCount: kMaxImageUploadBytes + 1,
        allowedExtensions: kAllowedImageExtensions,
        maxBytes: kMaxImageUploadBytes,
      );
      expect(tooBigImage.isValid, isFalse);
      expect(tooBigImage.errorMessage, contains('10 MB'));
    });
  });

  group('FileDropUploadZone widget behavior', () {
    testWidgets(
        'highlights on drag-over, rejects invalid drops, and accepts valid drops',
        (WidgetTester tester) async {
      DroppedFileData? accepted;
      final zoneKey = GlobalKey<FileDropUploadZoneState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: FileDropUploadZone(
                key: zoneKey,
                allowedExtensions: kAllowedPdfExtensions,
                maxBytes: kMaxPdfUploadBytes,
                subtitle: 'PDF فقط • الحد الأقصى 50MB',
                onFileAccepted: (DroppedFileData file) async {
                  accepted = file;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('file-drop-zone-surface')), findsOneWidget);
      expect(find.text('اسحب وأفلت الملف هنا أو اضغط للاختيار'), findsOneWidget);

      // Drag over highlights the drop zone with Arabic drop text.
      zoneKey.currentState!.setDraggingOver(true);
      await tester.pump();
      expect(zoneKey.currentState!.isDraggingOver, isTrue);
      expect(find.text('أفلت الملف هنا للرفع'), findsOneWidget);

      zoneKey.currentState!.setDraggingOver(false);
      await tester.pump();
      expect(zoneKey.currentState!.isDraggingOver, isFalse);

      // Dropping wrong extension shows validation error and never calls onFileAccepted.
      await zoneKey.currentState!.handleDroppedFile(
        DroppedFileData(
          name: 'image.png',
          sizeBytes: 100,
          bytes: Uint8List(100),
        ),
      );
      await tester.pump();
      expect(accepted, isNull);
      expect(find.byKey(const Key('file-drop-zone-error')), findsOneWidget);

      // Dropping oversized PDF (>50MB) shows error and never calls onFileAccepted.
      await zoneKey.currentState!.handleDroppedFile(
        DroppedFileData(
          name: 'big.pdf',
          sizeBytes: kMaxPdfUploadBytes + 1,
          bytes: Uint8List(1),
        ),
      );
      await tester.pump();
      expect(accepted, isNull);
      expect(find.textContaining('50 MB'), findsOneWidget);

      // Dropping a valid PDF clears errors and triggers onFileAccepted.
      await zoneKey.currentState!.handleDroppedFile(
        DroppedFileData(
          name: 'chapter1.pdf',
          sizeBytes: 512,
          bytes: Uint8List(512),
        ),
      );
      await tester.pump();
      expect(accepted?.name, 'chapter1.pdf');
      expect(find.byKey(const Key('file-drop-zone-error')), findsNothing);
    });

    testWidgets(
        'AddPdfResourceOverlay & AddAttachmentResourceOverlay render FileDropUploadZone without overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AddPdfResourceOverlay()),
        ),
      );
      expect(find.byType(FileDropUploadZone), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AddAttachmentResourceOverlay()),
        ),
      );
      expect(find.byType(FileDropUploadZone), findsOneWidget);
    });
  });
}
