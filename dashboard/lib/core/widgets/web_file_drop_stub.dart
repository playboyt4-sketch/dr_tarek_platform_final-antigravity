import 'web_file_drop.dart';

class _NoopRegistration implements WebDropRegistration {
  @override
  void dispose() {}
}

WebDropRegistration registerWebFileDropTarget({
  required bool Function(double clientX, double clientY) hitTest,
  required void Function(bool isDraggingOver) onDragOverChanged,
  required Future<void> Function(DroppedFileData file) onDrop,
}) {
  return _NoopRegistration();
}
