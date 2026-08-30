import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/notes_repository.dart';
import '../providers/notes_providers.dart';

/// Student-level notes (all lectures) — presentation only; data flows through
/// [NotesRepository] via [studentNotesStreamProvider].
class NotesScreen extends ConsumerStatefulWidget {
  final String studentId;
  const NotesScreen({required this.studentId, super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  Future<void> _addNote() async {
    final title = TextEditingController();
    final content = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ملاحظة جديدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result != true || title.text.trim().isEmpty) return;
    try {
      final repo = ref.read(notesRepositoryProvider);
      await repo.createQuickNote(
        studentId: widget.studentId,
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
