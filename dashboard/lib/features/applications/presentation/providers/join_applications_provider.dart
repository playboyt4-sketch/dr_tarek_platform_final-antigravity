import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../students/domain/live_student.dart';
import '../../domain/entities/join_application.dart';

final joinApplicationsProvider =
    StreamProvider<List<JoinApplication>>((ref) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('users')
      .where('role', isEqualTo: 'new_student')
      .where('approval_status', isEqualTo: 'pending')
      .snapshots()
      .map(
        (QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
            .where((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                isLiveStudent(doc.data()))
            .map(JoinApplication.fromDoc)
            .toList(growable: false),
      );
});
