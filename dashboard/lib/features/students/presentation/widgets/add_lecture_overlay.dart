import 'dart:typed_data';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../applications/domain/grade.dart';
import '../../../applications/presentation/providers/application_decision_provider.dart';
import '../providers/lecture_access_providers.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../authentication/domain/entities/dashboard_session.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/lecture_access.dart';
import '../providers/subject_details_provider.dart';

class AddLectureOverlay extends ConsumerStatefulWidget {
  final String subjectId;
  final String gradeKey;
  final SubjectContentTab tab;
  final int initialOrder;
  final Color gradeColor;
  final VoidCallback? onClose;
  final VoidCallback? onSave;

  const AddLectureOverlay({
    super.key,
    required this.subjectId,
    required this.gradeKey,
    required this.tab,
    required this.initialOrder,
    required this.gradeColor,
    this.onClose,
    this.onSave,
  });

  static Future<void> show(
    BuildContext context, {
    required String subjectId,
    required String gradeKey,
    required SubjectContentTab tab,
    required int initialOrder,
    required Color gradeColor,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (BuildContext context) => AddLectureOverlay(
        subjectId: subjectId,
        gradeKey: gradeKey,
        tab: tab,
        initialOrder: initialOrder,
        gradeColor: gradeColor,
      ),
    );
  }

  @override
  ConsumerState<AddLectureOverlay> createState() => _AddLectureOverlayState();
}

/// Identifies one of the three cascading dropdowns in the dialog, so
/// each can track its own open state (chevron rotation) and anchor box.
enum _DropdownKind { grade, subject, section }

class _AddLectureOverlayState extends ConsumerState<AddLectureOverlay> {
  late final TextEditingController _nameController;
  late final TextEditingController _orderController;
  late final TextEditingController _minutesController;

  late final FocusNode _nameFocus;
  late final FocusNode _orderFocus;

  /// Cascading accounting catalog (Figma quick-upload spec): grade -> subjects.
  static const Map<String, List<String>> gradeSubjects = {
    'الفرقة الأولى': ['محاسبة مالية'],
    'الفرقة الثانية': ['شركات الأشخاص', 'محاسبة تكاليف 2', 'محاسبة متوسطة'],
    'الفرقة الثالثة': ['مشاكل محاسبية', 'محاسبة تكاليف', 'محاسبة حكومية وقومية'],
    'الفرقة الرابعة': [
      'مالية متقدمة',
      'التحليل المحاسبي',
      'محاسبة ضريبية',
      'محاسبة التكاليف الفعلية',
      'نظم المعلومات',
      'مراجعة الحسابات'
    ],
  };

  static const List<String> sectionOptions = [
    'Lecture',
    'Revision',
    'Final',
    'Online',
  ];

  String? selectedGrade;
  String? selectedSubject;
  List<String> availableSubjects = const [];
  String? selectedSection;

  /// Per-dropdown open state driving the AnimatedRotation chevron
  /// (^ when open, v when closed).
  bool isGradeOpen = false;
  bool isSubjectOpen = false;
  bool isSectionOpen = false;

  /// Currently visible custom dropdown menu (at most one at a time).
  OverlayEntry? _menuOverlay;
  _DropdownKind? _openKind;

  /// Anchor boxes used to position each dropdown menu directly
  /// underneath its field.
  final GlobalKey _gradeBoxKey = GlobalKey();
  final GlobalKey _subjectBoxKey = GlobalKey();
  final GlobalKey _sectionBoxKey = GlobalKey();

  bool _guestAccess = true;

  /// Working selection (Figma selectors). Initialized from the entry
  /// context (subject details page or home quick-add picker).
  late String _gradeKey;
  late String _subjectId;
  late SubjectContentTab _tab;

  /// Staged lecture-access overrides returned from Configure Access.
  /// The lecture does not exist yet in the Quick Add flow, so the
  /// dialog cannot persist them directly — they are held here for the
  /// lecture-creation batch (`createLectureFull` `accessByStudent`).
  Map<String, bool> _accessByStudent = <String, bool>{};

  /// Empty by default: scheduled publishing requires an explicit date.
  DateTime? _publishDate;
  TimeOfDay? _publishTime;

  bool _saving = false;
  String? _formError;

  /// Staged lecture resources for this dialog session. Starts empty;
  /// entries are appended as the user saves them via the
  /// "+ Add Resource" sub-dialogs (no backend involved until Save).
  final List<Map<String, String>> _resources = [];

