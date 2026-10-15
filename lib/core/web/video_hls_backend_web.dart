import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player_web_hls/video_player_web_hls.dart';

/// Web-only HLS backend installer.
///
/// Replaces the stock `video_player_web` backend with the HLS-capable one
/// (`VideoPlayerPluginHls`), which attaches the hls.js global from
/// `web/index.html` to the plugin-owned `<video>` element and feeds it the
/// signed `.m3u8` URL unmodified. Non-HLS URLs fall through to plain
/// `<video>` behavior inside the plugin. Never called on mobile (see the
/// conditional import at the call site + the stub); the backend performs
/// no networking, signing, or entitlement work itself.
void ensureWebHlsPlaybackBackend() {
  VideoPlayerPlatform.instance = VideoPlayerPluginHls();
}
