import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/lecture_provider.dart';

class LectureScreen extends ConsumerWidget {
  final String lectureId;
  final String title;

  const LectureScreen({
    required this.lectureId,
    required this.title,
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) {
    final resources = ref.watch(
      lectureResourcesProvider(lectureId),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: resources.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, _) => Center(
          child: Text(
            'Unable to load lecture resources.\n$error',
            textAlign: TextAlign.center,
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Text('No learning resources available.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final resource = items[index];

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(
                    switch (resource.resourceType) {
                      _ => Icons.play_lesson_outlined,
                    },
                  ),
                  title: Text(
                    resource.resourceType.name,
                  ),
                  subtitle: Text('Resource ${index + 1}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

