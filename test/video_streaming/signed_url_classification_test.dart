import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies .m3u8 playlist URLs as HLS', () {
    expect(
      classifySignedVideoUrl(
        'https://vz-abc.b-cdn.net/guid-1/720p/playlist.m3u8?token=t&expires=1',
      ),
      SignedVideoUrlType.hls,
    );
  });

  test('classifies direct .mp4 URLs as MP4', () {
    expect(
      classifySignedVideoUrl(
        'https://vz-abc.b-cdn.net/guid-1/play_720p.mp4?token=t&expires=1',
      ),
      SignedVideoUrlType.mp4,
    );
  });

  test('classifies iframe.mediadelivery.net embed URLs as embed', () {
    expect(
      classifySignedVideoUrl(
        'https://iframe.mediadelivery.net/embed/12345/abcd-efgh?token=t',
      ),
      SignedVideoUrlType.embed,
    );
  });

  test('masks only the token value, preserving the rest verbatim', () {
    const raw =
        'https://vz-abc.b-cdn.net/guid-1/playlist.m3u8?token=SECRET&expires=123';
    final masked = maskSignedUrlToken(raw);
    expect(masked, contains('token=MASKED'));
    expect(masked, isNot(contains('SECRET')));
    expect(masked, contains('vz-abc.b-cdn.net/guid-1/playlist.m3u8'));
    expect(masked, contains('expires=123'));
  });

  test('masks the in-path bcdn_token signature, keeps scope visible', () {
    const secret = 'HS256-abcDEF123signature';
    const raw =
        'https://vz-abc.b-cdn.net/bcdn_token=$secret'
        '&token_path=%2Fguid-1%2F&expires=999'
        '/guid-1/720p/playlist.m3u8';
    final masked = maskSignedUrlToken(raw);
    expect(masked, isNot(contains(secret)));
    expect(masked, contains('bcdn_token=MASKED'));
    expect(masked, contains('token_path=%2Fguid-1%2F'));
    expect(masked, contains('expires=999'));
    expect(masked, contains('/guid-1/720p/playlist.m3u8'));
  });

  test('masks both query and in-path tokens when both present', () {
    const raw =
        'https://vz-abc.b-cdn.net/bcdn_token=LIVESECRET&token_path=%2Fv%2F'
        '/v/playlist.m3u8?token=QUERYSECRET&expires=1';
    final masked = maskSignedUrlToken(raw);
    expect(masked, isNot(contains('LIVESECRET')));
    expect(masked, isNot(contains('QUERYSECRET')));
    expect(masked, contains('bcdn_token=MASKED'));
    expect(masked, contains('token=MASKED'));
  });

  test('leaves tokenless URLs byte-identical', () {
    const raw = 'https://vz-abc.b-cdn.net/guid-1/720p/playlist.m3u8';
    expect(maskSignedUrlToken(raw), raw);
  });
}
