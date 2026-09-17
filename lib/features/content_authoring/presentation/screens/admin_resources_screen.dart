import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/admin_content_providers.dart';
import '../widgets/resource_forms.dart'
    show LectureResourceList, showAddResourceSheet;

/// Resource management per Feature 04 "Lecture Structure".
///
/// Rows follow the approved `NN. Type - Name   Edit   Delete` format with
/// drag-to-reorder; the overflow menu keeps the pre-existing visibility
/// toggle and video-thumbnail actions. Add/Edit forms live in
/// `resource_forms.dart` (shared with the Add New Lecture dialog) and
/// cover Video / PDF / Attachment / External Link only — no Timeline Quiz.
class AdminResourcesScreen extends ConsumerWidget {
  final String lectureId;
  final String lectureTitle;

  const AdminResourcesScreen({
    super.key,
    required this.lectureId,
    required this.lectureTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the live listener warm for the list below.
    ref.watch(adminResourcesProvider(lectureId));

    return Scaffold(
      appBar: AppBar(title: Text('Resources — $lectureTitle')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
        onPressed: () => showAddResourceSheet(context, ref, lectureId),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LectureResourceList(lectureId: lectureId),
      ),
    );
  }
}