  @override
  void initState() {
    super.initState();
    _gradeKey = widget.gradeKey;
    _subjectId = widget.subjectId;
    _tab = widget.tab;
    // Bridge entry context into the static catalog selections.
    final String displayGrade = gradeDisplayName(widget.gradeKey);
    if (gradeSubjects.containsKey(displayGrade)) {
      selectedGrade = displayGrade;
      availableSubjects = gradeSubjects[displayGrade]!;
    } else {
      selectedGrade = null;
      availableSubjects = const [];
    }
    selectedSection = null;
    _nameController = TextEditingController();
    _orderController = TextEditingController();
    _minutesController = TextEditingController();

    _nameFocus = FocusNode();
    _orderFocus = FocusNode();
    // Entry-context flows (Subject Details) arrive with a backend
    // subject id but no catalog pick: resolve its display title once
    // the grade subjects stream has data so the dropdown reflects it.
    if (widget.subjectId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolveCatalogSubject();
      });
    }
  }

  /// Best-effort bridge from the backend [_subjectId] to a static
  /// catalog title, keeping the dropdown in sync for entry-context
  /// flows. Prefers an exact id match, then a catalog title match.
  void _resolveCatalogSubject() {
    if (!mounted || selectedSubject != null) return;
    try {
      final List<SubjectOption> options =
          ref.read(gradeSubjectsProvider(_gradeKey)).value ??
              const <SubjectOption>[];
      SubjectOption? match;
      for (final SubjectOption s in options) {
        if (s.id == _subjectId) {
          match = s;
          break;
        }
      }
      if (match == null) return;
      // Only adopt titles present in the catalog options so the
      // dropdown display stays consistent with its menu items.
      for (final String t in availableSubjects) {
        if (t.trim() == match.title.trim()) {
          setState(() => selectedSubject = t);
          return;
        }
      }
    } catch (_) {
      // Offline-safe: keep the entry-context subject id as-is.
    }
  }

  static SubjectContentTab _tabForSection(String section) {
    switch (section) {
      case 'Revision':
        return SubjectContentTab.revisions;
      case 'Final':
        return SubjectContentTab.finalTab;
      case 'Online':
        return SubjectContentTab.online;
      case 'Lecture':
      default:
        return SubjectContentTab.lectures;
    }
  }

  /// Grade change from the static catalog: refresh subjects, reset the
  /// subject and section picks, and keep the backend working state in sync.
  void _handleStaticGradeChanged(String? grade) {
    setState(() {
      selectedGrade = grade;
      availableSubjects = grade == null ? const [] : (gradeSubjects[grade] ?? const []);
      selectedSubject = null;
      selectedSection = null;
      _subjectId = '';
      final String? mapped = grade == null ? null : normalizeGradeKey(grade);
      if (mapped != null) _gradeKey = mapped;
      _tab = SubjectContentTab.lectures;
    });
  }

  /// Subject change from the static catalog: resolve the backend
  /// subject id by title match when available, then recompute order.
  Future<void> _handleStaticSubjectChanged(String? subjectTitle) async {
    setState(() => selectedSubject = subjectTitle);
    if (subjectTitle == null) {
      setState(() => _subjectId = '');
      return;
    }
    String resolvedId = '';
    try {
      final List<SubjectOption> options =
          ref.read(gradeSubjectsProvider(_gradeKey)).value ?? const <SubjectOption>[];
      for (final SubjectOption s in options) {
        if (s.title.trim() == subjectTitle.trim()) {
          resolvedId = s.id;
          break;
        }
      }
      // Fallback: loose contains-match for titles with prefixes.
      if (resolvedId.isEmpty) {
        for (final SubjectOption s in options) {
          if (s.title.contains(subjectTitle) || subjectTitle.contains(s.title)) {
            resolvedId = s.id;
            break;
          }
        }
      }
    } catch (_) {
      // Offline-safe: keep the display selection, backend id stays empty.
    }
    setState(() => _subjectId = resolvedId);
    if (resolvedId.isNotEmpty) {
      await _handleSubjectChanged(resolvedId);
      // _handleSubjectChanged triggers its own setState; restore display pick.
      setState(() => selectedSubject = subjectTitle);
    }
  }

  Future<void> _handleStaticSectionChanged(String? section) async {
    if (section == null) return;
    setState(() => selectedSection = section);
    await _handleTabChanged(_tabForSection(section));
  }

  bool _isKindOpen(_DropdownKind kind) {
    switch (kind) {
      case _DropdownKind.grade:
        return isGradeOpen;
      case _DropdownKind.subject:
        return isSubjectOpen;
      case _DropdownKind.section:
        return isSectionOpen;
    }
  }

  void _setKindOpen(_DropdownKind kind, bool open) {
    switch (kind) {
      case _DropdownKind.grade:
        isGradeOpen = open;
        break;
      case _DropdownKind.subject:
        isSubjectOpen = open;
        break;
      case _DropdownKind.section:
        isSectionOpen = open;
        break;
    }
  }

  ValueChanged<String?> _onSelectedFor(_DropdownKind kind) {
    switch (kind) {
      case _DropdownKind.grade:
        return _handleStaticGradeChanged;
      case _DropdownKind.subject:
        return (String? v) {
          _handleStaticSubjectChanged(v);
        };
      case _DropdownKind.section:
        return (String? v) {
          _handleStaticSectionChanged(v);
        };
    }
  }

  GlobalKey _boxKeyFor(_DropdownKind kind) {
    switch (kind) {
      case _DropdownKind.grade:
        return _gradeBoxKey;
      case _DropdownKind.subject:
        return _subjectBoxKey;
      case _DropdownKind.section:
        return _sectionBoxKey;
    }
  }

  String? _valueFor(_DropdownKind kind) {
    switch (kind) {
      case _DropdownKind.grade:
        return selectedGrade;
      case _DropdownKind.subject:
        return selectedSubject;
      case _DropdownKind.section:
        return selectedSection;
    }
  }

  /// Toggles the custom dropdown menu for [kind]. The menu is anchored
  /// directly underneath the field box, pure white, exactly 360px wide.
  void _toggleDropdown(_DropdownKind kind, List<String> options) {
    if (_openKind == kind) {
      _closeDropdown();
      return;
    }
    _closeDropdown();
    if (options.isEmpty) return;
    final BuildContext? boxContext = _boxKeyFor(kind).currentContext;
    if (boxContext == null) return;
    final RenderBox box = boxContext.findRenderObject()! as RenderBox;
    final Offset origin = box.localToGlobal(Offset.zero);
    final Size screen = MediaQuery.of(context).size;
    const double menuWidth = 360;
    double left = origin.dx;
    final double maxLeft = screen.width - menuWidth - 8;
    if (left > maxLeft) left = maxLeft < 8 ? 8 : maxLeft;
    final double top = origin.dy + box.size.height + 8;
    final double spaceBelow = screen.height - top - 16;
    final double maxMenuHeight =
        spaceBelow.clamp(120.0, 300.0).toDouble();
    _openKind = kind;
    setState(() => _setKindOpen(kind, true));
    final ValueChanged<String?> onSelected = _onSelectedFor(kind);
    final String? current = _valueFor(kind);
    _menuOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeDropdown,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: Material(
              color: Colors.white,
              elevation: 4,
              shadowColor: const Color(0x20000000),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: menuWidth,
                  maxWidth: menuWidth,
                  maxHeight: maxMenuHeight,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final String option in options)
                        _menuItem(option, current, onSelected),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_menuOverlay!);
  }

  Widget _menuItem(String option, String? current,
      ValueChanged<String?> onSelected) {
    final bool selected = option == current;
    return InkWell(
      onTap: () {
        _closeDropdown();
        onSelected(option);
      },
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFF5F5F5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          option,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Google Sans Flex',
            fontSize: 14,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  void _closeDropdown() {
    if (_menuOverlay == null) return;
    _menuOverlay!.remove();
    _menuOverlay = null;
    _openKind = null;
    setState(() {
      isGradeOpen = false;
      isSubjectOpen = false;
      isSectionOpen = false;
    });
  }

  @override
  void dispose() {
    _menuOverlay?.remove();
    _menuOverlay = null;
    _nameController.dispose();
    _orderController.dispose();
    _minutesController.dispose();
    _nameFocus.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  // Pick Date. Cancel (null) preserves the previous value; picking a
  // date switches off Publish Now (mutually exclusive modes).
  Future<void> _handlePickDate() async {
    final picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (ctx) => const _CustomCalendarDialog(),
    );
    if (picked != null && mounted) {
      setState(() => _publishDate = picked);
    }
  }

  // Pick Time. Cancel (null) preserves the previous value.
  Future<void> _handlePickTime() async {
    final picked = await showDialog<TimeOfDay>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (ctx) => _CustomTimePickerWheelsDialog(
        initial: _publishTime,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _publishTime = picked);
    }
  }

  static String formatPublishDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  static String formatPublishTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  // Click '+ Add Resource': opens selector, and selecting immediately opens target overlay
  Future<void> _handleAddResource() async {
    final selectedType = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (ctx) => const _SelectResourceDialog(),
    );

    if (selectedType == null || !mounted) return;

    Map<String, String>? newResourceData;

    if (selectedType == 'Video') {
      newResourceData = await showDialog<Map<String, String>>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.25),
        builder: (ctx) => const _AddVideoDialog(),
      );
    } else if (selectedType == 'PDF') {
      newResourceData = await showDialog<Map<String, String>>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.25),
        builder: (ctx) => const _AddPdfDialog(),
      );
    } else if (selectedType == 'Attachment') {
      newResourceData = await showDialog<Map<String, String>>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.25),
        builder: (ctx) => const _AddAttachmentDialog(),
      );
    } else if (selectedType == 'External Link') {
      newResourceData = await showDialog<Map<String, String>>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.25),
        builder: (ctx) => const _AddExternalLinkDialog(),
      );
    }

    if (newResourceData != null && mounted) {
      setState(() {
        final orderStr = newResourceData!['order']?.isNotEmpty == true
            ? newResourceData['order']!
            : (_resources.length + 1).toString().padLeft(2, '0');

        _resources.add({
          'no': '$orderStr.',
          'title': newResourceData['title']!,
          'type': selectedType,
        });
      });
    }
  }

  Future<void> _handleConfigureAccess() async {
    final Map<String, bool>? overrides =
        await showDialog<Map<String, bool>>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (ctx) => _ConfigureAccessDialog(
        subjectId: _subjectId,
        initialOverrides: _accessByStudent,
      ),
    );
    // Null = Cancel/X: discard everything staged in the dialog session.
    if (overrides != null && mounted) {
      setState(() => _accessByStudent = overrides);
    }
  }

  /// Subject change: recompute the prefilled display order for the
  /// working subject + tab.
  Future<void> _handleSubjectChanged(String subjectId) async {
    setState(() => _subjectId = subjectId);
    try {
      final int order = await ref
          .read(subjectDetailsControllerProvider)
          .nextLectureOrder(subjectId: subjectId, tab: _tab);
      if (!mounted) return;
      setState(() {
        _orderController.text = order.toString().padLeft(2, '0');
      });
    } catch (_) {
      // Keep the current order field on failure (offline-safe default).
    }
  }

  /// Section change from the Figma selector: recompute the prefilled
  /// display order for the working subject + tab.
  Future<void> _handleTabChanged(SubjectContentTab tab) async {
    setState(() => _tab = tab);
    if (_subjectId.isEmpty) return;
    try {
      final int order = await ref
          .read(subjectDetailsControllerProvider)
          .nextLectureOrder(subjectId: _subjectId, tab: tab);
      if (!mounted) return;
      setState(() {
        _orderController.text = order.toString().padLeft(2, '0');
      });
    } catch (_) {
      // Keep the current order field on failure (offline-safe default).
    }
  }

  /// Shared field validation for every commit path. Returns the parsed
  /// values, or sets [_formError] and returns null.
  ({String title, int order, int? minutes})? _validateCommon() {
    // Entry-context flows (e.g. Subject Details) already carry a linked
    // backend subject id; the static catalog pick is only required for
    // the Quick Add flow that starts without one.
    if (_subjectId.isEmpty) {
      if (selectedGrade == null) {
        setState(() => _formError = 'Select a grade.');
        return null;
      }
      if (selectedSubject == null) {
        setState(() => _formError = 'Select a subject.');
        return null;
      }
      setState(() => _formError =
          'Selected subject is not linked to a backend subject yet.');
      return null;
    }
    final String title = _nameController.text.trim();
    if (title.isEmpty) {
      setState(() => _formError = 'Enter the lecture name.');
      return null;
    }
    final int? order = int.tryParse(_orderController.text.trim());
    if (order == null || order < 1) {
      setState(() => _formError = 'Enter a valid display order.');
      return null;
    }
    int? minutes;
    if (_guestAccess) {
      final String raw = _minutesController.text.trim();
      if (raw.isNotEmpty) {
        final int? parsed = int.tryParse(raw);
        if (parsed == null || parsed <= 0) {
          setState(() => _formError =
              'Available minutes must be greater than zero.');
          return null;
        }
        minutes = parsed;
      }
    }
    setState(() => _formError = null);
    return (title: title, order: order, minutes: minutes);
  }

  List<NewLectureResource> _commitResources() {
    const wireType = <String, String>{
      'Video': 'video',
      'PDF': 'pdf',
      'Attachment': 'attachment',
      'External Link': 'external_link',
    };
    final List<NewLectureResource> out = <NewLectureResource>[];
    for (int i = 0; i < _resources.length; i++) {
      final Map<String, String> row = _resources[i];
      out.add(NewLectureResource(
        type: wireType[row['type']] ?? 'video',
        title: (row['title'] ?? '').trim(),
        displayOrder: i + 1,
      ));
    }
    return out;
  }

  /// The single commit point for the whole workflow: one controller call
  /// carrying lecture fields + staged resources + staged access
  /// overrides. [publishNow] and [publishDateTime] are mutually
  /// exclusive; drafts pass both as null/false.
  Future<void> _commit({
    required String title,
    required int order,
    required bool publishNow,
    required DateTime? publishDateTime,
    required int? minutes,
  }) async {
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final DashboardSession? session =
          ref.read(sessionProvider).maybeWhen(
                data: (DashboardSession? s) => s,
                orElse: () => null,
              );
      await ref.read(subjectDetailsControllerProvider).createLectureFull(
            subjectId: _subjectId,
            tab: _tab,
            title: title,
            displayOrder: order,
            publishDateTime: publishDateTime,
            publishNow: publishNow,
            guestEnabled: _guestAccess,
            previewMinutes: minutes,
            resources: _commitResources(),
            accessByStudent: Map<String, bool>.from(_accessByStudent),
            actorId: session?.userId ?? 'dashboard',
          );
      if (!mounted) return;
      widget.onSave?.call();
      Navigator.of(context).pop(true);
    } on DecisionFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = 'Could not save the lecture. Please try again.';
      });
    }
  }

  /// Publish Now: immediate publish, requires at least one resource.
  Future<void> _publishNow() async {
    if (_saving) return;
    final validated = _validateCommon();
    if (validated == null) return;
    if (_resources.isEmpty) {
      setState(
          () => _formError = 'Add at least one resource to publish.');
      return;
    }
    await _commit(
      title: validated.title,
      order: validated.order,
      publishNow: true,
      publishDateTime: null,
      minutes: validated.minutes,
    );
  }

  /// Save Draft: unpublished, no date, zero resources allowed.
  Future<void> _saveDraft() async {
    if (_saving) return;
    final validated = _validateCommon();
    if (validated == null) return;
    await _commit(
      title: validated.title,
      order: validated.order,
      publishNow: false,
      publishDateTime: null,
      minutes: validated.minutes,
    );
  }

  /// Final Save: scheduled publish when a date was picked (requires at
  /// least one resource), otherwise a draft save.
  Future<void> _saveFinal() async {
    if (_saving) return;
    final validated = _validateCommon();
    if (validated == null) return;
    DateTime? publishDateTime;
    if (_publishDate != null) {
      if (_resources.isEmpty) {
        setState(
            () => _formError = 'Add at least one resource to publish.');
        return;
      }
      final TimeOfDay time = _publishTime ?? const TimeOfDay(hour: 0, minute: 0);
      publishDateTime = DateTime(
        _publishDate!.year,
        _publishDate!.month,
        _publishDate!.day,
        time.hour,
        time.minute,
      );
    }
    await _commit(
      title: validated.title,
      order: validated.order,
      publishNow: false,
      publishDateTime: publishDateTime,
      minutes: validated.minutes,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Dialog shell: max 640px wide, max 88% of viewport height (capped at
    // 750px). Sticky white header + divider, scrollable body below so
    // nothing clips or overflows.
    final Size viewport = MediaQuery.of(context).size;
    final double dialogWidth =
        (viewport.width - 48) < 640 ? (viewport.width - 48) : 640;
    double dialogHeight = viewport.height * 0.88;
    if (dialogHeight > 750) dialogHeight = 750;
    if (dialogHeight < 400) dialogHeight = 400;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          constraints: const BoxConstraints(maxWidth: 640),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 25,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              // Sticky / fixed white header (no clipping).
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Quick Upload',
                        style: TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: widget.onClose ??
                          () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(9999),
                      child: const SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: Icon(Icons.close,
                              size: 22, color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: const Color(0xFFEEEEEE)),
              // Scrollable body.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDropdownRow(
                        label: 'Grade',
                        value: selectedGrade,
                        hint: 'Select Grade',
                        options: gradeSubjects.keys.toList(),
                        kind: _DropdownKind.grade,
                      ),
                      const SizedBox(height: 12),
                      _buildDropdownRow(
                        label: 'Subject',
                        value: selectedSubject,
                        hint: 'Select Subject',
                        options: availableSubjects,
                        kind: _DropdownKind.subject,
                      ),
                      const SizedBox(height: 12),
                      _buildDropdownRow(
                        label: 'Section',
                        value: selectedSection,
                        hint: 'Select Section',
                        options: sectionOptions,
                        kind: _DropdownKind.section,
                      ),
                      const SizedBox(height: 16),
                      // Compact Name + Display order row.
                      _buildNameOrderRow(),
                      const SizedBox(height: 20),
                      const Text(
                        'Add Lecture Resources',
                        style: TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: Color(0xFF000000),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_resources.isEmpty)
                        const Padding(
                          padding:
                              EdgeInsets.only(bottom: 8),
                          child: Center(
                            child: Text(
                              'No resources added yet.',
                              style: TextStyle(
                                fontFamily:
                                    'Google Sans Flex',
                                fontSize: 13,
                                color: Color(0xFF9E9E9E),
                              ),
                            ),
                          ),
                        ),
                      for (int i = 0; i < _resources.length; i++)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: 8),
                          child: _buildResourceRow(
                            no: _resources[i]['no'] ?? '',
                            title:
                                _resources[i]['title'] ?? '',
                            onDelete: () => setState(
                                () => _resources.removeAt(i)),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Center(
                        child: InkWell(
                          onTap: _saving
                              ? null
                              : _handleAddResource,
                          borderRadius:
                              BorderRadius.circular(20),
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius:
                                  BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '+ Add Resource',
                              style: TextStyle(
                                fontFamily:
                                    'Google Sans Flex',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Publishing row (Figma 560x85): date + time columns
                      // (168 each) with clear (X) buttons, plus the 104px
                      // Publish Now / Save Draft action column.
                      SizedBox(
                        width: 560,
                        height: 85,
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            _buildDateTimeColumn(
                              label: 'Publish Date',
                              value: _publishDate == null
                                  ? null
                                  : formatPublishDate(
                                      _publishDate!),
                              hint: 'Select Date',
                              onTap: _handlePickDate,
                              onClear: () => setState(
                                  () => _publishDate = null),
                            ),
                            const SizedBox(width: 16),
                            _buildDateTimeColumn(
                              label: 'Publish Time',
                              value: _publishTime == null
                                  ? null
                                  : formatPublishTime(
                                      _publishTime!),
                              hint: 'Select Time',
                              onTap: _handlePickTime,
                              onClear: () => setState(
                                  () => _publishTime = null),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 104,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Invisible label placeholder: reserves
                                  // the exact label height so the pills
                                  // align with the date/time boxes in any
                                  // font without overflowing the 85px row.
                                  const Center(
                                    child: Text(
                                      '',
                                      style: TextStyle(
                                          fontFamily:
                                              'Google Sans Flex',
                                          fontSize: 14,
                                          fontWeight:
                                              FontWeight.w400,
                                          color: Colors.black),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _buildSmallActionButton(
                                      'Publish Now',
                                      _publishNow,
                                      filled: true),
                                  const SizedBox(height: 4),
                                  _buildSmallActionButton(
                                      'Save Draft',
                                      _saveDraft,
                                      filled: false),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Guest access row, centered horizontally. The
                      // labels are Flexible (wrapping instead of
                      // overflowing) so the row never overflows.
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        crossAxisAlignment:
                            CrossAxisAlignment.center,
                        children: [
                          const Flexible(
                            child: Text(
                              'Access for free Guest',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily:
                                      'Google Sans Flex',
                                  fontSize: 14,
                                  color: Colors.black),
                            ),
                          ),
                          const SizedBox(width: 12),
                          CupertinoSwitch(
                            value: _guestAccess,
                            activeColor:
                                const Color(0xFF34C759),
                            onChanged: _saving
                                ? null
                                : (bool v) => setState(
                                    () =>
                                        _guestAccess = v),
                          ),
                          const SizedBox(width: 12),
                          const Flexible(
                            child: Text(
                              'Available Minutes',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily:
                                      'Google Sans Flex',
                                  fontSize: 14,
                                  color: Colors.black),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 64,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(
                                      9999),
                              border: Border.all(
                                  color: const Color(
                                      0xFFE0E0E0)),
                            ),
                            child: TextField(
                              controller:
                                  _minutesController,
                              enabled: _guestAccess &&
                                  !_saving,
                              textAlign: TextAlign.center,
                              keyboardType:
                                  TextInputType.number,
                              style: const TextStyle(
                                  fontFamily:
                                      'Google Sans Flex',
                                  fontSize: 14,
                                  color: Colors.black),
                              decoration:
                                  const InputDecoration(
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.zero,
                                border:
                                    InputBorder.none,
                                hintText: '7',
                                hintStyle: TextStyle(
                                    color: Color(0xFFBDBDBD),
                                    fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : _handleConfigureAccess,
                          style:
                              OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: Color(0xFFE0E0E0)),
                            shape:
                                const StadiumBorder(),
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 10),
                          ),
                          child: const Text(
                            'Configure Access',
                            style: TextStyle(
                              fontFamily:
                                  'Google Sans Flex',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      if (_formError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _formError!,
                          style: const TextStyle(
                            fontFamily:
                                'Google Sans Flex',
                            fontSize: 12,
                            color: Color(0xFFDC2626),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Center(
                        child: SizedBox(
                          width: 120,
                          height: 36,
                          child: ElevatedButton(
                            onPressed:
                                _saving ? null : _saveFinal,
                            style:
                                ElevatedButton.styleFrom(
                              backgroundColor:
                                  Colors.black,
                              foregroundColor:
                                  Colors.white,
                              elevation: 0,
                              shape:
                                  const StadiumBorder(),
                              padding: EdgeInsets.zero,
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Save',
                                    style: TextStyle(
                                      fontFamily:
                                          'Google Sans Flex',
                                      fontSize: 14,
                                      fontWeight:
                                          FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cascading dropdown row: fixed 130px label + 42px input box with
  /// centered text and a rotating trailing chevron.
  ///
  /// The whole box (text, padding, arrow) is one [GestureDetector] with
  /// [HitTestBehavior.opaque], so tapping anywhere on it toggles the
  /// custom menu, which opens directly underneath the field: pure
  /// white, exactly 360px wide.
  Widget _buildDropdownRow({
    required String label,
    required String? value,
    required String hint,
    required List<String> options,
    required _DropdownKind kind,
  }) {
    final bool isOpen = _isKindOpen(kind);
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF000000),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _saving ? null : () => _toggleDropdown(kind, options),
              child: Container(
                key: _boxKeyFor(kind),
                width: double.infinity,
                height: 42,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFE0E0E0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value ?? hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 14,
                          color: value == null
                              ? const Color(0xFF9CA3AF)
                              : Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: isOpen ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Compact Name + Display order single row.
  Widget _buildNameOrderRow() {
    return Row(
      children: [
        const SizedBox(
          width: 130,
          child: Text(
            'Name',
            style: TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF000000),
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextFormField(
              controller: _nameController,
              focusNode: _nameFocus,
              enabled: !_saving,
              textAlignVertical:
                  TextAlignVertical.center,
              style: const TextStyle(
                fontFamily: 'Google Sans Flex',
                fontSize: 14,
                color: Colors.black,
              ),
              decoration: InputDecoration(
                hintText: 'أدخل اسم المحاضرة',
                hintStyle: const TextStyle(
                    color: Color(0xFFBDBDBD),
                    fontSize: 13),
                contentPadding:
                    const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: Color(0xFFE0E0E0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: Color(0xFFE0E0E0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: Color(0xFF111827)),
                ),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Display order',
            style: TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 13,
              color: Color(0xFF000000),
            ),
          ),
        ),
        SizedBox(
          width: 65,
          height: 42,
          child: TextFormField(
            controller: _orderController,
            focusNode: _orderFocus,
            enabled: !_saving,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 14,
              color: Colors.black,
            ),
            decoration: InputDecoration(
              hintText: '01',
              hintStyle: const TextStyle(
                  color: Color(0xFFBDBDBD), fontSize: 13),
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: Color(0xFFE0E0E0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: Color(0xFF111827)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResourceRow({
    required String no,
    required String title,
    required VoidCallback onDelete,
  }) {
    final String displayTitle =
        no.isNotEmpty ? '$no $title' : title;
    return Row(
      children: [
        Expanded(
          child: Text(
            displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF000000),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Edit',
              style: TextStyle(
                  color: Colors.white, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _saving ? null : onDelete,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(
                  color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  /// Figma publish bar column (168px): label above a 32px input box.
  /// Tapping the box opens the picker; the small X clears the value
  /// independently (its own gesture wins the arena, so the picker
  /// never opens from an X tap).
  Widget _buildDateTimeColumn({
    required String label,
    required String? value,
    required String hint,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final bool empty = value == null || value.isEmpty;
    return SizedBox(
      width: 168,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              label,
              style: const TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.black),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _saving ? null : onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF979797), width: 1.0),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      empty ? hint : value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: empty
                            ? const Color(0xFF9CA3AF)
                            : Colors.black,
                      ),
                    ),
                  ),
                  if (!empty)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _saving ? null : onClear,
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: Color(0xFF757575),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallActionButton(String label, VoidCallback onTap,
      {bool filled = true}) {
    if (!filled) {
      return SizedBox(
        width: 104,
        height: 26,
        child: OutlinedButton(
          onPressed: _saving ? null : onTap,
          style: OutlinedButton.styleFrom(
            side:
                const BorderSide(color: Color(0xFFE0E0E0)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            padding: EdgeInsets.zero,
          ),
          child: Text(label,
              style: const TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
      );
    }
    return SizedBox(
      width: 104,
      height: 26,
      child: ElevatedButton(
        onPressed: _saving ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Text(label,
            style: const TextStyle(
                fontFamily: 'Google Sans Flex',
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

}

/// ===========================================================================
/// Dialog 1: Select Resource Type (# add Resource - 411x309)
/// Direct tap opens specific overlay immediately, ZERO checkmarks
/// ===========================================================================
class _SelectResourceDialog extends StatelessWidget {
  const _SelectResourceDialog();

  @override
  Widget build(BuildContext context) {
    final options = ['Video', 'PDF', 'Attachment', 'External Link'];

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 411,
          height: 309,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x29000000), blurRadius: 32, offset: Offset(0, 12)),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 24,
                left: 78,
                child: const SizedBox(
                  width: 255,
                  height: 24,
                  child: Center(
                    child: Text(
                      'Add New Resource',
                      style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 22, fontWeight: FontWeight.w400, color: Color(0xFF111827)),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 24,
                left: 364,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: const SizedBox(width: 24, height: 24, child: Center(child: Icon(Icons.close, size: 20, color: Color(0xFF4B5563)))),
                ),
              ),
              Positioned(
                top: 89,
                left: 50,
                child: SizedBox(
                  width: 228,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < options.length; i++)
                        Padding(
                          padding: EdgeInsets.only(bottom: i < options.length - 1 ? 10 : 0),
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(options[i]), // Immediate selection
                            child: SizedBox(
                              width: 228,
                              height: 24,
                              child: Text(
                                options[i],
                                style: const TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 257,
                left: 144,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(9999),
                  child: Container(
                    width: 124,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(9999)),
                    child: const Text('Save', style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
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

/// ===========================================================================
/// Dialog 2: Add Video Dialog (#add Video Resource - 640x281)
/// ALL FIELDS EMPTY BY DEFAULT
/// ===========================================================================
class _AddVideoDialog extends StatefulWidget {
  const _AddVideoDialog();

  @override
  State<_AddVideoDialog> createState() => _AddVideoDialogState();
}

class _AddVideoDialogState extends State<_AddVideoDialog> {
  final _name = TextEditingController(text: '');
  final _order = TextEditingController(text: '');
  final _id = TextEditingController(text: '');

  @override
  Widget build(BuildContext context) {
    return _buildResourceModal(
      title: 'Add New Video',
      fields: [
        _ResourceFieldItem(label: 'Video Name', controller: _name, hint: 'Video Title'),
        _ResourceFieldItem(label: 'Video Display order', controller: _order, hint: '01'),
        _ResourceFieldItem(label: 'Video ID', controller: _id, hint: 'video-id'),
      ],
      onSave: () {
        Navigator.of(context).pop({
          'title': _name.text.trim().isEmpty ? 'Video' : _name.text.trim(),
          'order': _order.text.trim().isEmpty ? '01' : _order.text.trim(),
        });
      },
    );
  }
}

/// ===========================================================================
/// Dialog 3: Add PDF Dialog (#add PDF Resource - 640x281)
/// ALL FIELDS EMPTY BY DEFAULT
/// ===========================================================================
class _AddPdfDialog extends StatefulWidget {
  const _AddPdfDialog();

  @override
  State<_AddPdfDialog> createState() => _AddPdfDialogState();
}

class _AddPdfDialogState extends State<_AddPdfDialog> {
  final _name = TextEditingController(text: '');
  final _order = TextEditingController(text: '');

  /// Native-picked PDF (file_picker v12 API). Bytes are loaded via
  /// [PlatformFile.readAsBytes] into [_pickedPdfBytes] so the web
  /// upload path never needs dart:io.
  PlatformFile? _pickedPdfFile;
  Uint8List? _pickedPdfBytes;
  int _pickedPdfSize = 0;
  bool _picking = false;
  String? _fileError;

  /// In-memory PDF bytes for the backend storage upload
  /// (Firebase Storage `putData`). Kept so `readAsBytes` is called once.
  Uint8List? get pickedPdfBytes => _pickedPdfBytes;

  @override
  void dispose() {
    _name.dispose();
    _order.dispose();
    super.dispose();
  }

  static String _sanitizedBaseName(String filename) {
    var base = filename.trim();
    if (base.toLowerCase().endsWith('.pdf')) {
      base = base.substring(0, base.length - 4);
    }
    base = base.replaceAll(RegExp(r'[_-]+'), ' ');
    base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
    return base;
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _pickPdf() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _fileError = null;
    });
    try {
      // file_picker v12: single-file entry point, no withData flag.
      // Bytes are pulled explicitly below for the web upload path.
      final PlatformFile? file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf'],
      );
      if (!mounted) return;
      if (file == null) {
        setState(() => _picking = false);
        return;
      }
      final int byteCount = await file.length();
      final Uint8List bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedPdfFile = file;
        _pickedPdfBytes = bytes;
        _pickedPdfSize = byteCount;
        _picking = false;
        if (_name.text.trim().isEmpty) {
          final String suggestion = _sanitizedBaseName(file.name);
          if (suggestion.isNotEmpty) _name.text = suggestion;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _fileError = 'Could not open the file picker. Please try again.';
      });
    }
  }

  void _clearPicked() {
    setState(() {
      _pickedPdfFile = null;
      _pickedPdfBytes = null;
      _pickedPdfSize = 0;
    });
  }

  void _handleSave() {
    if (_pickedPdfFile == null) {
      setState(() => _fileError = 'Please select a PDF file first');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a PDF file first')),
      );
      return;
    }
    Navigator.of(context).pop(<String, String>{
      'title': _name.text.trim().isEmpty ? 'PDF' : _name.text.trim(),
      'order': _order.text.trim().isEmpty ? '01' : _order.text.trim(),
      'file': _pickedPdfFile!.name,
    });
  }

  @override
  Widget build(BuildContext context) {
    // 640 wide shell, 360 tall (was 281): the extra 79px hosts the
    // aligned third row (button ~38px + status ~28px) without pushing
    // the Save pill (top 308, 24px bottom margin). Fits 1280x800.
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 640,
          height: 360,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                  color: Color(0x29000000),
                  blurRadius: 32,
                  offset: Offset(0, 12)),
            ],
          ),
          child: Stack(
            children: <Widget>[
              const Positioned(
                top: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Text('Add New PDF',
                      style: TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 22,
                          color: Color(0xFF111827))),
                ),
              ),
              Positioned(
                top: 18,
                right: 24,
                child: IconButton(
                  icon: const Icon(Icons.close,
                      size: 20, color: Color(0xFF4B5563)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Positioned(
                top: 77,
                left: 40,
                child: SizedBox(
                  width: 560,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _pdfFieldRow(
                          label: 'PDF Name',
                          controller: _name,
                          hint: 'PDF Title'),
                      const SizedBox(height: 8),
                      _pdfFieldRow(
                          label: 'PDF Display order',
                          controller: _order,
                          hint: '01',
                          keyboardType: TextInputType.number),
                      const SizedBox(height: 12),
                      // Row 3: aligned grid — label 168 + gap 4 + action 388
                      // = 560, same left/right edges as the rows above.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SizedBox(
                            width: 168,
                            child: Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text('PDF File',
                                  style: TextStyle(
                                      fontFamily: 'Google Sans Flex',
                                      fontSize: 14,
                                      color: Colors.black)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 388,
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                InkWell(
                                  onTap: _picking ? null : _pickPdf,
                                  borderRadius:
                                      BorderRadius.circular(9999),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF111827),
                                      borderRadius:
                                          BorderRadius.circular(9999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        if (_picking)
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        else
                                          const Icon(Icons.upload,
                                              color: Colors.white,
                                              size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          _pickedPdfFile == null
                                              ? 'Upload PDF'
                                              : 'Replace PDF',
                                          style: const TextStyle(
                                              fontFamily:
                                                  'Google Sans Flex',
                                              fontSize: 14,
                                              color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_pickedPdfFile == null)
                                  const Text(
                                    'No file chosen (PDF only)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontFamily: 'Google Sans Flex',
                                        fontSize: 12,
                                        color: Color(0xFF6B7280)),
                                  )
                                else
                                  Container(
                                    constraints: const BoxConstraints(
                                        maxWidth: 388),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius:
                                          BorderRadius.circular(9999),
                                      border: Border.all(
                                          color:
                                              Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        const Icon(
                                            Icons.picture_as_pdf,
                                            size: 16,
                                            color: Color(0xFF111827)),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            '${_pickedPdfFile!.name} • ${_formatSize(_pickedPdfSize)}',
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontFamily:
                                                    'Google Sans Flex',
                                                fontSize: 12,
                                                color: Color(0xFF111827)),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        InkWell(
                                          onTap: _clearPicked,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  9999),
                                          child: const Padding(
                                            padding:
                                                EdgeInsets.all(2),
                                            child: Icon(Icons.close,
                                                size: 14,
                                                color: Color(
                                                    0xFF6B7280)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_fileError != null) ...<Widget>[
                                  const SizedBox(height: 4),
                                  Text(_fileError!,
                                      style: const TextStyle(
                                          fontFamily:
                                              'Google Sans Flex',
                                          fontSize: 12,
                                          color: Color(0xFFDC2626))),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 308,
                left: 258,
                child: InkWell(
                  onTap: _handleSave,
                  borderRadius: BorderRadius.circular(9999),
                  child: Container(
                    width: 124,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(9999)),
                    child: const Text('Save',
                        style: TextStyle(
                            fontFamily: 'Google Sans Flex',
                            fontSize: 14,
                            color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pdfFieldRow({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return SizedBox(
      height: 26,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 168,
            child: Text(label,
                style: const TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 14,
                    color: Colors.black)),
          ),
          const SizedBox(width: 4),
          Container(
            width: 304,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF979797)),
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Google Sans Flex', fontSize: 14),
              decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                      color: Color(0xFF9CA3AF), fontSize: 13),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 80,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(9999)),
            child: const Text('Edit',
                style: TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 14,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// ===========================================================================
/// Dialog 4: Add Attachment Dialog (#add Attachment resource - 640x281)
/// ALL FIELDS EMPTY BY DEFAULT
/// ===========================================================================
class _AddAttachmentDialog extends StatefulWidget {
  const _AddAttachmentDialog();

  @override
  State<_AddAttachmentDialog> createState() => _AddAttachmentDialogState();
}

class _AddAttachmentDialogState extends State<_AddAttachmentDialog> {
  final _name = TextEditingController(text: '');
  final _order = TextEditingController(text: '');

  /// Native-picked attachment (file_picker v12 API). Bytes are loaded via
  /// [PlatformFile.readAsBytes] into [_pickedAttachmentBytes] so the web
  /// upload path never needs dart:io.
  PlatformFile? _pickedAttachmentFile;
  Uint8List? _pickedAttachmentBytes;
  int _pickedAttachmentSize = 0;
  bool _picking = false;
  String? _fileError;

  /// In-memory bytes for the backend storage upload (`putData`).
  Uint8List? get pickedAttachmentBytes => _pickedAttachmentBytes;

  @override
  void dispose() {
    _name.dispose();
    _order.dispose();
    super.dispose();
  }

  static String _sanitizedBaseName(String filename) {
    var base = filename.trim();
    final int dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    base = base.replaceAll(RegExp(r'[_-]+'), ' ');
    base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
    return base;
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _pickAttachment() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _fileError = null;
    });
    try {
      // file_picker v12: single-file entry point. Custom filter keeps the
      // dialog focused on common attachments while staying native.
      final PlatformFile? file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>[
          'pdf', 'doc', 'docx', 'xls', 'xlsx',
          'ppt', 'pptx', 'zip', 'rar', 'txt',
        ],
      );
      if (!mounted) return;
      if (file == null) {
        setState(() => _picking = false);
        return;
      }
      final int byteCount = await file.length();
      final Uint8List bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedAttachmentFile = file;
        _pickedAttachmentBytes = bytes;
        _pickedAttachmentSize = byteCount;
        _picking = false;
        if (_name.text.trim().isEmpty) {
          final String suggestion = _sanitizedBaseName(file.name);
          if (suggestion.isNotEmpty) _name.text = suggestion;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _fileError = 'Could not open the file picker. Please try again.';
      });
    }
  }

  void _clearPicked() {
    setState(() {
      _pickedAttachmentFile = null;
      _pickedAttachmentBytes = null;
      _pickedAttachmentSize = 0;
    });
  }

  void _handleSave() {
    if (_pickedAttachmentFile == null) {
      setState(() => _fileError = 'Please select an attachment file first');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select an attachment file first')),
      );
      return;
    }
    Navigator.of(context).pop(<String, String>{
      'title':
          _name.text.trim().isEmpty ? 'Attachment' : _name.text.trim(),
      'order': _order.text.trim().isEmpty ? '01' : _order.text.trim(),
      'file': _pickedAttachmentFile!.name,
    });
  }

  @override
  Widget build(BuildContext context) {
    // 640 x 360 (was 281): third aligned row hosts button (~38px) +
    // status (~28px). Save stays 24px off bottom. Fits 1280x800.
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 640,
          height: 360,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                  color: Color(0x29000000),
                  blurRadius: 32,
                  offset: Offset(0, 12)),
            ],
          ),
          child: Stack(
            children: <Widget>[
              const Positioned(
                top: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Text('Add New Attachment',
                      style: TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 22,
                          color: Color(0xFF111827))),
                ),
              ),
              Positioned(
                top: 18,
                right: 24,
                child: IconButton(
                  icon: const Icon(Icons.close,
                      size: 20, color: Color(0xFF4B5563)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Positioned(
                top: 77,
                left: 40,
                child: SizedBox(
                  width: 560,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _attachmentFieldRow(
                          label: 'Attachment Name',
                          controller: _name,
                          hint: 'Attachment Title'),
                      const SizedBox(height: 8),
                      _attachmentFieldRow(
                          label: 'Attachment Display order',
                          controller: _order,
                          hint: '01',
                          keyboardType: TextInputType.number),
                      const SizedBox(height: 12),
                      // Row 3: aligned grid — label 176 + gap 4 + action 380
                      // = 560, same edges as the rows above.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SizedBox(
                            width: 176,
                            child: Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text('Attachment File',
                                  style: TextStyle(
                                      fontFamily: 'Google Sans Flex',
                                      fontSize: 14,
                                      color: Colors.black)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 380,
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                InkWell(
                                  onTap:
                                      _picking ? null : _pickAttachment,
                                  borderRadius:
                                      BorderRadius.circular(9999),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF111827),
                                      borderRadius:
                                          BorderRadius.circular(9999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        if (_picking)
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        else
                                          const Icon(Icons.upload,
                                              color: Colors.white,
                                              size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          _pickedAttachmentFile == null
                                              ? 'Upload Attachment'
                                              : 'Replace File',
                                          style: const TextStyle(
                                              fontFamily:
                                                  'Google Sans Flex',
                                              fontSize: 14,
                                              color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_pickedAttachmentFile == null)
                                  const Text(
                                    'No file chosen (PDF, Word, Excel, ZIP, etc.)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontFamily: 'Google Sans Flex',
                                        fontSize: 12,
                                        color: Color(0xFF6B7280)),
                                  )
                                else
                                  Container(
                                    constraints: const BoxConstraints(
                                        maxWidth: 380),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius:
                                          BorderRadius.circular(9999),
                                      border: Border.all(
                                          color:
                                              Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        const Icon(Icons.attach_file,
                                            size: 16,
                                            color: Color(0xFF111827)),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            '${_pickedAttachmentFile!.name} • ${_formatSize(_pickedAttachmentSize)}',
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontFamily:
                                                    'Google Sans Flex',
                                                fontSize: 12,
                                                color: Color(0xFF111827)),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        InkWell(
                                          onTap: _clearPicked,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  9999),
                                          child: const Padding(
                                            padding:
                                                EdgeInsets.all(2),
                                            child: Icon(Icons.close,
                                                size: 14,
                                                color: Color(
                                                    0xFF6B7280)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_fileError != null) ...<Widget>[
                                  const SizedBox(height: 4),
                                  Text(_fileError!,
                                      style: const TextStyle(
                                          fontFamily:
                                              'Google Sans Flex',
                                          fontSize: 12,
                                          color: Color(0xFFDC2626))),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 308,
                left: 258,
                child: InkWell(
                  onTap: _handleSave,
                  borderRadius: BorderRadius.circular(9999),
                  child: Container(
                    width: 124,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(9999)),
                    child: const Text('Save',
                        style: TextStyle(
                            fontFamily: 'Google Sans Flex',
                            fontSize: 14,
                            color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachmentFieldRow({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return SizedBox(
      height: 26,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 176,
            child: Text(label,
                style: const TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 14,
                    color: Colors.black)),
          ),
          const SizedBox(width: 4),
          Container(
            width: 296,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF979797)),
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Google Sans Flex', fontSize: 14),
              decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                      color: Color(0xFF9CA3AF), fontSize: 13),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 80,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(9999)),
            child: const Text('Edit',
                style: TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 14,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// ===========================================================================
/// Dialog 5: Add External Link Dialog (#add External Link resource - 640x281)
/// ALL FIELDS EMPTY BY DEFAULT
/// ===========================================================================
class _AddExternalLinkDialog extends StatefulWidget {
  const _AddExternalLinkDialog();

  @override
  State<_AddExternalLinkDialog> createState() => _AddExternalLinkDialogState();
}

class _AddExternalLinkDialogState extends State<_AddExternalLinkDialog> {
  final _name = TextEditingController(text: '');
  final _order = TextEditingController(text: '');
  final _url = TextEditingController(text: '');

  @override
  Widget build(BuildContext context) {
    return _buildResourceModal(
      title: 'Add New External Link',
      labelWidth: 180,
      fields: [
        _ResourceFieldItem(label: 'External Link Name', controller: _name, hint: 'Link Title'),
        _ResourceFieldItem(label: 'External Link Display order', controller: _order, hint: '01'),
        _ResourceFieldItem(label: 'External Link URL', controller: _url, hint: 'https://...'),
      ],
      onSave: () {
        Navigator.of(context).pop({
          'title': _name.text.trim().isEmpty ? 'External Link' : _name.text.trim(),
          'order': _order.text.trim().isEmpty ? '01' : _order.text.trim(),
        });
      },
    );
  }
}

class _ResourceFieldItem {
  final String label;
  final TextEditingController controller;
  final String hint;
  _ResourceFieldItem({required this.label, required this.controller, required this.hint});
}

Widget _buildResourceModal({
  required String title,
  required List<_ResourceFieldItem> fields,
  required VoidCallback onSave,
  double labelWidth = 168,
  Widget? extraWidget,
}) {
  return Center(
    child: Material(
      color: Colors.transparent,
      child: Container(
        width: 640,
        height: 281,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 32, offset: Offset(0, 12))],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Text(title, style: const TextStyle(fontFamily: 'Google Sans Flex', fontSize: 22, color: Color(0xFF111827))),
              ),
            ),
            Positioned(
              top: 18,
              right: 24,
              child: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFF4B5563)),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
            Positioned(
              top: 77,
              left: 40,
              child: SizedBox(
                width: 560,
                child: Column(
                  children: [
                    for (var field in fields) ...[
                      SizedBox(
                        height: 26,
                        child: Row(
                          children: [
                            SizedBox(
                              width: labelWidth,
                              child: Text(field.label, style: const TextStyle(fontFamily: 'Google Sans Flex', fontSize: 14, color: Colors.black)),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 560 - labelWidth - 88,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: const Color(0xFF979797)),
                              ),
                              child: TextField(
                                controller: field.controller,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontFamily: 'Google Sans Flex', fontSize: 14),
                                decoration: InputDecoration(hintText: field.hint, hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13), isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 80,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(9999)),
                              child: const Text('Edit', style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 14, color: Colors.white)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (extraWidget != null) ...[
                      const SizedBox(height: 4),
                      extraWidget,
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              top: 229,
              left: 258,
              child: InkWell(
                onTap: onSave,
                borderRadius: BorderRadius.circular(9999),
                child: Container(
                  width: 124,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(9999)),
                  child: const Text('Save', style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 14, color: Colors.white)),
                ),
              ),
            ),
            ],
              ),
            ),
          ),
        );
  }

/// ===========================================================================
/// Dialog 6: Calendar Dialog (Exact Figma 318px)
/// ===========================================================================
class _CustomCalendarDialog extends StatefulWidget {
  const _CustomCalendarDialog();

  @override
  State<_CustomCalendarDialog> createState() => _CustomCalendarDialogState();
}

class _CustomCalendarDialogState extends State<_CustomCalendarDialog> {
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static final List<int> _years =
      List<int>.generate(9, (int i) => 2024 + i);

  int _viewYear = 2026;
  int _viewMonth = 9;
  int _selectedDay = 9;

  final GlobalKey _monthKey = GlobalKey();
  final GlobalKey _yearKey = GlobalKey();

  final List<String> _weekdays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  static int _daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// Sunday-first leading offset for the 1st of the viewed month.
  static int _leadingOffset(int year, int month) =>
      DateTime(year, month, 1).weekday % 7;

  void _goToPreviousMonth() {
    setState(() {
      if (_viewMonth == 1) {
        _viewMonth = 12;
        _viewYear -= 1;
      } else {
        _viewMonth -= 1;
      }
      _clampSelectedDay();
    });
  }

  void _goToNextMonth() {
    setState(() {
      if (_viewMonth == 12) {
        _viewMonth = 1;
        _viewYear += 1;
      } else {
        _viewMonth += 1;
      }
      _clampSelectedDay();
    });
  }

  void _clampSelectedDay() {
    final int max = _daysInMonth(_viewYear, _viewMonth);
    if (_selectedDay > max) _selectedDay = max;
    if (_selectedDay < 1) _selectedDay = 1;
  }

  Future<void> _pickMonth() async {
    final BuildContext? boxContext = _monthKey.currentContext;
    if (boxContext == null) return;
    final RenderBox box =
        boxContext.findRenderObject()! as RenderBox;
    final Offset origin = box.localToGlobal(Offset.zero);
    final Size screen = MediaQuery.of(context).size;
    final int? picked = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height + 4,
        screen.width - origin.dx - 150,
        0,
      ),
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color(0x20000000),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      items: [
        for (int m = 1; m <= 12; m++)
          PopupMenuItem<int>(
            value: m,
            child: Center(child: Text(_months[m - 1])),
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() {
        _viewMonth = picked;
        _clampSelectedDay();
      });
    }
  }

  Future<void> _pickYear() async {
    final BuildContext? boxContext = _yearKey.currentContext;
    if (boxContext == null) return;
    final RenderBox box =
        boxContext.findRenderObject()! as RenderBox;
    final Offset origin = box.localToGlobal(Offset.zero);
    final Size screen = MediaQuery.of(context).size;
    final int? picked = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height + 4,
        screen.width - origin.dx - 130,
        0,
      ),
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color(0x20000000),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      items: [
        for (final int y in _years)
          PopupMenuItem<int>(
            value: y,
            child: Center(child: Text('$y')),
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() {
        _viewYear = picked;
        _clampSelectedDay();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final int daysCount = _daysInMonth(_viewYear, _viewMonth);
    final int offset = _leadingOffset(_viewYear, _viewMonth);
    final int prevCount = _daysInMonth(
        _viewMonth == 1 ? _viewYear - 1 : _viewYear,
        _viewMonth == 1 ? 12 : _viewMonth - 1);
    // Full weeks only: trailing cells show next month's head days.
    final int totalCells =
        ((offset + daysCount + 6) ~/ 7) * 7;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 318,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD9D9D9)),
            boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 32, offset: Offset(0, 12))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _goToPreviousMonth,
                  ),
                  InkWell(
                    key: _monthKey,
                    onTap: _pickMonth,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFD9D9D9)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _months[_viewMonth - 1],
                            style: const TextStyle(
                                fontFamily: 'Google Sans Flex',
                                fontSize: 15,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    key: _yearKey,
                    onTap: _pickYear,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFD9D9D9)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_viewYear',
                            style: const TextStyle(
                                fontFamily: 'Google Sans Flex',
                                fontSize: 15,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _goToNextMonth,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: _weekdays.map((d) => SizedBox(width: 32, child: Text(d, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF757575))))).toList(),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: totalCells,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    mainAxisExtent: 40),
                itemBuilder: (ctx, i) {
                  if (i < offset) {
                    // Previous month's tail days (display only).
                    return _adjacentDay('${prevCount - offset + 1 + i}');
                  }
                  final day = i - offset + 1;
                  if (day > daysCount) {
                    // Next month's head days (display only).
                    return _adjacentDay('${day - daysCount}');
                  }
                  final isSelected = day == _selectedDay;
                  return GestureDetector(
                    // Day tap selects (highlights); Save confirms.
                    onTap: () => setState(() => _selectedDay = day),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: isSelected
                          ? BoxDecoration(
                              color: const Color(0xFF2C2C2C),
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFFF5F5F5)
                              : const Color(0xFF1E1E1E),
                          fontSize: 16,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(
                      DateTime(_viewYear, _viewMonth, _selectedDay),
                    ),
                    borderRadius: BorderRadius.circular(9999),
                    child: Container(
                      width: 124,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(9999)),
                      child: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Adjacent-month filler day: gray display-only cell.
  static Widget _adjacentDay(String label) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFB3B3B3),
          fontSize: 16,
        ),
      ),
    );
  }
}

/// ===========================================================================
/// Dialog 7: Time Picker Wheels Dialog (Exact Figma 254x236 Glassmorphism)
/// ===========================================================================
class _CustomTimePickerWheelsDialog extends StatefulWidget {
  final TimeOfDay? initial;

  const _CustomTimePickerWheelsDialog({this.initial});

  @override
  State<_CustomTimePickerWheelsDialog> createState() => _CustomTimePickerWheelsDialogState();
}

class _CustomTimePickerWheelsDialogState extends State<_CustomTimePickerWheelsDialog> {
  late int _hour;
  late int _minute;
  late bool _isAm;

  @override
  void initState() {
    super.initState();
    final TimeOfDay initial = widget.initial ?? const TimeOfDay(hour: 9, minute: 0);
    _hour = initial.hourOfPeriod == 0 ? 12 : initial.hourOfPeriod;
    _minute = initial.minute;
    _isAm = initial.period == DayPeriod.am;
  }

  static const TextStyle _wheelSelectedStyle = TextStyle(
    fontSize: 29,
    color: Colors.white,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _wheelIdleStyle = TextStyle(
    fontSize: 22,
    color: Color(0xFF545454),
  );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: 254,
              height: 236,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0x4C7F7F7F),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white, width: 1.4),
                boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 28, offset: Offset(0, 8))],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            SizedBox(
                              width: 64,
                              child: CupertinoPicker(
                                key: const Key('hourWheel'),
                                itemExtent: 36,
                                backgroundColor: Colors.transparent,
                                scrollController: FixedExtentScrollController(
                                    initialItem: _hour - 1),
                                onSelectedItemChanged: (i) => setState(() => _hour = i + 1),
                                children: List.generate(
                                    12,
                                    (i) => Center(
                                            child: Text(
                                          '${i + 1}',
                                          style: (i + 1) == _hour
                                              ? _wheelSelectedStyle
                                              : _wheelIdleStyle,
                                        ))),
                              ),
                            ),
                            SizedBox(
                              width: 64,
                              child: CupertinoPicker(
                                key: const Key('minuteWheel'),
                                itemExtent: 36,
                                backgroundColor: Colors.transparent,
                                scrollController: FixedExtentScrollController(
                                    initialItem: _minute),
                                onSelectedItemChanged: (i) => setState(() => _minute = i),
                                children: List.generate(
                                    60,
                                    (i) => Center(
                                            child: Text(
                                          i.toString().padLeft(2, '0'),
                                          style: i == _minute
                                              ? _wheelSelectedStyle
                                              : _wheelIdleStyle,
                                        ))),
                              ),
                            ),
                            SizedBox(
                              width: 64,
                              child: CupertinoPicker(
                                key: const Key('periodWheel'),
                                itemExtent: 36,
                                backgroundColor: Colors.transparent,
                                scrollController: FixedExtentScrollController(
                                    initialItem: _isAm ? 0 : 1),
                                onSelectedItemChanged: (i) => setState(() => _isAm = i == 0),
                                children: [
                                  Center(
                                      child: Text('AM',
                                          style: _isAm
                                              ? _wheelSelectedStyle
                                              : _wheelIdleStyle)),
                                  Center(
                                      child: Text('PM',
                                          style: !_isAm
                                              ? _wheelSelectedStyle
                                              : _wheelIdleStyle)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: [0.0, 0.5, 1.0],
                                  colors: [
                                    Colors.transparent,
                                    Color(0x40000000),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(9999),
                        child: Container(
                          width: 100,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9999),
                              border: Border.all(color: Colors.white)),
                          child: const Text('Cancel', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () {
                          int h = _hour;
                          if (_isAm) {
                            if (h == 12) h = 0;
                          } else {
                            if (h != 12) h += 12;
                          }
                          Navigator.of(context).pop(TimeOfDay(hour: h, minute: _minute));
                        },
                        borderRadius: BorderRadius.circular(9999),
                        child: Container(
                          width: 100,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(9999)),
                          child: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===========================================================================
/// Dialog 8: Configure Access Dialog (640x540)
///
/// Lecture-specific student access override opened from the Quick Add
/// New Lecture "Configure Access" button. Shows ONLY students enrolled
/// in [subjectId] (non-deleted `subject_access_assignments`, joined
/// with approved `users`) — Section never affects eligibility.
///
/// Working state is local to the dialog session: toggles never write
/// to the backend. Cancel/X discards everything. Save returns the
/// effective per-student map; when [lectureId] is provided (edit flow)
/// the dialog persists via `lecture_access_grants` first and only pops
/// after the save succeeds, otherwise (Quick Add flow, lecture does
/// not exist yet) the map is returned to the caller for inclusion in
/// the lecture-creation batch. Default is ON (no override).
///
/// Row metadata per student: Student Number (رقم الطالب, from the
/// registered phone, '---' when absent), Student Name, and Subject Plan
/// chip (باقة المادة), plus the access toggle.
/// ===========================================================================
class _ConfigureAccessDialog extends ConsumerStatefulWidget {
  final String subjectId;

  /// Null while the lecture does not exist yet (Quick Add flow) — Save
  /// then returns overrides to the caller instead of persisting.
  final String? lectureId;

  /// Previously staged overrides (Quick Add session state).
  final Map<String, bool> initialOverrides;

  const _ConfigureAccessDialog({
    required this.subjectId,
    this.lectureId,
    this.initialOverrides = const <String, bool>{},
  });

  @override
  ConsumerState<_ConfigureAccessDialog> createState() => _ConfigureAccessDialogState();
}

class _ConfigureAccessDialogState extends ConsumerState<_ConfigureAccessDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late Map<String, bool> _staged;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _staged = Map<String, bool>.from(widget.initialOverrides);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<LectureAccessStudent>> studentsAsync =
        ref.watch(subjectLectureRosterProvider(widget.subjectId));
    final AsyncValue<List<LectureAccessGrant>> grantsAsync =
        widget.lectureId == null
            ? const AsyncValue<List<LectureAccessGrant>>.data(
                <LectureAccessGrant>[])
            : ref.watch(lectureAccessGrantsProvider(widget.lectureId!));

    // Data for the footer actions. The list body above renders the same
    // values through the loading/error states.
    final List<LectureAccessStudent>? roster = studentsAsync.value;
    final Map<String, bool> grantById =
        _grantMap(grantsAsync.value ?? const <LectureAccessGrant>[]);
    final bool dataReady = studentsAsync.hasValue &&
        (widget.lectureId == null || grantsAsync.hasValue);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 640,
          height: 540,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 32, offset: Offset(0, 12))],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 36, right: 24, top: 20, bottom: 12),
                child: Row(
                  children: [
                    const Spacer(),
                    const Text(
                      'Configure Access',
                      style: TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: Color(0xFF4B5563)),
                      // X discards unsaved changes exactly like Cancel.
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFD1D5DB), width: 1.0),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                    style: const TextStyle(fontFamily: 'Google Sans Flex', fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'بحث باسم الطالب، الكود، أو الباقة...',
                      hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 7),
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.search, size: 16, color: Color(0xFF9CA3AF)),
                      prefixIconConstraints: BoxConstraints(minWidth: 24, maxHeight: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Expanded(
                child: studentsAsync.when(
                  loading: () => const Center(child: CupertinoActivityIndicator()),
                  error: (err, _) => Center(child: Text('خطأ في تحميل الطلاب: $err')),
                  data: (roster) {
                    return grantsAsync.when(
                      loading: () =>
                          const Center(child: CupertinoActivityIndicator()),
                      error: (err, _) => Center(
                          child: Text('خطأ في تحميل الصلاحيات: $err')),
                      data: (grants) =>
                          _rosterList(roster, _grantMap(grants)),
                    );
                  },
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              const SizedBox(height: 14),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _saveError!,
                    style: const TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 124,
                      height: 28,
                      child: OutlinedButton(
                        // Cancel discards every unsaved change.
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.black),
                          shape: const StadiumBorder(),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontFamily: 'Google Sans Flex',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 124,
                      height: 28,
                      child: ElevatedButton(
                        onPressed: !dataReady || _saving || roster == null
                            ? null
                            : () => _save(roster, grantById),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: const StadiumBorder(),
                          padding: EdgeInsets.zero,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save',
                                style: TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Persists the effective per-student map as one logical save.
  ///
  /// Quick Add flow ([lectureId] == null, lecture does not exist yet):
  /// returns the map to the caller for the lecture-creation batch.
  /// Edit flow: writes via the use case first and pops only after the
  /// save succeeds. On failure the overlay stays open with working
  /// state intact and the error surfaces via SnackBar for retry.
  Future<void> _save(
    List<LectureAccessStudent> roster,
    Map<String, bool> grantById,
  ) async {
    final Map<String, bool> effective = <String, bool>{
      for (final LectureAccessStudent s in roster)
        s.id: resolveLectureAccess(
          staged: _staged[s.id],
          grantAllowed: grantById[s.id],
        ),
    };
    final String? lectureId = widget.lectureId;
    if (lectureId == null) {
      if (mounted) Navigator.of(context).pop(effective);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final DashboardSession? session =
          ref.read(sessionProvider).maybeWhen(
                data: (DashboardSession? s) => s,
                orElse: () => null,
              );
      await ref
          .read(saveLectureAccessOverridesUseCaseProvider)
          .execute(
            lectureId: lectureId,
            allowedByStudent: effective,
            actorId: session?.userId ?? 'dashboard',
          );
      if (!mounted) return;
      Navigator.of(context).pop(effective);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = failure.code == FailureCode.permissionDenied
            ? 'You do not have permission to change lecture access.'
            : 'Could not save lecture access. Please try again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_saveError!)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save lecture access. Please try again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_saveError!)),
      );
    }
  }

  /// Filtered roster list. Search never mutates enrollment; toggles
  /// write only to the local [_staged] working state.
  Widget _rosterList(
    List<LectureAccessStudent> roster,
    Map<String, bool> grantById,
  ) {
    final List<LectureAccessStudent> filtered = roster
        .where((LectureAccessStudent s) => matchesLectureAccessQuery(
              name: s.name,
              phone: s.phone,
              plan: s.plan,
              query: _searchQuery,
            ))
        .toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'لا يوجد طلاب مسجلين مطابقين للبحث',
          style: TextStyle(fontFamily: 'Google Sans Flex', color: Color(0xFF6B7280)),
        ),
      );
    }

    return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF3F4F6)),
                          itemBuilder: (ctx, i) {
                            final student = filtered[i];
                            final bool hasAccess = resolveLectureAccess(
                              staged: _staged[student.id],
                              grantAllowed: grantById[student.id],
                            );
                            final code = (student.phone != null && student.phone!.trim().isNotEmpty)
                                ? student.phone!.trim()
                                : '---';
                            final planLabel = student.plan == 'FREE' ? 'الباقة الافتراضية' : student.plan;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFFF3F4F6),
                                    child: Text(
                                      student.name.isNotEmpty ? student.name[0] : 'S',
                                      style: const TextStyle(
                                        fontFamily: 'Google Sans Flex',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF374151),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          student.name,
                                          style: const TextStyle(
                                            fontFamily: 'Google Sans Flex',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF111827),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              'رقم الطالب: $code',
                                              style: const TextStyle(
                                                fontFamily: 'Google Sans Flex',
                                                fontSize: 11,
                                                color: Color(0xFF6B7280),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF3F4F6),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: const Color(0xFFE5E7EB)),
                                              ),
                                              child: Text(
                                                planLabel,
                                                style: const TextStyle(
                                                  fontFamily: 'Google Sans Flex',
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                  color: Color(0xFF374151),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _saving
                                        ? null
                                        : () {
                                            setState(() {
                                              _staged[student.id] =
                                                  !hasAccess;
                                            });
                                          },
                                    child: Container(
                                      width: 48,
                                      height: 24,
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: hasAccess ? const Color(0xFF10B981) : const Color(0xFFE5E7EB),
                                        borderRadius: BorderRadius.circular(100),
                                      ),
                                      child: AnimatedAlign(
                                        duration: const Duration(milliseconds: 150),
                                        alignment: hasAccess ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
  }

  static Map<String, bool> _grantMap(List<LectureAccessGrant> grants) =>
      <String, bool>{
        for (final LectureAccessGrant g in grants) g.studentId: g.allowed,
      };
}
