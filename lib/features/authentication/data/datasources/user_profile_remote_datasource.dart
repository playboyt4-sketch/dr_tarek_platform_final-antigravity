import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/auth_user_model.dart';

class UserProfileRemoteDataSource {
  final FirebaseFirestore firestore;

  const UserProfileRemoteDataSource({required this.firestore});

  Future<AuthUserModel?> getUserById(String userId) async {
    final snapshot = await firestore.collection('users').doc(userId).get();

    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }

    return AuthUserModel.fromMap(snapshot.id, snapshot.data()!);
  }
}
