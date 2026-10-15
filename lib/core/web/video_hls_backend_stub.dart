/// Non-web no-op counterpart of `video_hls_backend_web.dart`.
///
/// Selected by the conditional import on every non-web target so mobile
/// and desktop builds never reference `dart:ui_web`/HLS code.
void ensureWebHlsPlaybackBackend() {}
