import 'package:flutter/material.dart';

/// Shared confirmation dialog before moving a student, subject, or lecture to
/// the Archive (soft delete).
Future<bool> showArchiveConfirmDialog({
  required BuildContext context,
  required String entityLabel,
  required String itemTitle,
  String? extraNote,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text('Move $entityLabel to Archive'),
      content: Text(
        'Are you sure you want to archive "$itemTitle"? '
        'It will be hidden from active lists and moved to the Archive.\n'
        'سيتم نقل "$itemTitle" إلى الأرشيف وإخفاؤه من القوائم النشطة.'
        '${extraNote != null ? '\n\n$extraNote' : ''}',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Move to Archive'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
