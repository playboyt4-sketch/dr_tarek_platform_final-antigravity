import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../student_dashboard/presentation/providers/dashboard_providers.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/notes_repository.dart';
import '../providers/notes_providers.dart';

/// Student-level notes (all lectures) — presentation only; data flows through
/// [NotesRepository] via [studentNotesStreamProvider].
///
/// Quick notes are subject-scoped: `firestore.rules` gates note create AND
/// read on `hasEntitlement(uid, subject_id, 'notes.create')`. When
/// [subjectId] is supplied the dialog saves directly to it; otherwise the
/// student picks one of their accessible subjects inside the dialog.
class NotesScreen extends ConsumerStatefulWidget {
  final String studentId;
  final String? subjectId;
  const NotesScreen({required this.studentId, this.subjectId, super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  Future<void> _addNote() async {
    final title = TextEditingController();
    final content = TextEditingController();
    String? pickedSubjectId = widget.subjectId;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final subjectsAsync = widget.subjectId != null
              ? null
              : ref.watch(dashboardSubjectsProvider);
          return AlertDialog(
            title: const Text('ملاحظة جديدة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subjectsAsync != null)
                  subjectsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    error: (_, _) =>
                        const Text('تعذر تحميل المواد.'),
                    data: (subjects) {
                      if (subjects.isEmpty) {
                        return const Text(
                          'لا توجد مواد متاحة لربط الملاحظة بها.',
                        );
                      }
                      pickedSubjectId ??= subjects.first.id;
                      return DropdownButtonFormField<String>(
                        initialValue: pickedSubjectId,
                        decoration: const InputDecoration(
                          labelText: 'المادة',
                        ),
                        items: [
                          for (final subject in subjects)
                            DropdownMenuItem(
                              value: subject.id,
                              child: Text(subject.title),
                            ),
                        ],
                        onChanged: (value) => setDialogState(
                          () => pickedSubjectId = value,
                        ),
                      );
                    },
                  ),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
                TextField(
                  controller: content,
                  decoration: const InputDecoration(labelText: 'المحتوى'),
                  maxLines: 4,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, true),
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
    if (result != true || title.text.trim().isEmpty) return;
    final subjectId = pickedSubjectId;
    if (subjectId == null || subjectId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر المادة المرتبطة بالملاحظة أولاً.'),
        ),
      );
      return;
    }
    try {
      final repo = ref.read(notesRepositoryProvider);
      await repo.createQuickNote(
        studentId: widget.studentId,
        subjectId: subjectId,
        title: title.text.trim(),
        content: content.text.trim(),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyFunctionErrorMessage(error, 'تعذر حفظ الملاحظة.'))),
      );
    }
  }

  Future<void> _deleteNote(Note note) async {
    try {
      await ref.read(notesRepositoryProvider).deleteNote(noteId: note.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyFunctionErrorMessage(error, 'تعذر حذف الملاحظة.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(studentNotesStreamProvider(widget.studentId));
    return Scaffold(
      appBar: AppBar(title: const Text('ملاحظاتي')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNote,
        icon: const Icon(Icons.add),
        label: const Text('ملاحظة جديدة'),
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('تعذر تحميل الملاحظات.')),
        data: (notes) {
          if (notes.isEmpty) {
            return const Center(child: Text('لم تضف أي ملاحظات بعد.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notes.length,
            itemBuilder: (_, index) {
              final note = notes[index];
              return Card(
                child: ListTile(
                  title: Text(note.title.isEmpty ? 'ملاحظة' : note.title),
                  subtitle: Text(note.content),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteNote(note),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
