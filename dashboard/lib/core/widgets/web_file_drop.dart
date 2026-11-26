import 'dart:typed_data';

import 'web_file_drop_stub.dart'
    if (dart.library.js_interop) 'web_file_drop_web.dart' as impl;

/// In-memory representation of a file dropped or picked in the dashboard.
class DroppedFileData {
  final String name;
  final int sizeBytes;
  final Uint8List bytes;
  final String mimeType;

  const DroppedFileData({
    required this.name,
    required this.sizeBytes,
    required this.bytes,
    this.mimeType = '',
  });
}

/// Subscription handle returned when registering a web drop zone target.
abstract class WebDropRegistration {
  void dispose();
}

/// Registers an active drop zone for HTML5 drag-and-drop events on web.
/// On non-web platforms this is a safe no-op.
WebDropRegistration registerWebFileDropTarget({
  required bool Function(double clientX, double clientY) hitTest,
  required void Function(bool isDraggingOver) onDragOverChanged,
  required Future<void> Function(DroppedFileData file) onDrop,
}) {
  return impl.registerWebFileDropTarget(
    hitTest: hitTest,
    onDragOverChanged: onDragOverChanged,
    onDrop: onDrop,
  );
}
