import 'package:cloud_functions/cloud_functions.dart';

import '../../applications/presentation/providers/application_decision_provider.dart'
    show DecisionFailure;

/// ADR-010 — Dashboard gateway for the server-verified library association.
///
/// The Dashboard never writes `bunny_library_id` itself (Firestore Rules deny
/// it). It asks the server to verify the (library, video) pair for one specific
/// resource, receives a receipt bound to that resource, and then asks the
/// server to persist the association:
///
///  1. `validateBunnyVideoAssociation` — Stream metadata check for exactly
///     (libraryId, videoId); returns `verified` + a resource-bound receipt, or
///     a non-success verdict.
///  2. `associateBunnyVideoToLibrary` — re-checks authority and the trusted
///     document, verifies the receipt, writes `bunny_library_id`
///     (+ `bunny_video_id` when rebinding) and recomputes `first_video`.
///
/// Neither call returns credentials, and no URL is built here. A failure is
/// surfaced to the author: the row stays pending, which the issuance gate
/// refuses to play.
abstract class BunnyAssociationGateway {
  /// Verify and persist the association for one video resource.
  ///
  /// Throws [DecisionFailure] with a doctor-readable message when the server
  /// rejects the association or cannot be reached.
  Future<void> associate({
    required String resourceId,
    required String lectureId,
    required String libraryId,
    required String videoId,
    bool replaceVideo = false,
  });
}

/// Production gateway backed by Firebase Callable Functions.
class CallableBunnyAssociationGateway implements BunnyAssociationGateway {
  CallableBunnyAssociationGateway(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<void> associate({
    required String resourceId,
    required String lectureId,
    required String libraryId,
    required String videoId,
    bool replaceVideo = false,
  }) async {
    Object? receipt;
    try {
      final HttpsCallableResult<dynamic> validation = await _functions
          .httpsCallable('validateBunnyVideoAssociation')
          .call(<String, dynamic>{
        'libraryId': libraryId,
        'videoId': videoId,
        'resourceId': resourceId,
        'lectureId': lectureId,
      });
      final Object? data = validation.data;
      final Map<String, dynamic> payload = data is Map
          ? Map<String, dynamic>.from(data)
          : const <String, dynamic>{};
      if (payload['status'] != 'verified') {
        throw DecisionFailure(
          'This Video ID could not be verified in the selected library '
          '(${payload['reason'] ?? 'unavailable'}).',
        );
      }
      receipt = payload['receipt'];
      if (receipt == null) {
        throw const DecisionFailure(
          'The server did not return a verification receipt.',
        );
      }
    } on FirebaseFunctionsException catch (error) {
      throw DecisionFailure(
        error.message ?? 'Video verification could not be completed.',
      );
    }

    try {
      await _functions.httpsCallable('associateBunnyVideoToLibrary').call(
        <String, dynamic>{
          'resourceId': resourceId,
          'lectureId': lectureId,
          'libraryId': libraryId,
          'videoId': videoId,
          'replaceVideo': replaceVideo,
          'receipt': receipt,
        },
      );
    } on FirebaseFunctionsException catch (error) {
      throw DecisionFailure(
        error.message ?? 'The verified library association was not saved.',
      );
    }
  }
}
