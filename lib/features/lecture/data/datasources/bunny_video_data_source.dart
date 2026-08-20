import 'package:cloud_functions/cloud_functions.dart';

class BunnyVideoDataSource {
  final FirebaseFunctions _functions;

  BunnyVideoDataSource({
    FirebaseFunctions? functions,
  }) : _functions = functions ?? FirebaseFunctions.instance;

  Future<String> generateSignedUrl({
    required String videoId,
    required String quality,
    required String subjectId,
    required String deviceId,
  }) async {
    final callable = _functions.httpsCallable('generateBunnySignedUrl');

    final result = await callable.call({
      'videoId': videoId,
      'quality': quality,
      'subjectId': subjectId,
      'deviceId': deviceId,
    });

    final data = Map<String, dynamic>.from(result.data as Map);

    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('Bunny signed video URL was not returned.');
    }

    return url;
  }
}
