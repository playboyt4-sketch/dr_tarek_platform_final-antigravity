import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';

/// Broadcast audiences for the quick announcement dialog.
const List<({String key, String label})> announcementAudiences =
    <({String key, String label})>[
  (key: 'all', label: 'All students'),
  (key: 'grade_one', label: 'Grade One'),
  (key: 'grade_two', label: 'Grade Two'),
  (key: 'grade_three', label: 'Grade Three'),
  (key: 'grade_four', label: 'Grade Four'),
  (key: 'center_only', label: 'Center students only'),
];

/// Pure validation for the announcement form.
String? validateAnnouncement({
  required String title,
  required String body,
}) {
  if (title.trim().isEmpty) return 'Notice title is required.';
  if (body.trim().isEmpty) return 'Message body is required.';
  return null;
}

/// Builds the broadcast envelope stored alongside the notification doc.
/// A backend fan-out trigger expands it into per-student `notifications`
/// docs (same `notifications` collection the phones already watch).
Map<String, dynamic> announcementAudienceDoc(String audienceKey) {
  return switch (audienceKey) {
    'grade_one' ||
    'grade_two' ||
    'grade_three' ||
    'grade_four' =>
      <String, dynamic>{
        'audience_type': 'grade',
        'grade': audienceKey,
        'center_only': false,
      },
    'center_only' => <String, dynamic>{
        'audience_type': 'center',
        'grade': null,
        'center_only': true,
      },
    _ => <String, dynamic>{
        'audience_type': 'all',
        'grade': null,
        'center_only': false,
      },
  };
}

/// Opens the Quick Announcement dialog from the "Send Announcement" card.
Future<bool?> showQuickAnnouncementDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: QuickAnnouncementForm(),
        ),
      ),
    ),
  );
}

/// Audience → title → body → instant broadcast.
class QuickAnnouncementForm extends ConsumerStatefulWidget {
  const QuickAnnouncementForm({super.key});

  @override
  ConsumerState<QuickAnnouncementForm> createState() =>
      _QuickAnnouncementFormState();
}

class _QuickAnnouncementFormState
    extends ConsumerState<QuickAnnouncementForm> {
  String _audienceKey = 'all';
  bool _sending = false;
  String? _error;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String? validationError = validateAnnouncement(
      title: _titleController.text,
      body: _bodyController.text,
    );
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;
      String actorId = 'dashboard';
      try {
        actorId = FirebaseAuth.instance.currentUser?.uid ?? 'dashboard';
      } catch (_) {
        actorId = 'dashboard';
      }
      await publishAnnouncement(
        db: db,
        actorId: actorId,
        audienceKey: _audienceKey,
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is StateError
            ? e.message
            : 'Could not send the announcement. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Send Announcement',
          style: AppTypography.gradeTitle(fontSize: 22),
        ),
        const SizedBox(height: 4),
        Text(
          'Broadcast instantly to student phones.',
          style: AppTypography.actionDesc(),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _audienceKey,
          decoration: const InputDecoration(labelText: 'Target audience'),
          items: <DropdownMenuItem<String>>[
            for (final audience in announcementAudiences)
              DropdownMenuItem<String>(
                value: audience.key,
                child: Text(audience.label),
              ),
          ],
          onChanged: _sending
              ? null
              : (String? value) {
                  if (value == null) return;
                  setState(() => _audienceKey = value);
                },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _titleController,
          enabled: !_sending,
          decoration: const InputDecoration(labelText: 'Notice Title'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bodyController,
          enabled: !_sending,
          decoration: const InputDecoration(labelText: 'Message Body'),
          minLines: 3,
          maxLines: 5,
          textInputAction: TextInputAction.done,
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFB3261E), fontSize: 14),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: _sending ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 180,
              height: 44,
              child: ElevatedButton(
                onPressed: _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.pillFill,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send Notice'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Persists a broadcast announcement as one `notifications` doc PER targeted
/// student (each carrying its own `user_id`), in WriteBatch chunks of 400.
///
/// The `sendPushNotification` trigger requires `user_id` on every doc, so a
/// single envelope doc without `user_id` would fail delivery. Targets are
/// resolved from `users` (`role == 'student'`, `approval_status ==
/// 'approved'), narrowed by [audienceKey]: `all`, `grade_*`, or
/// `center_only` (center students). Same per-doc wire shape the phones
/// already watch, plus the audience envelope. Returns the targeted count.
Future<int> publishAnnouncement({
  required FirebaseFirestore db,
  required String actorId,
  required String audienceKey,
  required String title,
  required String body,
}) async {
  Query<Map<String, dynamic>> query = db
      .collection('users')
      .where('role', isEqualTo: 'student')
      .where('approval_status', isEqualTo: 'approved');
  if (audienceKey == 'center_only') {
    query = query.where('student_type', isEqualTo: 'center_student');
  } else if (audienceKey.startsWith('grade_')) {
    query = query.where('grade', isEqualTo: audienceKey);
  }

  final QuerySnapshot<Map<String, dynamic>> targets = await query.get();
  if (targets.docs.isEmpty) {
    throw StateError('No targeted students found for audience "$audienceKey".');
  }

  const int batchLimit = 400;
  int written = 0;
  WriteBatch batch = db.batch();
  int ops = 0;

  Future<void> commitBatch() async {
    if (ops == 0) return;
    await batch.commit();
    batch = db.batch();
    ops = 0;
  }

  for (final QueryDocumentSnapshot<Map<String, dynamic>> student
      in targets.docs) {
    final DocumentReference<Map<String, dynamic>> ref =
        db.collection('notifications').doc();
    batch.set(ref, <String, dynamic>{
      'user_id': student.id,
      'title': title,
      'body': body,
      'type': 'Announcements',
      'notification_type': 'Announcements',
      'status': 'queued',
      'priority': 'high',
      'media_type': 'none',
      'is_read': false,
      ...announcementAudienceDoc(audienceKey),
      'created_at': FieldValue.serverTimestamp(),
      'created_by': actorId,
    });
    ops += 1;
    written += 1;
    if (ops >= batchLimit) {
      await commitBatch();
    }
  }
  await commitBatch();
  return written;
}
