import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../academic_periods/presentation/screens/academic_periods_screen.dart';
import '../../../authentication/domain/entities/auth_user.dart';

/// Subscription Plans (Feature Matrix) dashboard.
///
/// Layout follows the approved Figma `Subscription` frame:
/// 1. `plans nav bar` — Guest / Center FREE / Center PRO / Center MAX.
/// 2. Category nav bar — Video & Media / Pdf & documents / ... (scrolls to section).
/// 3. Full settings of the SELECTED plan only, every row driven by a
///    [CupertinoSwitch] (green = enabled), whole page scrolls to the end.
///
/// Every write goes through the `setPlanFeature` callable — client writes to
/// `plan_features` stay denied in `firestore.rules`. Subscriptions themselves
/// are per-subject and bound to the active academic term (start/end buttons
/// live on [AcademicPeriodsScreen]).
class SubscriptionPlansScreen extends StatefulWidget {
  final AuthUser user;

  const SubscriptionPlansScreen({required this.user, super.key});

  @override
  State<SubscriptionPlansScreen> createState() => _SubscriptionPlansScreenState();
}

enum _ValueKind { toggle, number, quality, text }

class _FeatureDef {
  final String key;
  final String label;
  final String? hint;
  final _ValueKind kind;

  const _FeatureDef(this.key, this.label, {this.hint, this.kind = _ValueKind.toggle});
}

class _FeatureSection {
  final String id;
  final String title;
  final List<_FeatureDef> features;

  const _FeatureSection(this.id, this.title, this.features);
}

const _videoQualities = <String>[
  '144p',
  '240p',
  '360p',
  '480p',
  '720p',
  '1080p',
  '1440p',
  '2k',
  '4k',
];

