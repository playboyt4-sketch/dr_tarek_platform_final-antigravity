import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads the current snapshot of [query] via a live Firestore `.snapshots()`
/// stream and automatically invalidates [ref] whenever subsequent Firestore
/// changes arrive while the provider is mounted.
///
/// Works seamlessly with both UI `ref.watch(...)` (real-time auto-updates with
/// zero manual refresh) and one-shot `container.read(provider.future)` calls.
Future<QuerySnapshot<Map<String, dynamic>>> watchQuerySnapshot(
  Ref ref,
  Query<Map<String, dynamic>> query,
) {
  final Completer<QuerySnapshot<Map<String, dynamic>>> first =
      Completer<QuerySnapshot<Map<String, dynamic>>>();
  bool deliveredFirst = false;

  final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> sub =
      query.snapshots().listen(
    (QuerySnapshot<Map<String, dynamic>> snap) {
      if (!deliveredFirst) {
        deliveredFirst = true;
        if (!first.isCompleted) first.complete(snap);
      } else {
        ref.invalidateSelf();
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!deliveredFirst && !first.isCompleted) {
        deliveredFirst = true;
        first.completeError(error, stackTrace);
      }
    },
  );
  ref.onDispose(sub.cancel);
  return first.future;
}
