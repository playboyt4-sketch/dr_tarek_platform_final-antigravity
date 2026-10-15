import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../authentication/presentation/providers/session_provider.dart';
import '../../domain/repositories/profile_repository.dart';
import '../providers/profile_providers.dart';

// ---------------------------------------------------------------------------
// "profile edit" bottom sheet (Figma node 58258:1891) + "Profile picture
// edit" sheet. Raw design-pixel values from Figma dev mode, consumed via
// context.rs() / context.rsV() / context.rsFont() — identical to Figma at
// the 393x852 reference.
//
// Frame map (dev mode paste, node 58258:1891 — 393x679 panel):
//   sheet     393x679 white, top r24, 1px white side stroke, drag handle
//             36x4 #E5E7EB at top center, close X 44x44 at (325,24)
//   rows      345x64   grade-canvas 15% fill, padding h8 v4; first row
//             top r28; row content spaceBetween:
//             - "Profile picture" 14 black + 56x56 avatar (gradient white
//               28%->4%, 1px white 45% ring) → opens the picture sheet
//             - "Name\n<name>" 14 black (left) → editable (students may
//               self-edit `full_name` per firestore.rules)
//             - "Phone\n<phone>" 14 black (left) → display only
//               (`phone_number` is immutable client-side)
//             - "Devices\nDevice 0i … <model>" 14 black → display only,
//               live from the student's `devices` rows
// Picture sheet: "Take a photo" (camera) + "Choose from gallery" rows.
// ---------------------------------------------------------------------------

/// One device row of the signed-in student (`devices` collection).
class StudentDevice {
  final String id;
  final String model;

  const StudentDevice({required this.id, required this.model});
}

/// Live device rows of [studentId] (`devices` where `user_id` matches).
///
/// Students may read their own device rows per firestore.rules; staff read
/// via delegation. An empty list means no bound device — the UI renders
/// an explicit placeholder, never an invented model name.
final studentDevicesProvider =
    StreamProvider.family<List<StudentDevice>, String>((ref, studentId) {
  return FirebaseFirestore.instance
      .collection('devices')
      .where('user_id', isEqualTo: studentId)
      .snapshots()
      .map(
        (snapshot) => <StudentDevice>[
          for (final doc in snapshot.docs)
            StudentDevice(
              id: doc.id,
              model: _deviceModel(doc.data(), doc.id),
            ),
        ],
      );
});

String _deviceModel(Map<String, dynamic> data, String fallbackId) {
  final Object? model = data['device_model'] ?? data['model'];
  if (model is String && model.trim().isNotEmpty) return model.trim();
  return fallbackId;
}

/// Opens the "profile edit" bottom sheet for [userId].
///
/// [onPhotoUpdated]/[onNameUpdated] report persisted changes so the
/// hosting profile screen refreshes its header immediately; the session
/// is additionally invalidated on name change so Student Home follows.
Future<void> showProfileEditSheet(
  BuildContext context, {
    required String userId,
    required String fullName,
    required String phoneNumber,
    required String? photoUrl,
    required Color canvas,
    required ValueChanged<String> onPhotoUpdated,
    required ValueChanged<String> onNameUpdated,
  }) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    barrierColor: const Color(0x40000000),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(context.rs(24)),
        topRight: Radius.circular(context.rs(24)),
      ),
      // Figma dev code: 1px white side stroke on the white panel.
      side: const BorderSide(
        width: 1,
        color: Color(0x59FFFFFF),
      ),
    ),
    builder: (_) => _ProfileEditSheet(
      userId: userId,
      fullName: fullName,
      phoneNumber: phoneNumber,
      photoUrl: photoUrl,
      canvas: canvas,
      onPhotoUpdated: onPhotoUpdated,
      onNameUpdated: onNameUpdated,
    ),
  );
}

class _ProfileEditSheet extends ConsumerStatefulWidget {
  final String userId;
  final String fullName;
  final String phoneNumber;
  final String? photoUrl;
  final Color canvas;
  final ValueChanged<String> onPhotoUpdated;
  final ValueChanged<String> onNameUpdated;

