import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_file_drop.dart';

class _DropTargetEntry {
  final bool Function(double clientX, double clientY) hitTest;
  final void Function(bool isDraggingOver) onDragOverChanged;
  final Future<void> Function(DroppedFileData file) onDrop;
  bool isOver = false;

  _DropTargetEntry({
    required this.hitTest,
    required this.onDragOverChanged,
    required this.onDrop,
  });

  void setOver(bool next) {
    if (isOver == next) return;
    isOver = next;
    onDragOverChanged(next);
  }
}

class _WebFileDropDispatcher {
  static final _WebFileDropDispatcher instance = _WebFileDropDispatcher._();

  _WebFileDropDispatcher._();

  final List<_DropTargetEntry> _targets = <_DropTargetEntry>[];
  bool _attached = false;

  late final JSFunction _onDragEnterJs = ((web.Event event) {
    _handleDragOver(event as web.DragEvent);
  }).toJS;

  late final JSFunction _onDragOverJs = ((web.Event event) {
    _handleDragOver(event as web.DragEvent);
  }).toJS;

  late final JSFunction _onDragLeaveJs = ((web.Event event) {
    final dragEvent = event as web.DragEvent;
    final num x = dragEvent.clientX;
    final num y = dragEvent.clientY;
    if (x <= 0 ||
        y <= 0 ||
        x >= web.window.innerWidth ||
        y >= web.window.innerHeight) {
      _clearAllHoverStates();
    }
  }).toJS;

  late final JSFunction _onDropJs = ((web.Event event) {
    unawaited(_handleDrop(event as web.DragEvent));
  }).toJS;

  bool _hasFiles(web.DragEvent event) {
    final types = event.dataTransfer?.types;
    if (types == null) return false;
    final int len = types.length;
    for (int i = 0; i < len; i++) {
      if (types[i].toDart == 'Files') {
        return true;
      }
    }
    return false;
  }

  _DropTargetEntry? _findTopMatch(double x, double y) {
    for (int i = _targets.length - 1; i >= 0; i--) {
      final entry = _targets[i];
      if (entry.hitTest(x, y)) {
        return entry;
      }
    }
    return null;
  }

  void _clearAllHoverStates() {
    for (final entry in _targets) {
      entry.setOver(false);
    }
  }

  void _handleDragOver(web.DragEvent event) {
    if (!_hasFiles(event)) return;
    event.preventDefault();
    final double x = event.clientX.toDouble();
    final double y = event.clientY.toDouble();
    final _DropTargetEntry? matched = _findTopMatch(x, y);
    if (matched != null) {
      event.dataTransfer?.dropEffect = 'copy';
    } else {
      event.dataTransfer?.dropEffect = 'none';
    }
    for (final entry in _targets) {
      entry.setOver(identical(entry, matched));
    }
  }

  Future<void> _handleDrop(web.DragEvent event) async {
    if (!_hasFiles(event)) return;
    event.preventDefault();
    final double x = event.clientX.toDouble();
    final double y = event.clientY.toDouble();
    final _DropTargetEntry? matched = _findTopMatch(x, y);
    _clearAllHoverStates();
    if (matched == null) return;

    final web.FileList? files = event.dataTransfer?.files;
    if (files == null || files.length == 0) return;
    final web.File? file = files.item(0);
    if (file == null) return;

    final JSArrayBuffer buffer = await file.arrayBuffer().toDart;
    final Uint8List bytes = buffer.toDart.asUint8List();

    await matched.onDrop(
      DroppedFileData(
        name: file.name,
        sizeBytes: file.size,
        bytes: bytes,
        mimeType: file.type,
      ),
    );
  }

  void _ensureAttached() {
    if (_attached) return;
    _attached = true;
    web.window.addEventListener('dragenter', _onDragEnterJs);
    web.window.addEventListener('dragover', _onDragOverJs);
    web.window.addEventListener('dragleave', _onDragLeaveJs);
    web.window.addEventListener('drop', _onDropJs);
  }

  void _detachIfEmpty() {
    if (!_attached || _targets.isNotEmpty) return;
    _attached = false;
    web.window.removeEventListener('dragenter', _onDragEnterJs);
    web.window.removeEventListener('dragover', _onDragOverJs);
    web.window.removeEventListener('dragleave', _onDragLeaveJs);
    web.window.removeEventListener('drop', _onDropJs);
  }

  WebDropRegistration register(_DropTargetEntry entry) {
    _targets.add(entry);
    _ensureAttached();
    return _WebDropHandle(this, entry);
  }

  void unregister(_DropTargetEntry entry) {
    entry.setOver(false);
    _targets.remove(entry);
    _detachIfEmpty();
  }
}

class _WebDropHandle implements WebDropRegistration {
  final _WebFileDropDispatcher _dispatcher;
  final _DropTargetEntry _entry;
  bool _disposed = false;

  _WebDropHandle(this._dispatcher, this._entry);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dispatcher.unregister(_entry);
  }
}

WebDropRegistration registerWebFileDropTarget({
  required bool Function(double clientX, double clientY) hitTest,
  required void Function(bool isDraggingOver) onDragOverChanged,
  required Future<void> Function(DroppedFileData file) onDrop,
}) {
  return _WebFileDropDispatcher.instance.register(
    _DropTargetEntry(
      hitTest: hitTest,
      onDragOverChanged: onDragOverChanged,
      onDrop: onDrop,
    ),
  );
}
