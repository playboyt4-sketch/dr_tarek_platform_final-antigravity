import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final dashboardSubjectsProvider = FutureProvider<List<DashboardSubject>>((ref) {
  final studentId = FirebaseAuth.instance.currentUser?.uid;
  if (studentId == null) return const <DashboardSubject>[];
  return ref
      .watch(dashboardRepositoryProvider)
      .getAccessibleSubjects(studentId: studentId);
});
