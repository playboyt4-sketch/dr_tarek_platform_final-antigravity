import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/playback_entities.dart';

abstract interface class PlaybackRepository {
  Future<PlaybackProgressRecord?> read(String lectureId);

  Future<void> save(PlaybackProgressRecord record, {bool syncCloud = true});

  Future<List<PlaybackProgressRecord>> getContinueWatching({int limit = 20});
}

class PlaybackRepositoryImpl implements PlaybackRepository {
  final String userId;
  final SharedPreferences localStore;
  final FirebaseFirestore? firestore;

  const PlaybackRepositoryImpl({
    required this.userId,
    required this.localStore,
    this.firestore,
  });

  String _key(String lectureId) => 'playback_progress_${userId}_$lectureId';

  @override
  Future<PlaybackProgressRecord?> read(String lectureId) async {
    final local = _readLocal(lectureId);
    try {
      final remote = await firestore
          ?.collection('lecture_progress')
          .doc('${userId}_$lectureId')
          .get();
      if (remote != null && remote.exists) {
        final cloud = _fromFirestore(
          remote.data() ?? <String, dynamic>{},
          lectureId,
        );
        if (cloud != null &&
            (local == null || cloud.updatedAt.isAfter(local.updatedAt))) {
          await _writeLocal(cloud);
          return cloud;
        }
      }
    } catch (_) {
      // Local restoration is intentionally independent of the network.
    }
    return local;
  }

  @override
  Future<void> save(
    PlaybackProgressRecord record, {
    bool syncCloud = true,
  }) async {
    await _writeLocal(record);
    if (!syncCloud) return;

    try {
      await firestore
          ?.collection('lecture_progress')
          .doc('${userId}_${record.lectureId}')
          .set({
            'student_id': userId,
            'lecture_id': record.lectureId,
            if (record.subjectId != null) 'subject_id': record.subjectId,
            if (record.sectionId != null) 'section_id': record.sectionId,
            if (record.lectureTitle != null)
              'lecture_title': record.lectureTitle,
            if (record.thumbnailUrl != null)
              'thumbnail_url': record.thumbnailUrl,
            'position_seconds': record.position.inMilliseconds / 1000,
            'duration_seconds': record.duration.inMilliseconds / 1000,
            'progress_percent': record.progressPercent * 100,
            'completed': record.completed,
            'is_completed': record.completed,
            if (record.completed) 'completed_at': FieldValue.serverTimestamp(),
            if (record.pdfLastPage != null) 'pdf_last_page': record.pdfLastPage,
            if (record.pdfTotalPages != null) 'pdf_total_pages': record.pdfTotalPages,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {
      // The local copy remains authoritative until a later save succeeds.
    }
  }

  @override
  Future<List<PlaybackProgressRecord>> getContinueWatching({
    int limit = 20,
  }) async {
    final localRecords = <PlaybackProgressRecord>[];
    for (final key in localStore.getKeys().where(
      (key) => key.startsWith('playback_progress_${userId}_'),
    )) {
      final raw = localStore.getString(key);
      if (raw == null) continue;
      try {
        final record = PlaybackProgressRecord.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (ProgressMath.hasMeaningfulProgress(record)) {
          localRecords.add(record);
        }
      } catch (_) {
        // Ignore corrupted records without preventing the rest of the dashboard from loading.
      }
    }

    try {
      final snapshot = await firestore
          ?.collection('lecture_progress')
          .where('student_id', isEqualTo: userId)
          .orderBy('updated_at', descending: true)
          .limit(limit)
          .get();
      if (snapshot == null) {
        localRecords.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return localRecords.take(limit).toList();
      }
      final cloudRecords = snapshot.docs
          .map(
            (doc) => _fromFirestore(
              doc.data(),
              doc.id.replaceFirst('${userId}_', ''),
            ),
          )
          .whereType<PlaybackProgressRecord>()
          .where(ProgressMath.hasMeaningfulProgress)
          .toList();
      final merged = <String, PlaybackProgressRecord>{
        for (final record in localRecords) record.lectureId: record,
      };
      for (final record in cloudRecords) {
        final current = merged[record.lectureId];
        if (current == null || record.updatedAt.isAfter(current.updatedAt)) {
          merged[record.lectureId] = record;
        }
      }
      final result = merged.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return result.take(limit).toList();
    } catch (_) {
      localRecords.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return localRecords.take(limit).toList();
    }
  }

  PlaybackProgressRecord? _readLocal(String lectureId) {
    final raw = localStore.getString(_key(lectureId));
    if (raw == null) return null;
    try {
      return PlaybackProgressRecord.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLocal(PlaybackProgressRecord record) async {
    await localStore.setString(
      _key(record.lectureId),
      jsonEncode(record.toJson()),
    );
  }

  PlaybackProgressRecord? _fromFirestore(
    Map<String, dynamic> data,
    String lectureId,
  ) {
    final position = _duration(data['position_seconds']);
    final duration = _duration(data['duration_seconds']);
    if (data['student_id'] is! String || data['student_id'] != userId) {
      return null;
    }
    return PlaybackProgressRecord(
      userId: userId,
      lectureId: (data['lecture_id'] as String?) ?? lectureId,
      subjectId: data['subject_id'] as String?,
      sectionId: data['section_id'] as String?,
      lectureTitle: data['lecture_title'] as String?,
      thumbnailUrl: data['thumbnail_url'] as String?,
      position: ProgressMath.clampPosition(position, duration),
      duration: duration,
      progressPercent: ProgressMath.percent(position, duration),
      completed:
          data['completed'] == true ||
          data['is_completed'] == true ||
          ProgressMath.isCompleted(position, duration),
      updatedAt: _date(data['updated_at']),
      pdfLastPage: data['pdf_last_page'] as int?,
      pdfTotalPages: data['pdf_total_pages'] as int?,
    );
  }

  Duration _duration(Object? value) {
    final seconds = value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? 0;
    return Duration(
      milliseconds: (seconds.clamp(0, 24 * 60 * 60) * 1000).round(),
    );
  }

  DateTime _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse('$value') ?? DateTime.now();
  }
}