const _sections = <_FeatureSection>[
  _FeatureSection('video', 'Video & Media', [
    _FeatureDef('video.access', 'مشاهدة الفيديو'),
    _FeatureDef('video.preview_duration', 'مدة المعاينة (دقائق)',
        hint: 'Guest فقط — Center غير محدود', kind: _ValueKind.number),
    _FeatureDef('video.rolling_window.enabled', 'تحديد المشاهدة كل 24 ساعة',
        hint: 'تفعيل/إلغاء النافذة الزمنية على أي خطة'),
    _FeatureDef('video.rolling_window.hours', 'مدة نافذة المشاهدة (ساعات)',
        hint: 'افتراضي 24 — من 1 إلى 168', kind: _ValueKind.number),
    _FeatureDef('video.quality.max', 'أعلى جودة متاحة', kind: _ValueKind.quality),
    _FeatureDef('video.quality.144p', 'جودة 144p'),
    _FeatureDef('video.quality.240p', 'جودة 240p'),
    _FeatureDef('video.quality.360p', 'جودة 360p'),
    _FeatureDef('video.quality.480p', 'جودة 480p'),
    _FeatureDef('video.quality.720p', 'جودة 720p'),
    _FeatureDef('video.quality.1080p', 'جودة 1080p'),
    _FeatureDef('video.quality.1440p', 'جودة 1440p'),
    _FeatureDef('video.quality.2k', 'جودة 2K'),
    _FeatureDef('video.quality.4k', 'جودة 4K'),
    _FeatureDef('video.playback_speed', 'التحكم في سرعة التشغيل'),
    _FeatureDef('video.playback_speed.x0_5', 'سرعة X0.50'),
    _FeatureDef('video.playback_speed.x1_0', 'سرعة X1.00'),
    _FeatureDef('video.playback_speed.x2_0', 'سرعة X2.00'),
    _FeatureDef('video.playback_speed.x3_0', 'سرعة X3.00'),
    _FeatureDef('video.playback_speed.x4_0', 'سرعة X4.00'),
    _FeatureDef('video.pip', 'صورة داخل صورة (PiP)'),
    _FeatureDef('video.cast', 'الكاست على التلفزيون'),
    _FeatureDef('video.download', 'تحميل الفيديو أوفلاين'),
    _FeatureDef('video.download.choose_quality', 'السماح باختيار جودة التحميل'),
    _FeatureDef('video.download.max_count', 'أقصى عدد فيديوهات محملة',
        kind: _ValueKind.number),
    _FeatureDef('video.download.quality', 'جودة التحميل', kind: _ValueKind.quality),
    _FeatureDef('video.resume', 'الاستكمال من آخر موضع'),
    _FeatureDef('video.skip_forward_backward', 'التقديم والتأخير'),
    _FeatureDef('video.heatmap', 'خريطة الأوقات الأكثر مشاهدة'),
    _FeatureDef('video.watermark', 'العلامة المائية للفيديو'),
    _FeatureDef('video.security.screen_record_detect', 'كشف تسجيل الشاشة'),
    _FeatureDef('video.security.screenshot_prevent', 'منع لقطات الشاشة'),
  ]),
  _FeatureSection('pdf', 'Pdf & documents', [
    _FeatureDef('pdf.access', 'عرض ملفات PDF'),
    _FeatureDef('pdf.preview_pages', 'عدد صفحات المعاينة',
        hint: 'Guest = 5 — Center غير محدود', kind: _ValueKind.number),
    _FeatureDef('pdf.download', 'تحميل PDF'),
    _FeatureDef('pdf.offline', 'قراءة PDF أوفلاين'),
    _FeatureDef('pdf.offline_max_files', 'أقصى عدد ملفات PDF أوفلاين',
        kind: _ValueKind.number),
    _FeatureDef('pdf.search', 'البحث داخل PDF'),
    _FeatureDef('pdf.zoom', 'التكبير (Zoom)'),
    _FeatureDef('pdf.bookmarks', 'علامات PDF المرجعية'),
    _FeatureDef('pdf.toc', 'جدول المحتويات'),
    _FeatureDef('pdf.print', 'طباعة PDF'),
    _FeatureDef('pdf.copy', 'نسخ النص'),
    _FeatureDef('pdf.share', 'مشاركة PDF'),
    _FeatureDef('pdf.watermark', 'العلامة المائية لـ PDF'),
    _FeatureDef('pdf.security.screen_record_detect', 'كشف تسجيل الشاشة (PDF)'),
    _FeatureDef('pdf.security.screenshot_prevent', 'منع لقطات الشاشة (PDF)'),
  ]),
  _FeatureSection('attachments', 'Attachments', [
    _FeatureDef('attachment.access', 'فتح المرفقات'),
    _FeatureDef('attachment.download', 'تحميل المرفقات'),
  ]),
  _FeatureSection('assessment', 'Quizzes & Exams', [
    _FeatureDef('quiz.access', 'اختبارات التايم لاين'),
    _FeatureDef('quiz.attempts', 'عدد محاولات الكويز', kind: _ValueKind.number),
    _FeatureDef('quiz.review', 'مراجعة الإجابات'),
    _FeatureDef('quiz.explanation', 'عرض الشرح'),
    _FeatureDef('exam.access', 'دخول الامتحانات'),
    _FeatureDef('exam.review_solutions', 'مراجعة حلول الامتحان'),
    _FeatureDef('exam.practice_mode', 'وضع التدريب'),
    _FeatureDef('exam.attempts', 'عدد محاولات الامتحان', kind: _ValueKind.number),
    _FeatureDef('exam.anti_cheat', 'الحماية من الغش'),
    _FeatureDef('exam.countdown', 'مؤقت الامتحان الإجباري'),
    _FeatureDef('exam.shuffle', 'خلط الأسئلة والاختيارات'),
    _FeatureDef('exam.question_bank', 'بنك الأسئلة للتدريب الذاتي'),
    _FeatureDef('exam.prerequisite', 'شرط اجتياز السابق'),
    _FeatureDef('exam.result.visibility', 'سياسة ظهور النتيجة',
        hint: 'مثال: immediate', kind: _ValueKind.text),
    _FeatureDef('progress.tracking', 'تتبع تقدم التعلم'),
    _FeatureDef('progress.analytics', 'التحليلات الشخصية للطالب'),
  ]),
  _FeatureSection('chat', 'Chat & Questions', [
    _FeatureDef('chat.admin', 'شات الإدارة (Center فقط)'),
    _FeatureDef('chat.doctor_channel', 'قناة الدكتور (قراءة فقط)'),
    _FeatureDef('chat.attachments', 'إرسال مرفقات في الشات'),
    _FeatureDef('question.submit', 'إرسال سؤال للإدارة'),
    _FeatureDef('question.attachments', 'إرفاق ملفات مع السؤال'),
  ]),
  _FeatureSection('notifications', 'Notifications', [
    _FeatureDef('notification.push', 'إشعارات Push'),
    _FeatureDef('notification.in_app', 'إشعارات داخل التطبيق'),
    _FeatureDef('notification.quiet_hours', 'الوضع الصامت (Quiet Hours)'),
  ]),
  _FeatureSection('productivity', 'Notes & Bookmarks', [
    _FeatureDef('notes.create', 'إنشاء الملاحظات'),
    _FeatureDef('notes.search', 'البحث في الملاحظات'),
    _FeatureDef('notes.image', 'ملاحظات بالصور'),
    _FeatureDef('notes.voice', 'ملاحظات صوتية'),
    _FeatureDef('notes.export', 'تصدير الملاحظات'),
    _FeatureDef('notes.smart', 'حفظ Smart Notes'),
    _FeatureDef('notes.reminders', 'التذكيرات وجدول المذاكرة'),
    _FeatureDef('notes.revision_tag', 'تعليم المحاضرات للمراجعة'),
    _FeatureDef('bookmark.create', 'إنشاء الإشارات المرجعية'),
    _FeatureDef('bookmark.max_count', 'أقصى عدد للإشارات',
        hint: 'Max = غير محدود', kind: _ValueKind.number),
    _FeatureDef('bookmark.search', 'البحث في الإشارات'),
  ]),
  _FeatureSection('device', 'Devices & Security', [
    _FeatureDef('device.max_count', 'عدد الأجهزة المسموح',
        hint: 'Pro = 1 — Max يُضبط يدوياً', kind: _ValueKind.number),
    _FeatureDef('device.replace', 'استبدال الجهاز ذاتياً'),
    _FeatureDef('security.score', 'عرض نقاط الأمان'),
    _FeatureDef('security.block_root', 'حظر الروت والمحاكيات'),
    _FeatureDef('offline.mode', 'وضع الأوفلاين العام'),
    _FeatureDef('offline.encryption', 'تشفير DRM (AES-256)'),
  ]),
  _FeatureSection('profile', 'Profile & Account', [
    _FeatureDef('profile.edit_name', 'تعديل الاسم'),
    _FeatureDef('profile.edit_photo', 'تعديل الصورة'),
    _FeatureDef('profile.change_password', 'تغيير كلمة المرور'),
    _FeatureDef('profile.view_device', 'عرض بيانات الجهاز'),
    _FeatureDef('profile.view_membership', 'عرض بيانات الاشتراك'),
    _FeatureDef('profile.display_handle', 'الاسم المعروض العام'),
  ]),
];

