import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../student_dashboard/presentation/providers/dashboard_providers.dart';

import '../../data/datasources/subject_navigation_remote_data_source.dart';
import '../../data/repositories/subject_navigation_repository_impl.dart';
import '../../domain/entities/subject_learning_entities.dart';
import '../../domain/repositories/subject_navigation_repository.dart';

final subjectNavigationRepositoryProvider =
    Provider<SubjectNavigationRepository>((ref) {
      return SubjectNavigationRepositoryImpl(
        remoteDataSource: SubjectNavigationRemoteDataSource(
          firestore: FirebaseFirestore.instance,
        ),
      );
    });

final subjectSectionsProvider =
    FutureProvider.family<List<LearningSection>, String>(
      (ref, subjectId) =>
          ref.watch(subjectNavigationRepositoryProvider).getSections(subjectId),
    );

final sectionLecturesProvider =
    FutureProvider.family<List<LectureSummary>, String>(
      (ref, sectionId) =>
          ref.watch(subjectNavigationRepositoryProvider).getLectures(sectionId),
    );

/// Display media for one lecture (cards + header cover): poster image
/// plus Bunny's silent preview animation for header autoplay.
class LectureDisplayMedia {
  final String? thumbnailUrl;
  final String? previewUrl;

  const LectureDisplayMedia({this.thumbnailUrl, this.previewUrl});
}

/// Batched display media for a whole section (cards + header cover) in ONE
/// callable round trip: lecture doc thumbnails first, otherwise the
/// server-resolved poster of each lecture's first video, plus Bunny's
/// silent `preview.webp` for header autoplay. Fail-open → empty map
/// (callers keep placeholders). Signed URLs live ~1h; cached per section
/// while watched.
final sectionDisplayMediaProvider =
    FutureProvider.family<Map<String, LectureDisplayMedia>, String>(
      (ref, sectionId) async {
        // Signed URLs live ~1h: keep the batch alive 30min so reopening
        // the subject shows posters instantly instead of refetching.
        final keepAlive = ref.keepAlive();
        final expiry = Timer(const Duration(minutes: 30), keepAlive.close);
        ref.onDispose(expiry.cancel);
        final stopwatch = Stopwatch()..start();
        try {
          final response = await FirebaseFunctions.instance
              .httpsCallable('getSectionDisplayMedia')
              .call({'sectionId': sectionId});
          final data = Map<String, dynamic>.from(response.data as Map);
          final items = (data['items'] as List?) ?? const [];
          final map = <String, LectureDisplayMedia>{};
          var withThumb = 0;
          var withPreview = 0;
          for (final entry in items) {
            final item = Map<String, dynamic>.from(entry as Map);
            final id = item['lectureId'] as String?;
            if (id == null || id.isEmpty) continue;
            final thumb = item['thumbnailUrl'] as String?;
            final preview = item['previewUrl'] as String?;
            if (thumb != null && thumb.isNotEmpty) withThumb++;
            if (preview != null && preview.isNotEmpty) withPreview++;
            map[id] = LectureDisplayMedia(
              thumbnailUrl:
                  (thumb != null && thumb.isNotEmpty) ? thumb : null,
              previewUrl:
                  (preview != null && preview.isNotEmpty) ? preview : null,
            );
          }
          debugPrint(
            '[VIDEO-THUMB] section=$sectionId lectures=${map.length} '
            'withThumb=$withThumb withPreview=$withPreview '
            'elapsedMs=${stopwatch.elapsedMilliseconds}',
          );
          return map;
        } catch (error) {
          debugPrint(
            '[VIDEO-THUMB] section=$sectionId FAILED '
            'errorType=${error.runtimeType} error=$error',
          );
          return const <String, LectureDisplayMedia>{};
        }
      },
    );

/// Background warm-up kicked right after login lands on Home (post-frame,
/// fire-and-forget): resolves every visible section's lectures + display
/// media maps AND downloads the poster/preview bytes into the image cache,
/// so opening any subject later renders instantly from the 30min keepAlive
/// cache + warm [ImageCache]. Never blocks navigation, never throws —
/// any failure degrades to today's lazy behavior. Order follows the Home
/// carousel (first subject first) so the likeliest tap warms earliest.
Future<void> warmUpSubjectMedia(WidgetRef ref, BuildContext context) async {
  final stopwatch = Stopwatch()..start();
  var sectionsWarmed = 0;
  try {
    final subjects = await ref.read(dashboardSubjectsProvider.future);
    for (final subject in subjects) {
      if (!context.mounted) return;
      List<LearningSection> sections;
      try {
        sections = await ref.read(
          subjectSectionsProvider(subject.id).future,
        );
      } catch (_) {
        continue;
      }
      for (final section in sections) {
        if (!context.mounted) return;
        if (!section.isVisible || section.isLocked) continue;
        try {
          final lecturesFuture = ref.read(
            sectionLecturesProvider(section.id).future,
          );
          final mediaFuture = ref.read(
            sectionDisplayMediaProvider(section.id).future,
          );
          final results = await Future.wait([
            lecturesFuture,
            mediaFuture,
          ]);
          if (!context.mounted) return;
          final media = results[1] as Map<String, LectureDisplayMedia>;
          sectionsWarmed++;
          for (final entry in media.values) {
            for (final url in [
              entry.thumbnailUrl,
              entry.previewUrl,
            ]) {
              if (url == null || url.isEmpty) continue;
              unawaited(
                precacheImage(NetworkImage(url), context).catchError((
                  _,
                ) {
                  // A single undecodable image must never fail warm-up.
                }),
              );
            }
          }
        } catch (_) {
          continue;
        }
      }
    }
  } catch (_) {
    // Entire warm-up is best-effort.
  }
  debugPrint(
    '[VIDEO-THUMB] warmup done sections=$sectionsWarmed '
    'elapsedMs=${stopwatch.elapsedMilliseconds}',
  );
}
