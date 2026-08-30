import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_messages.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../core/widgets/password_strength_meter.dart';
import '../providers/auth_provider.dart';

class StudentRegistrationWizard extends ConsumerStatefulWidget {
  const StudentRegistrationWizard({super.key});

  @override
  ConsumerState<StudentRegistrationWizard> createState() =>
      _StudentRegistrationWizardState();
}

class _StudentRegistrationWizardState
    extends ConsumerState<StudentRegistrationWizard> {
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  int _step = 0;
  String? _selectedGrade;
  String? _selectedCustomGroupId;
  String? _selectedCustomGroupName;
  bool _submitted = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  File? _photoFile;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _next() {
    final error = _validateStep();
    if (error != null) {
      _showError(error);
      return;
    }
    setState(() => _step += 1);
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step -= 1);
  }

  InputDecoration _stepInputDecoration({
    required String label,
    required String hint,
    Widget? suffixIcon,
  }) {
    final rs = context.rs;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: EdgeInsets.symmetric(horizontal: rs(16), vertical: rs(20)),
      suffixIcon: suffixIcon,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(rs(12)),
        borderSide: const BorderSide(color: Color(0xFFD0D0D0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(rs(12)),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
    );
  }

  String? _validateStep() {
    switch (_step) {
      case 0:
        if (_fullNameController.text.trim().isEmpty) {
          return 'يرجى إدخال الاسم بالكامل.';
        }
        if (_fullNameController.text.trim().length > 100) {
          return 'الاسم يجب ألا يتجاوز 100 حرف.';
        }
      case 1:
        final phone = _phoneController.text.trim();
        if (!RegExp(r'^01[0125][0-9]{8}$').hasMatch(phone)) {
          return 'يرجى إدخال رقم هاتف مصري صحيح (مثال: 01001234567).';
        }
      case 3:
        if (_selectedGrade == null) {
          return 'يرجى اختيار الفرقة الدراسية.';
        }
      case 4:
        final password = _passwordController.text;
        if (password.length < 8) {
          return 'كلمة المرور يجب أن تتكون من 8 أحرف على الأقل.';
        }
        final hasUpper = password.contains(RegExp(r'[A-Z]'));
        final hasLower = password.contains(RegExp(r'[a-z]'));
        final hasDigit = password.contains(RegExp(r'[0-9]'));
        final hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>\-_+=\[\]/\\`~]'));
        if (!hasUpper || !hasLower || !hasDigit || !hasSpecial) {
          return 'كلمة المرور يجب أن تحتوي على حرف كبير، حرف صغير، رقم، ورمز خاص.';
        }
        if (_passwordController.text != _confirmPasswordController.text) {
          return 'كلمتا المرور غير متطابقتين.';
        }
    }
    return null;
  }

  /// Loads ACTIVE custom groups through the authorized callable.
  /// Direct Firestore reads of `custom_groups` are denied server-side;
  /// the callable exposes only {id, name, grade} of active groups.
  Future<List<Map<String, String>>> _loadActiveGroups() async {
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('getActiveCustomGroups');
      final result = await callable.call<Map<String, dynamic>>();
      final list = result.data['groups'] as List<dynamic>? ?? [];
      return list
          .whereType<Map<dynamic, dynamic>>()
          .map((item) => <String, String>{
            'id': item['id']?.toString() ?? '',
            'name': item['name']?.toString() ?? '',
            'grade': item['grade']?.toString() ?? '',
          })
          .where((group) => group['id']!.isNotEmpty)
          .toList();
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  Future<void> _submit() async {
    final error = _validateStep();
    if (error != null) {
      _showError(error);
      return;
    }

    await ref
        .read(authProvider.notifier)
        .register(
          fullName: _fullNameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          grade: _selectedGrade!,
          customGroupId: _selectedCustomGroupId,
          customGroupName: _selectedCustomGroupName,
          password: _passwordController.text,
        );

    if (!mounted) return;
    final state = ref.read(authProvider);
    if (!state.hasError) {
      setState(() => _submitted = true);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
      ));
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          _photoFile = File(picked.path);
        });
      }
    } catch (e) {
      _showError('فشل في اختيار الصورة الشخصية: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final rs = context.rs;
    if (_submitted) return const _RegistrationSubmittedView();

    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: _back,
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
        title: Text(
          'خطوة ${_step + 1} من 5',
          style: TextStyle(
            color: Colors.black,
            fontSize: rs(18),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
              child: LinearProgressIndicator(
                value: (_step + 1) / 5,
                backgroundColor: const Color(0xFFE0E4EA),
                color: const Color(0xFF2563EB),
                minHeight: rs(6),
                borderRadius: BorderRadius.circular(rs(3)),
              ),
            ),
            SizedBox(height: rs(16)),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: context.contentMaxWidth),
                  child: _buildStep(),
                ),
              ),
            ),
            if (authState.hasError) ...[
              Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: context.pagePadding),
                child: Text(
                  _friendlyError(authState.error),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                    fontSize: rs(14),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            Padding(
              padding: EdgeInsets.all(context.pagePadding),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: context.contentMaxWidth),
                child: Row(
                  children: [
                    if (_step > 0) ...[
                      Expanded(
                        child: SizedBox(
                          height: rs(60),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: Color(0xFFD0D0D0)),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(rs(12)),
                              ),
                            ),
                            onPressed:
                                authState.isLoading ? null : _back,
                            child: Text(
                              'السابق',
                              style: TextStyle(
                                fontSize: rs(18),
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: rs(12)),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: rs(60),
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(rs(12)),
                            ),
                          ),
                          onPressed: authState.isLoading
                              ? null
                              : (_step == 4 ? _submit : _next),
                          child: authState.isLoading
                              ? SizedBox(
                                  height: rs(24),
                                  width: rs(24),
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _step == 4 ? 'Finish' : 'Next',
                                  style: TextStyle(
                                    fontSize: rs(20),
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _RegistrationStepLayout(
          imagePath: 'assets/images/New Student - name.png',
          title: 'ما هو اسمك بالكامل؟',
          subtitle: 'أدخل اسمك الثلاثي أو الرباعي كما هو مدون في الأوراق الرسمية.',
          child: TextField(
            controller: _fullNameController,
            autofocus: true,
            style: TextStyle(fontSize: context.rs(18), color: Colors.black),
            decoration: _stepInputDecoration(
              label: 'Full Name',
              hint: 'Enter your full name',
            ),
          ),
        );
      case 1:
        return _RegistrationStepLayout(
          imagePath: 'assets/images/New Student - number.png',
          title: 'ما هو رقم هاتفك؟',
          subtitle: 'سيتم استخدام رقم الهاتف لتسجيل الدخول إلى حسابك.',
          child: TextField(
            controller: _phoneController,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: context.rs(18), color: Colors.black),
            decoration: _stepInputDecoration(
              label: 'phone number',
              hint: 'Enter your phone number',
            ),
          ),
        );
      case 2:
        return _RegistrationStepLayout(
          imagePath: 'assets/images/New Student - add a photo.png',
          title: 'الصورة الشخصية',
          subtitle: 'يمكنك إضافة صورتك الشخصية هنا أو لاحقاً من الملف الشخصي.',
          child: Center(
            child: Stack(
              children: [
                Container(
                  width: context.rs(150),
                  height: context.rs(150),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFD0D0D0), width: 1),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x11000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      )
                    ],
                  ),
                  child: ClipOval(
                    child: _photoFile != null
                        ? Image.file(_photoFile!, fit: BoxFit.cover)
                        : Icon(Icons.person, size: context.rs(76), color: const Color(0xFF9A9A9A)),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: context.rs(44),
                    height: context.rs(44),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.add_a_photo_outlined, color: Colors.white, size: context.rs(20)),
                      onPressed: _pickImage,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case 3:
        return _RegistrationStepLayout(
          imagePath: 'assets/images/New Student - grade.png',
          title: 'الفرقة والمجموعة',
          subtitle: 'اختر فرقتك الدراسية والمجموعة المخصصة إن وجدت.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GradeRadioGroup(
                selectedGrade: _selectedGrade,
                onChanged: (val) => setState(() => _selectedGrade = val),
              ),
              SizedBox(height: context.rs(24)),
              FutureBuilder<List<Map<String, String>>>(
                future: _loadActiveGroups(),
                builder: (context, snapshot) {
                  final groups = snapshot.data ?? const <Map<String, String>>[];
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedCustomGroupId,
                    decoration: InputDecoration(
                      labelText: 'المجموعة المخصصة (اختياري)',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: context.rs(16),
                        vertical: context.rs(14),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(context.rs(12)),
                        borderSide:
                            const BorderSide(color: Color(0xFFD0D0D0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(context.rs(12)),
                        borderSide: const BorderSide(
                            color: Color(0xFF2563EB), width: 1.5),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('بدون مجموعة خاصة (عام)'),
                      ),
                      ...groups.map(
                        (group) => DropdownMenuItem<String>(
                          value: group['id'],
                          child: Text(group['name'] ?? ''),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCustomGroupId = value;
                        if (value == null) {
                          _selectedCustomGroupName = null;
                        } else {
                          final match = groups.where((g) => g['id'] == value);
                          _selectedCustomGroupName = match.isNotEmpty
                              ? match.first['name']
                              : null;
                        }
                      });
                    },
                  );
                },
              ),
            ],
          ),
        );
      case 4:
        return _RegistrationStepLayout(
          imagePath: 'assets/images/New Student - password.png',
          title: 'تعيين كلمة المرور',
          subtitle: 'يجب أن تتبع كلمة المرور سياسة الأمان الموضحة أدناه.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: context.rs(18), color: Colors.black),
                decoration: _stepInputDecoration(
                  label: 'كلمة المرور',
                  hint: 'Enter password',
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: const Color(0xFF9A9A9A),
                    ),
                  ),
                ),
              ),
              SizedBox(height: context.rs(8)),
              PasswordStrengthMeter(password: _passwordController.text),
              SizedBox(height: context.rs(16)),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmation,
                style: TextStyle(fontSize: context.rs(18), color: Colors.black),
                decoration: _stepInputDecoration(
                  label: 'تأكيد كلمة المرور',
                  hint: 'Re-Enter password',
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _obscureConfirmation = !_obscureConfirmation,
                    ),
                    icon: Icon(
                      _obscureConfirmation
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: const Color(0xFF9A9A9A),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  String _friendlyError(Object? error) {
    if (error == null) {
      return failureMessage(
        AppLocalizations.of(context),
        FailureCode.unknown,
      );
    }
    return failureMessage(
      AppLocalizations.of(context),
      Failure.from(error).code,
    );
  }
}

class _RegistrationStepLayout extends StatelessWidget {
  final String imagePath;
  final Widget child;
  final String title;
  final String? subtitle;

  const _RegistrationStepLayout({
    required this.imagePath,
    required this.child,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero Image
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: rs(260),
              ),
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return SizedBox(
                    height: rs(150),
                    child: Icon(Icons.image_outlined,
                        size: rs(64), color: const Color(0xFF9A9A9A)),
                  );
                },
              ),
            ),
          ),
          SizedBox(height: rs(20)),
          // Step title & subtitle
          Padding(
            padding:
                EdgeInsets.symmetric(horizontal: context.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: rs(22),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: rs(4)),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: rs(13),
                      color: const Color(0xFF9A9A9A),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: rs(20)),
          // Form child
          Padding(
            padding:
                EdgeInsets.symmetric(horizontal: context.pagePadding),
            child: child,
          ),
          SizedBox(height: rs(20)),
        ],
      ),
    );
  }
}

class _GradeRadioGroup extends StatelessWidget {
  final String? selectedGrade;
  final ValueChanged<String> onChanged;

  const _GradeRadioGroup({
    required this.selectedGrade,
    required this.onChanged,
  });

  static const _grades = [
    {'key': 'grade_one', 'label': 'الفرقة الأولى'},
    {'key': 'grade_two', 'label': 'الفرقة الثانية'},
    {'key': 'grade_three', 'label': 'الفرقة الثالثة'},
    {'key': 'grade_four', 'label': 'الفرقة الرابعة'},
  ];

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(rs(12)),
        border: Border.all(color: const Color(0xFFD0D0D0), width: 1),
      ),
      child: Column(
        children: _grades.map((grade) {
          final isSelected = selectedGrade == grade['key'];
          return InkWell(
            onTap: () => onChanged(grade['key']!),
            borderRadius: BorderRadius.circular(rs(12)),
            child: Container(
              height: rs(52),
              padding: EdgeInsets.symmetric(horizontal: rs(16)),
              decoration: BoxDecoration(
                border: grade['key'] != 'grade_four'
                    ? Border(bottom: BorderSide(color: Color(0xFFEFEFEF), width: 1))
                    : null,
              ),
              child: Row(
                children: [
                  // Custom Radio Button
                  Container(
                    width: rs(22),
                    height: rs(22),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFD0D0D0),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Center(
                            child: Container(
                              width: rs(12),
                              height: rs(12),
                              decoration: const BoxDecoration(
                                color: Color(0xFF2563EB),
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
                  SizedBox(width: rs(16)),
                  Text(
                    grade['label']!,
                    style: TextStyle(
                      fontSize: rs(16),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: const Color(0xFF1E1E1E),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _RegistrationSubmittedView extends StatelessWidget {
  const _RegistrationSubmittedView();

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF7),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.pagePadding,
              vertical: context.pagePadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: rs(20)),
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: rs(360),
                    ),
                    child: Image.asset(
                      'assets/images/New Student - end.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return SizedBox(
                          height: rs(190),
                          child: Icon(Icons.mark_email_read_outlined, size: rs(84), color: Colors.green),
                        );
                      },
                    ),
                  ),
                ),
                SizedBox(height: rs(24)),
                Text(
                  'الطلب قيد المراجعة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: rs(24),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: rs(12)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: rs(16)),
                  child: Text(
                    'تم إرسال طلب تسجيلك بنجاح. ستتمكن من تسجيل الدخول فور اعتماد حسابك وتعيين موادك من قِبل إدارة المنصة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: rs(15),
                      height: 1.5,
                      color: const Color(0xFF424242),
                    ),
                  ),
                ),
                SizedBox(height: rs(48)),
                SizedBox(
                  width: double.infinity,
                  height: rs(60),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(rs(12)),
                      ),
                    ),
                    onPressed: () =>
                        Navigator.of(context).popUntil((route) => route.isFirst),
                    child: Text(
                      'العودة للبداية',
                      style: TextStyle(
                        fontSize: rs(18),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: rs(24)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