  const _ProfileEditSheet({
    required this.userId,
    required this.fullName,
    required this.phoneNumber,
    required this.photoUrl,
    required this.canvas,
    required this.onPhotoUpdated,
    required this.onNameUpdated,
  });

  @override
  ConsumerState<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends ConsumerState<_ProfileEditSheet> {
  late String _currentName;
  String? _currentPhotoUrl;

  @override
  void initState() {
    super.initState();
    _currentName = widget.fullName;
    _currentPhotoUrl = widget.photoUrl;
  }

  @override
  void didUpdateWidget(covariant _ProfileEditSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullName != widget.fullName) {
      _currentName = widget.fullName;
    }
    if (oldWidget.photoUrl != widget.photoUrl) {
      _currentPhotoUrl = widget.photoUrl;
    }
  }

  Color get _rowFill => widget.canvas.withValues(alpha: 0.15);

  String get userId => widget.userId;

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(studentDevicesProvider(userId));
    // Figma frame is a fixed 393x679 panel (content top-aligned, empty
    // space below) — capped so it stays inside small viewports.
    final sheetHeight = context
        .rsV(679)
        .clamp(0.0, MediaQuery.sizeOf(context).height * 0.92);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: sheetHeight,
          child: SingleChildScrollView(
            // Figma rows are LTR (label left, photo/value right) — pin it
            // instead of inheriting the app's RTL direction.
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  context.rs(24),
                  context.rsV(56),
                  context.rs(24),
                  context.rsV(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Profile picture row (Figma y94, top r28).
                    _EditRow(
                      fill: _rowFill,
                      topRounded: true,
                      onTap: () => _openPictureSheet(context),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Padding(
                            padding: EdgeInsets.all(context.rs(10)),
                            child: Text(
                              'Profile picture',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: context.rsFont(14),
                                fontWeight: FontWeight.w400,
                                height: 1.43,
                              ),
                            ),
                          ),
                          _SheetAvatar(photoUrl: _currentPhotoUrl),
                        ],
                      ),
                    ),
                    SizedBox(height: context.rsV(4)),
                    // Name row (Figma y162) — editable.
                    _EditRow(
                      fill: _rowFill,
                      onTap: () => _openNameDialog(context),
                      child: _InfoText(
                        label: 'Name',
                        value: _currentName,
                        trailingIcon: Icons.edit_outlined,
                      ),
                    ),
                    SizedBox(height: context.rsV(4)),
                    // Phone row (Figma y230) — display only.
                    _EditRow(
                      fill: _rowFill,
                      child: _InfoText(
                        label: 'Phone',
                        value: widget.phoneNumber,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    SizedBox(height: context.rsV(4)),
                    // Devices row (Figma y298) — display only, live data.
                    _EditRow(
                      fill: _rowFill,
                      child: devicesAsync.when(
                        loading: () => const _InfoText(
                          label: 'Devices',
                          value: '…',
                        ),
                        error: (_, _) => const _InfoText(
                          label: 'Devices',
                          value: '—',
                        ),
                        data: (devices) {
                          if (devices.isEmpty) {
                            return const _InfoText(
                              label: 'Devices',
                              value: '—',
                            );
                          }
                          final device = devices.first;
                          return Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _InfoText(
                                label: 'Devices',
                                value: 'Device 01',
                              ),
                              Flexible(
                                child: Text(
                                  device.model,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: context.rsFont(14),
                                    fontWeight: FontWeight.w400,
                                    height: 1.43,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Drag handle (Figma 36x4 #E5E7EB at top center).
              Positioned(
                left: 0,
                right: 0,
                top: context.rsV(12),
                child: Center(
                  child: Container(
                    width: context.rs(36),
                    height: context.rsV(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius:
                          BorderRadius.circular(context.rs(9999)),
                    ),
                  ),
                ),
              ),
              // Close X (Figma 44x44 at top right).
              Positioned(
                right: context.rs(24),
                top: context.rsV(24),
                child: SizedBox(
                  width: context.rs(44),
                  height: context.rs(44),
                  child: IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    ),
    );
  }

  Future<void> _openPictureSheet(BuildContext context) async {
    // Figma "Profile picture edit" overlay (node 58259:2068): fixed 679
    // white panel, back circle, centered title, two 345x54 option rows.
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x40000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(context.rs(24)),
          topRight: Radius.circular(context.rs(24)),
        ),
        side: const BorderSide(
          width: 1,
          color: Color(0x59FFFFFF),
        ),
      ),
      builder: (_) => const _PictureEditPanel(),
    );
    if (source == null) return;
    if (!context.mounted) return;
    // Capture everything that needs this sheet's context BEFORE popping it:
    // after the pop the sheet's context is deactivated, so any
    // `!context.mounted` check after an await would silently drop the
    // upload (the reported "nothing happens" bug). Picking also happens
    // while the sheet is still mounted so web file-picker activation works.
    final container = ProviderScope.containerOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('يرجى تسجيل الدخول أولاً.')),
      );
      return;
    }
    XFile? image;
    try {
      image = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 85,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر اختيار الصورة، حاول مرة أخرى.')),
      );
      return;
    }
    // Picker cancel: keep the edit sheet open, no error, no navigation.
    if (image == null) return;
    Uint8List bytes;
    try {
      bytes = await image.readAsBytes();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر قراءة الصورة، حاول مرة أخرى.')),
      );
      return;
    }
    if (bytes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر قراءة الصورة، حاول مرة أخرى.')),
      );
      return;
    }
    // Close the edit sheet; the upload + outcome snackbar run on the
    // profile screen so progress is visible, not buried. The captured
    // [messenger]/[container] survive the pop.
    if (context.mounted) {
      // ignore: use_build_context_synchronously
      Navigator.of(context).maybePop();
    }
    await _persistPickedPhoto(
      container: container,
      messenger: messenger,
      userId: uid,
      bytes: bytes,
    );
  }

  Future<void> _persistPickedPhoto({
    required ProviderContainer container,
    required ScaffoldMessengerState messenger,
    required String userId,
    required Uint8List bytes,
  }) async {
    try {
      final ProfileRepository repo =
          container.read(profileRepositoryProvider);
      final url = await repo.uploadProfilePhoto(
        userId: userId,
        bytes: bytes,
        fileName: '${DateTime.now().millisecondsSinceEpoch}_avatar.jpg',
      );
      await repo.updateProfilePhotoUrl(userId: userId, url: url);
      if (mounted) {
        setState(() => _currentPhotoUrl = url);
      }
      widget.onPhotoUpdated(url);
      // Session re-resolves from `users/{uid}` so every avatar (profile
      // header AND Student Home) shows the new photo immediately — without
      // this the change looked like nothing happened.
      container.invalidate(sessionProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم تحديث صورة الملف الشخصي.')),
        );
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تعذر رفع الصورة، حاول مرة أخرى.')),
        );
    }
  }

  Future<void> _openNameDialog(BuildContext context) async {
    // Figma "Name edit" overlay (node 58259:2134): fixed 679 white panel
    // with the D0D0D0 field + floating "Full Name" label, the grade
    // Cancel pill and the white Save pill. Saves via Save or keyboard
    // submit; Cancel pops without saving.
    final updated = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x40000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(context.rs(24)),
          topRight: Radius.circular(context.rs(24)),
        ),
        side: const BorderSide(
          width: 1,
          color: Color(0x59FFFFFF),
        ),
      ),
      builder: (_) => _EditNameOverlay(
        initialName: _currentName,
        userId: userId,
        canvas: widget.canvas,
      ),
    );
    if (updated == null || !context.mounted) return;
    // Update this sheet's row instantly so the user sees the new name
    // without closing/reopening the sheet, then notify the profile header.
    if (mounted) {
      setState(() => _currentName = updated);
    }
    widget.onNameUpdated(updated);
    // Session re-resolves from `users/{uid}` so Student Home greets with
    // the new name without a manual reload.
    ProviderScope.containerOf(context).invalidate(sessionProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث الاسم بنجاح.')),
    );
  }
}