const _planOrder = <String>['guest', 'free', 'pro', 'max'];

const _planLabels = <String, String>{
  'guest': 'Guest',
  'free': 'Free',
  'pro': 'Pro',
  'max': 'Max',
};

/// Mirrors SENSITIVE_PLAN_FEATURES in functions/src/index.ts: Teacher-only
/// keys render locked for Admin sessions; the backend is the true boundary.
const _teacherOnlyFeatures = <String>{
  'video.rolling_window.enabled',
  'video.rolling_window.hours',
};

class _SubscriptionPlansScreenState extends State<SubscriptionPlansScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
  final _scrollController = ScrollController();

  String _selectedPlan = 'guest';
  int _selectedCategory = 0;
  final _pending = <String>{};
  final Map<String, GlobalKey> _sectionKeys = {
    for (final section in _sections) section.id: GlobalKey(),
  };

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCategory(int index) {
    setState(() => _selectedCategory = index);
    final key = _sectionKeys[_sections[index].id];
    final context = key?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
    }
  }

  Future<void> _saveFeature({
    required String featureKey,
    required bool enabled,
    Object? value,
    String valueType = 'boolean',
  }) async {
    if (_pending.contains(featureKey)) return;
    setState(() => _pending.add(featureKey));
    try {
      await _functions.httpsCallable('setPlanFeature').call({
        'planId': _selectedPlan,
        'featureKey': featureKey,
        'enabled': enabled,
        if (value case final Object v) 'value': v,
        'valueType': valueType,
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyFunctionErrorMessage(error, 'تعذر حفظ الميزة.')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending.remove(featureKey));
    }
  }

  Future<void> _editValue(
    _FeatureDef def,
    bool enabled,
    Object? currentValue,
  ) async {
    final controller = TextEditingController(
      text: currentValue == null ? '' : currentValue.toString(),
    );
    String? quality = def.kind == _ValueKind.quality
        ? (currentValue?.toString().toLowerCase() ?? '720p')
        : null;
    if (quality != null && !_videoQualities.contains(quality)) {
      quality = '720p';
    }

    final saved = await showDialog<Object?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(def.label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (def.hint != null) ...[
                Text(def.hint!,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 8),
              ],
              if (def.kind == _ValueKind.quality)
                DropdownButtonFormField<String>(
                  initialValue: quality,
                  decoration: const InputDecoration(labelText: 'الجودة'),
                  items: [
                    for (final option in _videoQualities)
                      DropdownMenuItem(value: option, child: Text(option)),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => quality = value ?? quality),
                )
              else
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: def.kind == _ValueKind.number
                      ? TextInputType.number
                      : TextInputType.text,
                  inputFormatters: def.kind == _ValueKind.number
                      ? [FilteringTextInputFormatter.digitsOnly]
                      : const [],
                  decoration: InputDecoration(
                    labelText: def.kind == _ValueKind.number ? 'القيمة (رقم)' : 'القيمة',
                    helperText: def.key,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (def.kind == _ValueKind.quality) {
                  Navigator.pop(dialogContext, quality);
                } else if (def.kind == _ValueKind.number) {
                  final parsed = int.tryParse(controller.text.trim());
                  if (parsed == null) return;
                  Navigator.pop(dialogContext, parsed);
                } else {
                  Navigator.pop(dialogContext, controller.text.trim());
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (saved == null || !mounted) return;

    await _saveFeature(
      featureKey: def.key,
      enabled: enabled,
      value: saved,
      valueType: def.kind == _ValueKind.number
          ? 'number'
          : def.kind == _ValueKind.quality
              ? 'string'
              : 'string',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الاشتراكات والخطط')),
      body: Column(
        children: [
          const SizedBox(height: 12),
          const Text(
            'Tarek el araby Platform',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _PlansNavBar(
            selectedPlan: _selectedPlan,
            onSelect: (planId) => setState(() => _selectedPlan = planId),
          ),
          const SizedBox(height: 10),
          _CategoryNavBar(
            selectedIndex: _selectedCategory,
            onSelect: _scrollToCategory,
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildPlanBody()),
        ],
      ),
    );
  }

  Widget _buildPlanBody() {
    final featuresStream = _firestore
        .collection('plan_features')
        .where('plan_id', isEqualTo: _selectedPlan)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: featuresStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('تعذر تحميل إعدادات الخطة.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final byKey = <String, Map<String, dynamic>>{
          for (final doc in snapshot.data!.docs)
            ((doc.data()['feature_key'] ?? '').toString()): doc.data(),
        };
        final enabledCount =
            byKey.values.where((data) => data['enabled'] == true).length;

        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TermCard(user: widget.user),
              const SizedBox(height: 10),
              _PlanSummaryCard(
                planLabel: _planLabels[_selectedPlan] ?? _selectedPlan,
                enabledCount: enabledCount,
                totalCount: _sections.fold<int>(
                    0, (total, section) => total + section.features.length),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < _sections.length; i++) ...[
                _SectionCard(
                  key: _sectionKeys[_sections[i].id],
                  section: _sections[i],
                  valuesByKey: byKey,
                  pending: _pending,
                  isTeacher: widget.user.role == 'teacher',
                  onToggle: (def, enabled) {
                    final current = byKey[def.key];
                    final currentValue =
                        current?['value'] ?? current?['feature_value'];
                    _saveFeature(
                      featureKey: def.key,
                      enabled: enabled,
                      value: currentValue is num || currentValue is String
                          ? currentValue
                          : null,
                      valueType: def.kind == _ValueKind.number
                          ? 'number'
                          : def.kind == _ValueKind.toggle
                              ? 'boolean'
                              : 'string',
                    );
                  },
                  onEditValue: (def) {
                    final current = byKey[def.key];
                    _editValue(
                      def,
                      current?['enabled'] == true,
                      current?['value'] ?? current?['feature_value'],
                    );
                  },
                ),
                const SizedBox(height: 10),
              ],
              const _PlansFootnote(),
            ],
          ),
        );
      },
    );
  }
}

