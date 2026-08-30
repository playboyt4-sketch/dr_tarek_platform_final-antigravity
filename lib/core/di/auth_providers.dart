import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final customClaimsProvider = StreamProvider<Map<String, dynamic>?>((
  ref,
) async* {
  // Riverpod 3 disposes providers once their last listener is removed.
  // Claims back the whole session gate and must live for the app lifetime.
  ref.keepAlive();

  final auth = ref.watch(firebaseAuthProvider);

  await for (final user in auth.authStateChanges()) {
    if (user == null) {
      yield null;
      continue;
    }

    final tokenResult = await user.getIdTokenResult(true);
    yield tokenResult.claims;
  }
});

final userRoleProvider = Provider<String?>((ref) {
  final claims = ref.watch(customClaimsProvider).value;
  return claims?['role'] as String?;
});

final studentTypeProvider = Provider<String?>((ref) {
  final claims = ref.watch(customClaimsProvider).value;
  return claims?['student_type'] as String?;
});

final planIdProvider = Provider<String?>((ref) {
  final claims = ref.watch(customClaimsProvider).value;
  return claims?['plan_id'] as String?;
});

final maxDevicesProvider = Provider<int?>((ref) {
  final claims = ref.watch(customClaimsProvider).value;
  return (claims?['max_devices'] as num?)?.toInt();
});

final subscriptionStatusProvider = Provider<String?>((ref) {
  final claims = ref.watch(customClaimsProvider).value;
  return claims?['subscription_status'] as String?;
});

final isApprovedProvider = Provider<bool>((ref) {
  final claims = ref.watch(customClaimsProvider).value;
  return claims?['approved'] == true;
});
