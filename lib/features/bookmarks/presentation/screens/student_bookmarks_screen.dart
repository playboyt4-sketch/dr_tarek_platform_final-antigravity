import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bookmarks_providers.dart';

/// Student-level bookmarks list — reads exclusively through the bookmarks
/// repository ([studentBookmarksStreamProvider]).
class BookmarksScreen extends ConsumerWidget {
  final String studentId;
  const BookmarksScreen({required this.studentId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync =
        ref.watch(studentBookmarksStreamProvider(studentId));
    return Scaffold(
      appBar: AppBar(title: const Text('المحفوظات')),
      body: bookmarksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('لا توجد محاضرات محفوظة بعد.')),
        data: (bookmarks) {
          if (bookmarks.isEmpty) {
            return const Center(child: Text('لا توجد محاضرات محفوظة بعد.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bookmarks.length,
            itemBuilder: (_, index) {
              final bookmark = bookmarks[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.bookmark_border_rounded),
                  title: Text(bookmark.title),
                  subtitle: Text(bookmark.lectureId),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
