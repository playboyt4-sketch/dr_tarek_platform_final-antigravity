import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/friendly_error_message.dart'
    show mapFunctionErrorCode;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_input.dart';
import '../providers/admin_content_providers.dart';
import '../screens/lecture_access_screen.dart';
import 'resource_forms.dart' show LectureResourceList, showAddResourceSheet;

/// Approved Add Lecture UI: `Add New Lecture`.
///
/// Contains ONLY: Lecture Name, Lecture Display Order, Lecture Resources
/// (+ Add Resource), Publish Date, Publish Time, Publish Now, Save Draft,
/// Guest Access + Preview Minutes, Configure Access.
/// No Grade / Subject / Year / Term / Description — those come from the
/// surrounding navigation context.
///
/// Flow: the dialog first collects the lecture fields; Save Draft / Publish
/// Now creates the lecture through the existing use-cases (description is
/// intentionally left empty); the same dialog then reveals the resources
/// section and Configure Access for the newly created lecture.
Future<bool?> showAddLectureDialog(
  BuildContext context,
  WidgetRef ref, {
  required String subjectId,
  required String sectionId,
  required String sectionTitle,
  required int initialOrder,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _AddLectureDialog(
      subjectId: subjectId,
      sectionId: sectionId,
      sectionTitle: sectionTitle,
      initialOrder: initialOrder,
    ),
  );
}

class _AddLectureDialog extends ConsumerStatefulWidget {
  final String subjectId;
  final String sectionId;
  final String sectionTitle;
  final int initialOrder;

  const _AddLectureDialog({
    required this.subjectId,
    required this.sectionId,
    required this.sectionTitle,
    required this.initialOrder,
  });

  @override
  ConsumerState<_AddLectureDialog> createState() => _AddLectureDialogState();
}

class _AddLectureDialogState extends ConsumerState<_AddLectureDialog> {
  final _name = TextEditingController();
  late final TextEditingController _order;
  final _minutes = TextEditingController();

  DateTime? _publishDate;
  TimeOfDay? _publishTime;
  bool _guestEnabled = false;
  bool _submitting = false;

  /// Set once the lecture is created; reveals resources + access.
  String? _createdLectureId;
  String _createdTitle = '';

  @override
  void initState() {
    super.initState();
    _order = TextEditingController(text: '${widget.initialOrder}');
  }

  @override
  void dispose() {
    _name.dispose();
    _order.dispose();
    _minutes.dispose();
    super.dispose();
  }

  String _dateLabel() {
    final d = _publishDate;
    if (d == null) return 'No publish date';
    return 'Publish Date: ${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  String _timeLabel() {
    final t = _publishTime;
    if (t == null) return 'No publish time';
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return 'Publish Time: $h:${t.minute.toString().padLeft(2, '0')} $period';
  }

  DateTime? _combinedPublishDateTime() {
    final d = _publishDate;
    if (d == null) return null;
    final t = _publishTime;
    return DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
  }

  int? _parseMinutes() {
    final text = _minutes.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<void> _submit({required bool publishNow}) async {
    if (_submitting) return;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lecture Name is required.')));
      return;
    }
    final order =
        int.tryParse(_order.text.trim()) ?? widget.initialOrder;
    final minutes = _parseMinutes();
    if (_guestEnabled && minutes != null && minutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Preview minutes must be a number greater than zero.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final lectureId =
          await ref.read(createLectureUseCaseProvider).execute(
                subjectId: widget.subjectId,
                sectionId: widget.sectionId,
                title: _name.text.trim(),
                // No Description field in the approved UI.
                description: '',
                displayOrder: order < 1 ? widget.initialOrder : order,
                publishDate:
                    _combinedPublishDateTime() ?? (publishNow ? DateTime.now() : null),
                guestEnabled: _guestEnabled,
                guestPreviewMinutes:
                    _guestEnabled ? minutes : null,
              );
      if (publishNow) {
        await ref.read(setLecturePublishedUseCaseProvider).execute(
            lectureId: lectureId, published: true);
      }
      if (!mounted) return;
      setState(() {
        _createdLectureId = lectureId;
        _createdTitle = _name.text.trim();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              publishNow ? 'Lecture published.' : 'Draft saved.')));
    } on Failure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(mapFunctionErrorCode('permission-denied',
                failure.debugDetail, 'Could not save the lecture.'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save the lecture.')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final createdId = _createdLectureId;
    return AlertDialog(
      title: const Text('Add New Lecture'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: createdId == null ? _fieldsPhase() : _resourcesPhase(createdId),
        ),
      ),
      actions: createdId == null
          ? [
              TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              OutlinedButton(
                  onPressed:
                      _submitting ? null : () => _submit(publishNow: false),
                  child: const Text('Save Draft')),
              FilledButton(
                  onPressed:
                      _submitting ? null : () => _submit(publishNow: true),
                  child: const Text('Publish Now')),
            ]
          : [
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done')),
            ],
    );
  }

  Widget _fieldsPhase() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Section: ${widget.sectionTitle}',
            style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        AppInput(controller: _name, hint: 'Lecture Name'),
        const SizedBox(height: 8),
        TextField(
          controller: _order,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'Lecture Display Order'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(_dateLabel())),
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: _submitting
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _publishDate ?? DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null && mounted) {
                      setState(() => _publishDate = picked);
                    }
                  },
          ),
        ]),
        Row(children: [
          Expanded(child: Text(_timeLabel())),
          IconButton(
            icon: const Icon(Icons.access_time_outlined),
            onPressed: _submitting
                ? null
                : () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _publishTime ?? TimeOfDay.now(),
                    );
                    if (picked != null && mounted) {
                      setState(() => _publishTime = picked);
                    }
                  },
          ),
        ]),
        const SizedBox(height: 8),
        Row(
          children: [
            Switch(
              value: _guestEnabled,
              activeTrackColor: AppColors.success,
              inactiveTrackColor: Colors.grey,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _guestEnabled = v),
            ),
            Expanded(
              child: Text(
                'Guest Access',
                style: TextStyle(
                    color: _guestEnabled
                        ? AppColors.success
                        : Colors.grey),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                enabled: _guestEnabled && !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Preview Duration',
                  suffixText: 'Minutes',
                  hintText: 'e.g. 5',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _resourcesPhase(String lectureId) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_createdTitle,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Add Lecture Resources',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: LectureResourceList(
              lectureId: lectureId, shrinkWrap: false),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('+ Add Resource'),
          onPressed: () =>
              showAddResourceSheet(context, ref, lectureId),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LectureAccessScreen(
                lectureId: lectureId,
                lectureTitle: _createdTitle,
                subjectId: widget.subjectId,
              ),
            ));
          },
          child: const Text('Configure Access'),
        ),
      ],
    );
  }
}
