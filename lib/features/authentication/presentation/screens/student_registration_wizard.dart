import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  static const _grades = <String, String>{
    'grade_one': 'الفرقة الأولى',
    'grade_two': 'الفرقة الثانية',
    'grade_three': 'الفرقة الثالثة',
    'grade_four': 'الفرقة الرابعة',
  };

  int _step = 0;
  String? _selectedGrade;
  String? _selectedCustomGroupId;
  String? _selectedCustomGroupName;
  bool _submitted = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

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
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    if (_submitted) return const _RegistrationSubmittedView();

    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text('خطوة ${_step + 1} من 5'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: (_step + 1) / 5),
                  const SizedBox(height: 32),
                  Expanded(child: _buildStep()),
                  if (authState.hasError) ...[
                    const SizedBox(height: 12),
                    Text(
                      _friendlyError(authState.error),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_step > 0) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: authState.isLoading ? null : _back,
                            child: const Text('السابق'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton(
                          onPressed: authState.isLoading
                              ? null
                              : (_step == 4 ? _submit : _next),
                          child: authState.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_step == 4 ? 'إرسال الطلب' : 'التالي'),
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

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _StepLayout(
          title: 'ما هو اسمك بالكامل؟',
          subtitle: 'أدخل اسمك الثلاثي أو الرباعي كما هو مدون في الأوراق الرسمية.',
          child: TextField(
            controller: _fullNameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'الاسم بالكامل',
              border: OutlineInputBorder(),
            ),
          ),
        );
      case 1:
        return _StepLayout(
          title: 'ما هو رقم هاتفك؟',
          subtitle: 'سيتم استخدام رقم الهاتف لتسجيل الدخول إلى حسابك.',
          child: TextField(
            controller: _phoneController,
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف المصري',
              hintText: '01001234567',
              border: OutlineInputBorder(),
            ),
          ),
        );
      case 2:
        return const _StepLayout(
          title: 'الصورة الشخصية',
          subtitle: 'يمكنك إضافة صورتك الشخصية لاحقاً من الملف الشخصي.',
          child: Center(
            child: CircleAvatar(
              radius: 48,
              child: Icon(Icons.person, size: 48),
            ),
          ),
        );
      case 3:
        return _StepLayout(
          title: 'الفرقة والمجموعة',
          subtitle: 'اختر فرقتك الدراسية والمجموعة إن وجدت.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedGrade,
                decoration: const InputDecoration(
                  labelText: 'الفرقة الدراسية',
                  border: OutlineInputBorder(),
                ),
                items: _grades.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedGrade = value),
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('custom_groups')
                    .where('is_active', isEqualTo: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedCustomGroupId,
                    decoration: const InputDecoration(
                      labelText: 'المجموعة المخصصة (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('بدون مجموعة خاصة (عام)'),
                      ),
                      ...docs.map(
                        (doc) => DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(
                            (doc.data()['name'] as String?) ?? doc.id,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCustomGroupId = value;
                        if (value == null) {
                          _selectedCustomGroupName = null;
                        } else {
                          final match = docs.where((d) => d.id == value);
                          _selectedCustomGroupName = match.isNotEmpty
                              ? match.first.data()['name'] as String?
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
        return _StepLayout(
          title: 'تعيين كلمة المرور',
          subtitle: 'يجب أن تتبع كلمة المرور سياسة الأمان الموضحة أدناه.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              PasswordStrengthMeter(password: _passwordController.text),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmation,
                decoration: InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _obscureConfirmation = !_obscureConfirmation,
                    ),
                    icon: Icon(
                      _obscureConfirmation
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
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
    final raw = error?.toString() ?? 'Registration failed.';
    return raw.replaceFirst('Exception: ', '');
  }
}

class _StepLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _StepLayout({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(subtitle),
          const SizedBox(height: 32),
          child,
        ],
      ),
    );
  }
}

class _RegistrationSubmittedView extends StatelessWidget {
  const _RegistrationSubmittedView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF7),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 88),
                const SizedBox(height: 24),
                Text(
                  'الطلب قيد المراجعة',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'تم إرسال طلب تسجيلك بنجاح. ستتمكن من تسجيل الدخول فور اعتماد حسابك وتعيين موادك من قِبل إدارة المنصة.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  child: const Text('العودة للبداية'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
