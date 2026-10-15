import 'dart:ui';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../providers/profile_providers.dart';

/// "Grade One Student Profile Overview" — 1280x800 landscape canvas.
///
/// Figma-faithful implementation:
/// - Base background #F59E0B, text primary #111827.
/// - Glass surface rgba(0,0,0,0.12) + BackdropFilter blur.
/// - Absolute Stack positioning per spec coordinates.
/// - Inline Edit/Done for Name & Phone, showDialog overlays for
///   Grade & Student Type (fade 150ms, barrier black 25%).
///
/// Loads the REAL student from `users/{studentId}` through
/// [studentProfileProvider]. Displayed name/phone/grade/student-type are
/// reflections of the loaded [AuthUser] — never local source of truth.
class GradeOneProfileOverviewScreen extends ConsumerStatefulWidget {
  final String studentId;

  const GradeOneProfileOverviewScreen({required this.studentId, super.key});

  /// Display-only mapping: canonical `users.grade` key → overview label.
  ///
  /// Never used for writes; the authoritative value stays `AuthUser.grade`.
  static String gradeLabelForKey(String? gradeKey) {
    final normalized = (gradeKey ?? '').trim().toLowerCase();
    const aliases = <String, String>{
      'grade_one': 'Grade One',
      'grade_1': 'Grade One',
      'grade 1': 'Grade One',
      '1': 'Grade One',
      'grade_two': 'Grade Two',
      'grade_2': 'Grade Two',
      'grade 2': 'Grade Two',
      '2': 'Grade Two',
      'grade_three': 'Grade Three',
      'grade_3': 'Grade Three',
      'grade 3': 'Grade Three',
      '3': 'Grade Three',
      'grade_four': 'Grade Four',
      'grade_4': 'Grade Four',
      'grade 4': 'Grade Four',
      '4': 'Grade Four',
    };
    return aliases[normalized] ?? 'Grade One';
  }

  /// Write-path mapping: overview label → canonical `users.grade` key.
  ///
  /// Only canonical keys are ever sent to the backend; a UI label such as
  /// "Grade Two" must never cross the repository boundary. Returns null
  /// for unrecognized labels (caller treats this as invalid input).
  static String? canonicalGradeForLabel(String? gradeLabel) {
    final normalized = (gradeLabel ?? '').trim().toLowerCase();
    const aliases = <String, String>{
      'grade one': 'grade_one',
      'grade_one': 'grade_one',
      'grade_1': 'grade_one',
      'grade 1': 'grade_one',
      '1': 'grade_one',
      'grade two': 'grade_two',
      'grade_two': 'grade_two',
      'grade_2': 'grade_two',
      'grade 2': 'grade_two',
      '2': 'grade_two',
      'grade three': 'grade_three',
      'grade_three': 'grade_three',
      'grade_3': 'grade_three',
      'grade 3': 'grade_three',
      '3': 'grade_three',
      'grade four': 'grade_four',
      'grade_four': 'grade_four',
      'grade_4': 'grade_four',
      'grade 4': 'grade_four',
      '4': 'grade_four',
    };
    return aliases[normalized];
  }

  /// Pure same-grade check: true when [selectedLabel] already matches the
  /// loaded canonical [currentGradeKey], so the caller can skip the
  /// backend (no audit event for a no-op).
  static bool isGradeUnchanged({
    required String? currentGradeKey,
    required String selectedLabel,
  }) {
    final currentLabel = gradeLabelForKey(currentGradeKey);
    return currentLabel.trim().toLowerCase() ==
        selectedLabel.trim().toLowerCase();
  }

  /// Display-only mapping for the backend `student_type` value.
  static String studentTypeLabelForKey(String? studentTypeKey) {
    final normalized = (studentTypeKey ?? '').trim().toLowerCase();
    if (normalized == 'guest') return 'Guest';
    return 'Center';
  }

  @override
  ConsumerState<GradeOneProfileOverviewScreen> createState() =>
      _GradeOneProfileOverviewScreenState();
}

