import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/lecture/data/datasources/lecture_remote_data_source.dart';
import 'package:dr_tarek_platform/features/lecture/domain/entities/lecture_resource.dart';

class _RecordingFunctions extends Fake implements FirebaseFunctions {
  _RecordingFunctions(this.response);

  final Map<String, dynamic> response;
  String? requestedFunctionName;
  Object? requestedPayload;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    requestedFunctionName = name;
    return _CapturingCallable(this);
  }
}

class _CapturingCallable extends Fake implements HttpsCallable {
  _CapturingCallable(this._functions);

  final _RecordingFunctions _functions;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? payload]) async {
    _functions.requestedPayload = payload;
    return _FakeResult<T>(_functions.response as T);
  }
}

class _FakeResult<T> extends Fake implements HttpsCallableResult<T> {
  _FakeResult(this.data);

  @override
  final T data;
}

void main() {
  test('getResourcesForLecture uses the authorized callable and maps '
      'the safe projection', () async {
    final functions = _RecordingFunctions(const {
      'resources': [
        {
          'id': 'res-1',
          'resourceType': 'video',
          'title': 'الفيديو الأول',
          'bunnyVideoId': 'bunny-123',
          'storagePath': null,
          'thumbnail': 'https://thumb',
          'duration': 610,
          'displayOrder': 1,
        },
        {
          'id': 'res-2',
          'resourceType': 'pdf',
          'title': 'الملف',
          'bunnyVideoId': null,
          'storagePath': 'lecture_resources/x/file.pdf',
          'thumbnail': null,
          'duration': null,
          'displayOrder': 2,
        },
      ],
    });

    final dataSource = LectureRemoteDataSource(functions: functions);

    final resources = await dataSource.getResourcesForLecture('lecture-9');

    expect(functions.requestedFunctionName, 'getLectureResources');
    expect(functions.requestedPayload, {'lectureId': 'lecture-9'});

    expect(resources, hasLength(2));

    final video = resources[0];
    expect(video.id, 'res-1');
    expect(video.lectureId, 'lecture-9');
    expect(video.resourceType, LectureResourceType.video);
    expect(video.bunnyVideoId, 'bunny-123');
    expect(video.thumbnail, 'https://thumb');
    expect(video.duration, 610);
    // Raw resource URLs must never reach the client entity.
    expect(video.resourceUrl, isEmpty);

    final pdf = resources[1];
    expect(pdf.resourceType, LectureResourceType.pdf);
    expect(pdf.resourceUrl, isEmpty);
  });

  test('getResourcesForLecture drops malformed entries', () async {
    final functions = _RecordingFunctions(const {
      'resources': [
        {'id': '', 'resourceType': 'video'},
        {'id': 'res-ok', 'resourceType': 'unknown-kind'},
      ],
    });

    final dataSource = LectureRemoteDataSource(functions: functions);

    final resources = await dataSource.getResourcesForLecture('lecture-1');

    expect(resources, hasLength(1));
    expect(resources.single.id, 'res-ok');
    expect(resources.single.resourceType, LectureResourceType.externalLink);
  });
}
