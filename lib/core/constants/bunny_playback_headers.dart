/// HTTP headers attached to Bunny Stream playback sources.
///
/// The production Stream pull zone has hotlink protection configured to
/// reject requests with an EMPTY `Referer` (verified live: the same signed
/// URL returns 403 with no Referer and 200 with any non-empty Referer).
/// Native AVPlayer/ExoPlayer send no Referer by default, so iOS/Android were
/// blocked before the request ever reached token validation.
///
/// The signed directory token remains the actual access control; this header
/// only satisfies the pull zone's request-origin filter. Flutter Web cannot
/// set `Referer` from JavaScript and does not need to: the browser sends the
/// page origin automatically, which is non-empty and therefore accepted.
const Map<String, String> bunnyPlaybackHttpHeaders = <String, String>{
  'Referer': 'https://dr-tarek-platform.web.app/',
};