class _GradeOneProfileOverviewScreenState
    extends ConsumerState<GradeOneProfileOverviewScreen>
    with SingleTickerProviderStateMixin {
  // ---- Design tokens (Grade One / Yellow) ----
  static const Color bgColor = AppColors.grade1Canvas; // #F59E0B
  static const Color textPrimary = AppColors.grade1TextPrimary; // #111827
  static const Color avatarGray = AppColors.mediumGray; // #6B7280
  static const Color glassFill = Color(0x1F000000); // black 12%
  static const Color glassBorderIdle = Color(0x33000000); // black 20%
  static const Color overlayBarrier = Color(0x40000000); // black 25%

  /// Solid dark used for buttons sitting directly on the amber canvas.
  /// Spec asks for solid #F59E0B buttons, which is invisible on a #F59E0B
  /// canvas, so we use the near-black primary for contrast (the spec's own
  /// "or darker amber for contrast" allowance).
  static const Color canvasButtonFill = textPrimary;

  static const List<String> grades = [
    'Grade One',
    'Grade Two',
    'Grade Three',
    'Grade Four',
  ];
  static const List<String> studentTypes = ['Center', 'Guest'];
  static const List<String> navItems = [
    'Overview',
    'Subjects',
    'Memberships',
    'Payments',
    'Device',
    'Security',
    'Activity',
  ];

  bool menuOpen = false;
  late final AnimationController _menuController;

  bool isEditingName = false;
  bool isEditingPhone = false;

  late TextEditingController nameController;
  late TextEditingController phoneController;
  late FocusNode nameFocus;
  late FocusNode phoneFocus;

  String selectedGrade = 'Grade One';
  String selectedStudentType = 'Center';
  String activeGradeTab = 'Grade One';
  String activeSubTab = 'Students';

  /// Last [AuthUser] snapshot the controllers/display state were seeded
  /// from. Reseeds only when the loaded profile actually changes, so
  /// unrelated rebuilds never clobber in-progress local edits.
  AuthUser? _seededUser;

  void _seedFromProfile(AuthUser user) {
    final prev = _seededUser;
    if (prev != null &&
        prev.id == user.id &&
        prev.fullName == user.fullName &&
        prev.phoneNumber == user.phoneNumber &&
        prev.grade == user.grade &&
        prev.studentType == user.studentType) {
      return;
    }
    _seededUser = user;
    nameController.text = user.fullName;
    phoneController.text = user.phoneNumber;
    selectedGrade =
        GradeOneProfileOverviewScreen.gradeLabelForKey(user.grade);
    selectedStudentType =
        GradeOneProfileOverviewScreen.studentTypeLabelForKey(
            user.studentType);
    activeGradeTab = selectedGrade;
  }

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    phoneController = TextEditingController();
    nameFocus = FocusNode();
    phoneFocus = FocusNode();
    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    _menuController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() => menuOpen = !menuOpen);
    if (menuOpen) {
      _menuController.forward();
    } else {
      _menuController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(studentProfileProvider(widget.studentId));
    return profile.when(
      loading: () => const Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const Scaffold(
        backgroundColor: bgColor,
        body: Center(child: Text('تعذر تحميل ملف الطالب.')),
      ),
      data: (user) {
        _seedFromProfile(user);
        return _buildLoaded();
      },
    );
  }

  Widget _buildLoaded() {
    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: Container(
              width: 1280,
              height: 800,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(color: bgColor),
              child: Stack(
                children: [
                  // Menu icon — X:80 Y:24, 80x80.
                  Positioned(
                    left: 80,
                    top: 24,
                    child: _buildMenuIcon(),
                  ),
                  // App title — X:370 Y:24, 540x80.
                  Positioned(
                    left: 370,
                    top: 24,
                    child: _buildAppTitle(),
                  ),
                  // Sidebar — X:80 Y:132 (below header).
                  Positioned(
                    left: 80,
                    top: 132,
                    child: _buildSidebar(),
                  ),
                  // Main content — X:370 Y:132.
                  Positioned(
                    left: 370,
                    top: 132,
                    child: _buildMainContent(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- A. Header ----------

  Widget _buildAppTitle() {
    return SizedBox(
      width: 540,
      height: 80,
      child: Center(
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              fontFamily: AppFontFamilies.googleSansFlex,
              fontSize: 48,
              height: 1.0,
              color: textPrimary,
            ),
            children: [
              TextSpan(
                text: 'Tarek el araby ',
                style: TextStyle(fontWeight: FontWeight.w400),
              ),
              TextSpan(
                text: 'Platform',
                style: TextStyle(
                  fontWeight: FontWeight.w100,
                  fontVariations: [FontVariation('wght', 100)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 80x80 hit-area; two 80x1 lines morph into an X via AnimatedBuilder.
  Widget _buildMenuIcon() {
    return InkWell(
      onTap: _toggleMenu,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 80,
        height: 80,
        child: AnimatedBuilder(
          animation: _menuController,
          builder: (context, _) {
            final t = _menuController.value;
            // Lines rotate ±45° and converge to center as t → 1.
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  offset: Offset(0, -5 * (1 - t)),
                  child: Transform.rotate(
                    angle: t * 0.7853982, // 45°
                    child: Container(
                      width: 80,
                      height: 1,
                      color: textPrimary,
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, 5 * (1 - t)),
                  child: Transform.rotate(
                    angle: -t * 0.7853982,
                    child: Container(
                      width: 80,
                      height: 1,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------- B. Left sidebar ----------

  Widget _buildSidebar() {
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar — 250x250 container, gray head/body vectors.
          Container(
            width: 250,
            height: 250,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white24,
            ),
            child: const Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 40,
                  child: _AvatarHead(),
                ),
                Positioned(
                  bottom: 20,
                  child: _AvatarBody(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Nav menu — width 250, hug height, gap 8.
          SizedBox(
            width: 250,
            child: Column(
              children: [
                for (final item in navItems)
                  _buildNavBtn(item, isActive: item == 'Overview'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBtn(String title, {bool isActive = false}) {
    return Container(
      width: 250,
      height: 48,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive ? canvasButtonFill : Colors.transparent,
        borderRadius: BorderRadius.circular(9999),
        border: isActive
            ? null
            : Border.all(color: bgColor, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        title,
        style: TextStyle(
          fontFamily: AppFontFamilies.googleSansFlex,
          fontSize: 20,
          fontWeight: FontWeight.w400,
          color: isActive ? bgColor : textPrimary,
        ),
      ),
    );
  }

  // ---------- C. Main content ----------

  Widget _buildMainContent() {
    return SizedBox(
      width: 814,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Top tabs — 660x40, gap 4.
          SizedBox(
            width: 660,
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < grades.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  // READ-ONLY reflection of the persisted AuthUser.grade:
                  // tapping a tab must never mutate activeGradeTab. The
                  // Grade Edit dialog is the only grade-change mechanism.
                  _buildTopTab(
                    grades[i],
                    isActive: activeGradeTab == grades[i],
                    onTap: null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Sub-tabs: Students (active, underlined) & Subjects.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                onTap: () => setState(() => activeSubTab = 'Students'),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    border: activeSubTab == 'Students'
                        ? const Border(
                            bottom: BorderSide(
                                color: textPrimary, width: 2))
                        : null,
                  ),
                  child: const Text(
                    'Students',
                    style: TextStyle(
                      fontFamily: AppFontFamilies.googleSansFlex,
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      color: textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 36),
              InkWell(
                onTap: () => setState(() => activeSubTab = 'Subjects'),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    border: activeSubTab == 'Subjects'
                        ? const Border(
                            bottom: BorderSide(
                                color: textPrimary, width: 2))
                        : null,
                  ),
                  child: Text(
                    'Subjects',
                    style: TextStyle(
                      fontFamily: AppFontFamilies.googleSansFlex,
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      color: activeSubTab == 'Subjects'
                          ? textPrimary
                          : textPrimary.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),
          // Data rows — 814x272 total, gap 16.
          SizedBox(
            width: 814,
            child: Column(
              children: [
                _buildTextRow(
                  'Name',
                  controller: nameController,
                  focusNode: nameFocus,
                  isEditing: isEditingName,
                  onToggle: () {
                    setState(() => isEditingName = !isEditingName);
                    if (isEditingName) {
                      FocusScope.of(context).requestFocus(nameFocus);
                    } else {
                      nameFocus.unfocus();
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildTextRow(
                  'Phone',
                  controller: phoneController,
                  focusNode: phoneFocus,
                  isEditing: isEditingPhone,
                  keyboardType: TextInputType.phone,
                  onToggle: () {
                    setState(() => isEditingPhone = !isEditingPhone);
                    if (isEditingPhone) {
                      FocusScope.of(context).requestFocus(phoneFocus);
                    } else {
                      phoneFocus.unfocus();
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildDropdownRow(
                  'Grade',
                  selectedGrade,
                  onEdit: _showGradesOverlay,
                ),
                const SizedBox(height: 16),
                _buildDropdownRow(
                  'Student type',
                  selectedStudentType,
                  onEdit: _showStudentTypeOverlay,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTab(String text,
      {bool isActive = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 160,
        height: 32,
        decoration: BoxDecoration(
          color: isActive ? canvasButtonFill : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: AppFontFamilies.googleSansFlex,
            fontSize: 24,
            fontWeight: FontWeight.w400,
            color: isActive ? bgColor : textPrimary,
          ),
        ),
      ),
    );
  }

  // ---------- Data rows ----------

  Widget _buildTextRow(
    String label, {
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isEditing,
    required VoidCallback onToggle,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return SizedBox(
      width: 814,
      height: 56,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppFontFamilies.googleSansFlex,
                fontSize: 28,
                fontWeight: FontWeight.w400,
                color: textPrimary,
              ),
            ),
          ),
          _buildGlassField(
            width: 407,
            height: 50,
            isEditing: isEditing,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: isEditing,
              keyboardType: keyboardType,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppFontFamilies.googleSansFlex,
                fontSize: 20,
                fontWeight: FontWeight.w400,
                color: textPrimary,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          _buildActionButton(isEditing ? 'Done' : 'Edit', onToggle),
        ],
      ),
    );
  }

  Widget _buildDropdownRow(String label, String value, {required VoidCallback onEdit}) {
    return SizedBox(
      width: 814,
      height: 56,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppFontFamilies.googleSansFlex,
                fontSize: 28,
                fontWeight: FontWeight.w400,
                color: textPrimary,
              ),
            ),
          ),
          _buildGlassField(
            width: 407,
            height: 50,
            child: Center(
              child: Text(
                value,
                style: const TextStyle(
                  fontFamily: AppFontFamilies.googleSansFlex,
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  color: textPrimary,
                ),
              ),
            ),
          ),
          _buildActionButton('Edit', onEdit),
        ],
      ),
    );
  }

  Widget _buildGlassField({
    required double width,
    required double height,
    required Widget child,
    bool isEditing = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: glassFill,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: isEditing ? textPrimary : glassBorderIdle,
              width: isEditing ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  Widget _buildActionButton(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9999),
      child: Container(
        width: 144,
        height: 48,
        decoration: BoxDecoration(
          color: canvasButtonFill,
          borderRadius: BorderRadius.circular(9999),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: AppFontFamilies.googleSansFlex,
            fontSize: 20,
            fontWeight: FontWeight.w400,
            color: bgColor,
          ),
        ),
      ),
    );
  }

  // ---------- Overlays ----------

  void _showGradesOverlay() {
    String temp = selectedGrade;
    bool saving = false;
    showGeneralDialog<void>(
      context: context,
      barrierColor: overlayBarrier,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (context, animation, _, child) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(opacity: fade, child: child);
      },
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setOverlayState) => Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 677,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Grades',
                      style: TextStyle(
                        fontFamily: AppFontFamilies.googleSansFlex,
                        fontSize: 32,
                        fontWeight: FontWeight.w400,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 660,
                      height: 40,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0; i < grades.length; i++) ...[
                            if (i > 0) const SizedBox(width: 4),
                            _buildOverlayOption(
                              grades[i],
                              isActive: temp == grades[i],
                              onTap: saving
                                  ? null
                                  : () => setOverlayState(
                                      () => temp = grades[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSaveButton(
                      saving
                          ? null
                          : () async {
                              // Capture dialog navigator + screen messenger
                              // before any async gap (lint:
                              // use_build_context_synchronously).
                              final navigator = Navigator.of(context);
                              final messenger =
                                  ScaffoldMessenger.of(this.context);
                              final currentGradeKey = ref
                                  .read(studentProfileProvider(
                                      widget.studentId))
                                  .value
                                  ?.grade;
                              if (GradeOneProfileOverviewScreen
                                  .isGradeUnchanged(
                                currentGradeKey: currentGradeKey,
                                selectedLabel: temp,
                              )) {
                                // No-op: matches backend behavior
                                // (no write, no audit event).
                                navigator.pop();
                                return;
                              }
                              final canonical =
                                  GradeOneProfileOverviewScreen
                                      .canonicalGradeForLabel(temp);
                              if (canonical == null) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'تحقق من البيانات المدخلة ثم أعد المحاولة.'),
                                  ),
                                );
                                return;
                              }
                              setOverlayState(() => saving = true);
                              try {
                                await ref
                                    .read(
                                        updateStudentGradeUseCaseProvider)
                                    .execute(
                                      studentId: widget.studentId,
                                      grade: canonical,
                                    );
                              } on FirebaseFunctionsException catch (error) {
                                // Server authorization is authoritative
                                // (e.g. Admin without admin_students →
                                // permission-denied). Never expose raw
                                // backend details to the user.
                                if (mounted) {
                                  setOverlayState(() => saving = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        friendlyFunctionErrorMessage(
                                          error,
                                          'تعذر حفظ الفرقة، حاول مرة أخرى.',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return;
                              } catch (_) {
                                if (mounted) {
                                  setOverlayState(() => saving = false);
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'تعذر حفظ الفرقة، حاول مرة أخرى.'),
                                    ),
                                  );
                                }
                                return;
                              }
                              if (!mounted) return;
                              navigator.pop();
                              // Reload the authoritative profile: the
                              // reseeded AuthUser.grade drives
                              // selectedGrade/activeGradeTab — no
                              // optimistic local mutation.
                              ref.invalidate(studentProfileProvider(
                                  widget.studentId));
                            },
                      isLoading: saving,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- Overlays ----------

  void _showStudentTypeOverlay() {
    String temp = selectedStudentType;
    showGeneralDialog<void>(
      context: context,
      barrierColor: overlayBarrier,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (context, animation, _, child) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(opacity: fade, child: child);
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setOverlayState) => Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 380,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Student Type',
                      style: TextStyle(
                        fontFamily: AppFontFamilies.googleSansFlex,
                        fontSize: 32,
                        fontWeight: FontWeight.w400,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 332,
                      height: 40,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0;
                              i < studentTypes.length;
                              i++) ...[
                            if (i > 0) const SizedBox(width: 4),
                            _buildOverlayOption(
                              studentTypes[i],
                              isActive: temp == studentTypes[i],
                              onTap: () => setOverlayState(
                                  () => temp = studentTypes[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSaveButton(() {
                      setState(() => selectedStudentType = temp);
                      Navigator.pop(context);
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Overlay option — 160x32, radius 28. Active: amber fill + white text
  /// (visible because the overlay card itself is white).
  Widget _buildOverlayOption(String text,
      {required bool isActive, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 160,
        height: 32,
        decoration: BoxDecoration(
          color: isActive ? bgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: AppFontFamilies.googleSansFlex,
            fontSize: 24,
            fontWeight: FontWeight.w400,
            color: isActive ? Colors.white : textPrimary,
          ),
        ),
      ),
    );
  }

  /// Save — 160x40, radius 28, amber fill.
  ///
  /// Same geometry/typography as the Figma spec; [isLoading] swaps the
  /// label for a spinner and [onTap] null disables the button while the
  /// grade save is in flight.
  Widget _buildSaveButton(VoidCallback? onTap, {bool isLoading = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 160,
        height: 40,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(28),
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Save',
                style: TextStyle(
                  fontFamily: AppFontFamilies.googleSansFlex,
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

class _AvatarHead extends StatelessWidget {
  const _AvatarHead();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 93.75,
      height: 93.75,
      decoration: const BoxDecoration(
        color: _GradeOneProfileOverviewScreenState.avatarGray,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _AvatarBody extends StatelessWidget {
  const _AvatarBody();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 166.67,
      height: 67.71,
      decoration: BoxDecoration(
        color: _GradeOneProfileOverviewScreenState.avatarGray,
        borderRadius: BorderRadius.circular(100),
      ),
    );
  }
}
