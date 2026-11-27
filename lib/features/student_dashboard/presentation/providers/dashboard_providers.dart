import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../authentication/presentation/providers/auth_provider.dart';
import '../../data/datasources/dashboard_remote_data_source.dart';
import '../../data/repositories/dashboard_repository_impl.dart';
import '../../domain/entities/dashboard_subject.dart';
import '../../domain/repositories/dashboard_repository.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositoryImpl(
    remoteDataSource: DashboardRemoteDataSource(
      firestore: FirebaseFirestore.instance,
    ),
  );
});

final dashboardSubjectsProvider = StreamProvider<List<DashboardSubject>>((ref) {
  ref.keepAlive();
  // Watch authProvider user id so logging in/switching accounts re-subscribes
  // automatically, while still supporting direct FirebaseAuth sessions.
  String? studentId = ref.watch(
    authProvider.select((auth) => auth.asData?.value?.id),
  );
  if (studentId == null) {
    try {
      studentId = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      studentId = null;
    }
  }
  if (studentId == null || studentId.isEmpty) {
    return Stream.value(const <DashboardSubject>[]);
  }
  return ref
      .watch(dashboardRepositoryProvider)
      .watchAccessibleSubjects(studentId: studentId);
});

final Set<String> _precachedCoverKeys = <String>{};

/// Pre-warms [dashboardSubjectsProvider] and precaches subject poster images
/// into Flutter's [ImageCache] while the user is still on pre-home screens.
/// Safe, fire-and-forget, and never throws or blocks navigation.
Future<void> preloadSubjectsAndCovers(
  ProviderContainer container,
  BuildContext context,
) async {
  try {
    final subjects = await container
        .read(dashboardSubjectsProvider.future)
        .timeout(const Duration(seconds: 8));
    if (!context.mounted) return;
    await precacheSubjectCovers(context, subjects);
  } catch (_) {
    // Best-effort warmup only.
  }
}

/// Precaches all valid remote subject [thumbnailUrl]s into memory so Student Home
/// renders cards and posters immediately without a late image flash.
Future<void> precacheSubjectCovers(
  BuildContext context,
  Iterable<DashboardSubject> subjects,
) async {
  for (final subject in subjects) {
    if (!context.mounted) return;
    final rawUrl = subject.thumbnailUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) continue;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      continue;
    }
    final cacheKey =
        '${subject.id}|$rawUrl|${subject.updatedAt?.millisecondsSinceEpoch ?? 0}';
    if (!_precachedCoverKeys.add(cacheKey)) continue;
    unawaited(
      precacheImage(NetworkImage(rawUrl), context).catchError((_) {
        _precachedCoverKeys.remove(cacheKey);
      }),
    );
  }
}