/// Top `plans nav bar`: pill container, selected segment is solid black.
class _PlansNavBar extends StatelessWidget {
  final String selectedPlan;
  final ValueChanged<String> onSelect;

  const _PlansNavBar({required this.selectedPlan, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('plans')
          .orderBy('display_order')
          .snapshots(),
      builder: (context, snapshot) {
        final ids = snapshot.data?.docs.map((doc) => doc.id).toList() ??
            _planOrder;
        final ordered = [
          for (final id in _planOrder)
            if (ids.contains(id)) id,
          for (final id in ids)
            if (!_planOrder.contains(id)) id,
        ];
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(AppShapes.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final planId in ordered)
                  _PlanSegment(
                    label: _planLabels[planId] ?? planId,
                    selected: planId == selectedPlan,
                    onTap: () => onSelect(planId),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlanSegment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PlanSegment(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(AppShapes.radiusFull),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Second nav bar: feature categories, tap scrolls to the section.
class _CategoryNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _CategoryNavBar({required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(AppShapes.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _sections.length; i++)
              _PlanSegment(
                label: _sections[i].title,
                selected: i == selectedIndex,
                onTap: () => onSelect(i),
              ),
          ],
        ),
      ),
    );
  }
}

/// Active term banner: subscription is fixed per term and per subject.
class _TermCard extends StatelessWidget {
  final AuthUser user;

  const _TermCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('academic_periods')
          .where('is_core', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        String label = 'لا توجد فترة نشطة';
        String? activeId;
        for (final doc in snapshot.data?.docs ?? const []) {
          final data = doc.data();
          if (data['status'] == 'active' && data['is_deleted'] != true) {
            label = (data['label'] ?? doc.id).toString();
            activeId = doc.id;
            break;
          }
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined,
                        color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text('الترم الحالي',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: activeId == null
                            ? AppColors.itemSurface
                            : AppColors.success.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(AppShapes.radiusFull),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: activeId == null
                              ? AppColors.muted
                              : AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'الاشتراك ثابت بالترم — اشتراك مستقل لكل مادة داخل الترم النشط.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AcademicPeriodsScreen(user: user),
                    ),
                  ),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('بدء / إنهاء الترم'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  final String planLabel;
  final int enabledCount;
  final int totalCount;

  const _PlanSummaryCard({
    required this.planLabel,
    required this.enabledCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(planLabel,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    '$enabledCount من $totalCount ميزة مفعّلة',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.verified_outlined, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final _FeatureSection section;
  final Map<String, Map<String, dynamic>> valuesByKey;
  final Set<String> pending;
  final bool isTeacher;
  final void Function(_FeatureDef def, bool enabled) onToggle;
  final void Function(_FeatureDef def) onEditValue;

  const _SectionCard({
    super.key,
    required this.section,
    required this.valuesByKey,
    required this.pending,
    required this.isTeacher,
    required this.onToggle,
    required this.onEditValue,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(section.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            const Divider(height: 1),
            for (final def in section.features)
              _FeatureRow(
                def: def,
                data: valuesByKey[def.key],
                isPending: pending.contains(def.key),
                locked: !isTeacher &&
                    _teacherOnlyFeatures.contains(def.key),
                onToggle: (enabled) => onToggle(def, enabled),
                onEditValue: () => onEditValue(def),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final _FeatureDef def;
  final Map<String, dynamic>? data;
  final bool isPending;

  /// Teacher-only key opened by an Admin: switch + value editor locked.
  final bool locked;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEditValue;

  const _FeatureRow({
    required this.def,
    required this.data,
    required this.isPending,
    required this.locked,
    required this.onToggle,
    required this.onEditValue,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = data?['enabled'] == true;
    final rawValue = data?['value'] ?? data?['feature_value'];
    final valueText = rawValue?.toString();

    return Column(
      children: [
        ListTile(
          dense: true,
          title: Text(def.label, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            locked ? '${def.key} · للمعلم فقط' : def.key,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          trailing: isPending
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : locked
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outlined,
                            size: 18, color: AppColors.muted),
                        SizedBox(width: 6),
                        Text('للمعلم فقط',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 12)),
                      ],
                    )
                  : CupertinoSwitch(
                      value: enabled,
                      activeTrackColor: AppColors.success,
                      onChanged: onToggle,
                    ),
        ),
        if (def.kind != _ValueKind.toggle)
          Padding(
            padding: const EdgeInsetsDirectional.only(
                start: 16, end: 16, bottom: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: InkWell(
                onTap: locked ? null : onEditValue,
                borderRadius:
                    BorderRadius.circular(AppShapes.radiusSmall),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.itemSurface,
                    borderRadius:
                        BorderRadius.circular(AppShapes.radiusSmall),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          locked
                              ? Icons.lock_outlined
                              : Icons.edit_outlined,
                          size: 14),
                      const SizedBox(width: 6),
                      Text(
                        (valueText?.isEmpty ?? true)
                            ? 'تحديد القيمة'
                            : 'القيمة: $valueText',
                        style: const TextStyle(fontSize: 12),
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
}

class _PlansFootnote extends StatelessWidget {
  const _PlansFootnote();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ملاحظات ثابتة للخطط',
                style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text(
              '• كل مادة لها اشتراك مستقل — تغيير الخطة هنا يطبق على كل الاشتراكات الجديدة لهذه الخطة.\n'
              '• تحديد المشاهدة كل 24 ساعة: يُفعّل/يُلغى لكل خطة على حدة من قسم Video & Media.\n'
              '• Guest: الدقائق تُضبط لكل محاضرة من إدارة المحاضرات.\n'
              '• الفرق بين Pro و Max الوحيد المعتمد: عدد الأجهزة + التحميل الأوفلاين.',
              style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.8),
            ),
          ],
        ),
      ),
    );
  }
}