/// One 345x64 edit-sheet row (grade-canvas 15% fill, padding h8 v4).
class _EditRow extends StatelessWidget {
  final Color fill;
  final Widget child;
  final bool topRounded;
  final VoidCallback? onTap;

  const _EditRow({
    required this.fill,
    required this.child,
    this.topRounded = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = topRounded
        ? BorderRadius.only(
            topLeft: Radius.circular(context.rs(28)),
            topRight: Radius.circular(context.rs(28)),
          )
        : BorderRadius.zero;
    return Material(
      color: fill,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      child: InkWell(
        borderRadius: borderRadius == BorderRadius.zero
            ? null
            : borderRadius,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: context.rsV(64)),
          padding: EdgeInsets.symmetric(
            horizontal: context.rs(8),
            vertical: context.rsV(4),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Two-line info text (Figma 14 black label + value).
class _InfoText extends StatelessWidget {
  final String label;
  final String value;
  final TextDirection? textDirection;
  final IconData? trailingIcon;

  const _InfoText({
    required this.label,
    required this.value,
    this.textDirection,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      '$label\n$value',
      style: TextStyle(
        color: Colors.black,
        fontSize: context.rsFont(14),
        fontWeight: FontWeight.w400,
        height: 1.43,
      ),
    );
    if (trailingIcon == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: textDirection == null
            ? text
            : Directionality(
                textDirection: textDirection!,
                child: text,
              ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: textDirection == null
              ? text
              : Directionality(
                  textDirection: textDirection!,
                  child: text,
                ),
        ),
        Icon(trailingIcon, color: Colors.black54, size: context.rs(20)),
      ],
    );
  }
}

/// 56x56 sheet avatar (Figma div.avatar: gradient white 28%->4%,
/// 1px white 45% ring, photo cover with person fallback).
class _SheetAvatar extends StatelessWidget {
  final String? photoUrl;

  const _SheetAvatar({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final diameter = context.rs(56);
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        children: [
          Container(
            width: diameter,
            height: diameter,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(0.16, -0.09),
                end: const Alignment(0.84, 1.09),
                colors: [
                  Colors.white.withValues(alpha: 0.28),
                  Colors.white.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(context.rs(28)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x7F000000),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                  spreadRadius: -10,
                ),
              ],
            ),
            child: photoUrl?.isNotEmpty == true
                ? Image.network(
                    photoUrl!,
                    width: diameter,
                    height: diameter,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _SheetAvatarFallback(diameter: diameter),
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                            ? child
                            : _SheetAvatarFallback(diameter: diameter),
                  )
                : _SheetAvatarFallback(diameter: diameter),
          ),
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(context.rs(28)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetAvatarFallback extends StatelessWidget {
  final double diameter;

  const _SheetAvatarFallback({required this.diameter});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.05),
      alignment: Alignment.center,
      child: Icon(
        Icons.person_outline,
        size: diameter * 0.52,
        color: Colors.black.withValues(alpha: 0.4),
      ),
    );
  }
}

/// Figma "Profile picture edit" overlay (node 58259:2068).
/// Fixed 393x679 white panel (capped to the viewport): glass back circle
/// at (24,24), centered 14 title, two 345x54 option rows at y135/y224
/// (white 15% fill, r16, 26 icon + 20 #111827 label). English-only screen.
class _PictureEditPanel extends StatelessWidget {
  const _PictureEditPanel();

  @override
  Widget build(BuildContext context) {
    final sheetHeight = context
        .rsV(679)
        .clamp(0.0, MediaQuery.sizeOf(context).height * 0.92);
    return SafeArea(
      top: false,
      child: SizedBox(
        width: context.rs(393),
        height: sheetHeight,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Drag handle (Figma 179,12 36x4 #E5E7EB r9999).
              Positioned(
                left: context.rs(179),
                top: context.rsV(12),
                child: Container(
                  width: context.rs(36),
                  height: context.rsV(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius:
                        BorderRadius.circular(context.rs(9999)),
                  ),
                ),
              ),
              // Back circle (Figma 24,24 44x44).
              Positioned(
                left: context.rs(24),
                top: context.rsV(24),
                child: _OverlayBackButton(
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              // Title (Figma y24 h44, 14 black centered).
              Positioned(
                top: context.rsV(24),
                left: 0,
                right: 0,
                child: SizedBox(
                  height: context.rsV(44),
                  child: Center(
                    child: Text(
                      'Profile picture',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: context.rsFont(14),
                        fontWeight: FontWeight.w400,
                        height: 1.43,
                      ),
                    ),
                  ),
                ),
              ),
              // Take a photo (Figma 24,135 345x54).
              Positioned(
                left: context.rs(24),
                top: context.rsV(135),
                child: _PictureEditOption(
                  icon: Icons.photo_camera_outlined,
                  label: 'Take a photo',
                  onTap: () =>
                      Navigator.of(context).pop(ImageSource.camera),
                ),
              ),
              // Choose from gallery (Figma 24,224 345x54).
              Positioned(
                left: context.rs(24),
                top: context.rsV(224),
                child: _PictureEditOption(
                  icon: Icons.photo_library_outlined,
                  label: 'Choose from gallery',
                  onTap: () =>
                      Navigator.of(context).pop(ImageSource.gallery),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma overlay back circle (44x44): white 25% fill, 1px black 10%
/// stroke, soft shadow, dark chevron (the white-on-glass canonical back
/// button would be invisible on these white panels).
class _OverlayBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _OverlayBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final size = context.rs(44);
    return Material(
      color: Colors.white.withValues(alpha: 0.25),
      shape: CircleBorder(
        side: BorderSide(
          color: Colors.black.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: const Center(
            child: Padding(
              padding: EdgeInsets.only(right: 2.0),
              child: Icon(
                Icons.chevron_left,
                color: Color(0xFF111827),
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One 345x54 picture option row (Figma white 15% r16, 26 icon +
/// 20 #111827 label centered as a group).
class _PictureEditOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PictureEditOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(context.rs(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(context.rs(16)),
        onTap: onTap,
        child: SizedBox(
          width: context.rs(345),
          height: context.rsV(54),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: context.rs(26),
                color: const Color(0xFF111827),
              ),
              SizedBox(width: context.rs(8)),
              // Flexible so system-large text sizes ellipsize instead of
              // overflowing the fixed 345 row.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFF111827),
                    fontSize: context.rsFont(20),
                    fontWeight: FontWeight.w400,
                    height: 1.30,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma "Name edit" overlay (node 58259:2134).
/// Fixed 393x679 white panel (capped to the viewport): glass back circle,
/// centered 14 title, 369x69 D0D0D0 field at (12,165) with the floating
/// "Full Name" label (no background), centered 20 value text, the grade
/// Cancel pill at (191,285) and the white Save pill beside it. The name
/// persists via Save or keyboard submit; Cancel pops without saving.
/// English-only screen.
///
/// The dialog owns its [TextEditingController] (created in `initState`,
/// disposed in `dispose`): disposing a controller passed in from the
/// caller while the pop transition still holds the TextField crashes
/// with "used after being disposed".
class _EditNameOverlay extends ConsumerStatefulWidget {
  final String initialName;
  final String userId;
  final Color canvas;

  const _EditNameOverlay({
    required this.initialName,
    required this.userId,
    required this.canvas,
  });

  @override
  ConsumerState<_EditNameOverlay> createState() => _EditNameOverlayState();
}

class _EditNameOverlayState extends ConsumerState<_EditNameOverlay> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'يرجى إدخال الاسم.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateFullName(
            userId: widget.userId,
            fullName: name,
          );
      if (!mounted) return;
      Navigator.of(context).pop(name);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyFunctionErrorMessage(
          error,
          'تعذر تحديث الاسم، حاول مرة أخرى.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = context
        .rsV(679)
        .clamp(0.0, MediaQuery.sizeOf(context).height * 0.92);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          width: context.rs(393),
          height: sheetHeight,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Drag handle (Figma 179,12 36x4 #E5E7EB r9999).
                Positioned(
                  left: context.rs(179),
                  top: context.rsV(12),
                  child: Container(
                    width: context.rs(36),
                    height: context.rsV(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius:
                          BorderRadius.circular(context.rs(9999)),
                    ),
                  ),
                ),
                // Back circle (Figma 24,24 44x44) — pops without saving.
                Positioned(
                  left: context.rs(24),
                  top: context.rsV(24),
                  child: _OverlayBackButton(
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                // Title (Figma y24 h44, 14 black centered).
                Positioned(
                  top: context.rsV(24),
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: context.rsV(44),
                    child: Center(
                      child: Text(
                        'Name',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: context.rsFont(14),
                          fontWeight: FontWeight.w400,
                          height: 1.43,
                        ),
                      ),
                    ),
                  ),
                ),
                // Field outer box (Figma 12,165 369x69, white fill like
                // the page, 1px #D0D0D0, r12).
                Positioned(
                  left: context.rs(12),
                  top: context.rsV(165),
                  child: Container(
                    width: context.rs(369),
                    height: context.rsV(69),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(context.rs(12)),
                      border: Border.all(
                        color: const Color(0xFFD0D0D0),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _controller,
                      enabled: !_saving,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _saving ? null : _save(),
                      cursorColor: Colors.black,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: context.rsFont(20),
                        fontWeight: FontWeight.w400,
                        height: 1.30,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: true,
                        fillColor: Colors.white,
                        hoverColor: Colors.white,
                        focusColor: Colors.white,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                ),
                // Floating "Full Name" label (Figma 36,147 134x33) —
                // white like the page so it masks the field border
                // behind it (no grey chip). IgnorePointer so it never
                // blocks taps/focus on the TextField below it.
                Positioned(
                  left: context.rs(36),
                  top: context.rsV(147),
                  child: IgnorePointer(
                    child: Container(
                    width: context.rs(134),
                    height: context.rsV(33),
                    color: Colors.white,
                    alignment: Alignment.center,
                    child: Text(
                      'Full Name',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF9A9A9A),
                        fontSize: context.rsFont(20),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    ),
                  ),
                ),
                // Validation error (no Figma slot — small red line under
                // the field, clear of the Cancel pill at y285).
                if (_error != null)
                  Positioned(
                    top: context.rsV(240),
                    left: 0,
                    right: 0,
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: context.rsFont(13),
                      ),
                    ),
                  ),
                // Cancel pill — secondary (white with canvas text + border
                // so it stays visible on the white sheet).
                Positioned(
                  left: context.rs(191),
                  top: context.rsV(285),
                  child: Material(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(context.rs(28)),
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(context.rs(28)),
                      onTap: _saving
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      child: Container(
                        constraints: BoxConstraints(
                          minWidth: context.rs(77),
                          minHeight: context.rsV(40),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rs(16),
                          vertical: context.rs(10),
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(context.rs(28)),
                          border: Border.all(
                            color: const Color(0xFFD0D0D0),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: widget.canvas,
                            fontSize: context.rsFont(14),
                            fontWeight: FontWeight.w400,
                            height: 1.43,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Save pill — primary (grade-canvas fill + white text).
                // Persists the name via [_save]; shows the spinner while
                // saving.
                Positioned(
                  left: context.rs(268),
                  top: context.rsV(285),
                  child: Material(
                    color: widget.canvas,
                    borderRadius:
                        BorderRadius.circular(context.rs(28)),
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(context.rs(28)),
                      onTap: _saving ? null : _save,
                      child: Container(
                        constraints: BoxConstraints(
                          minWidth: context.rs(77),
                          minHeight: context.rsV(40),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rs(16),
                          vertical: context.rs(10),
                        ),
                        alignment: Alignment.center,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Save',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: context.rsFont(14),
                                  fontWeight: FontWeight.w400,
                                  height: 1.43,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}