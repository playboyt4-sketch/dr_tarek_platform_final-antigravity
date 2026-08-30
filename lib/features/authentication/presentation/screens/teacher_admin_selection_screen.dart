import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure_messages.dart';
import '../../../../core/responsive/responsive.dart';
import '../../domain/repositories/auth_repository.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'staff_password_screen.dart';

/// Riverpod provider for the pre-login staff directory (owner + admins).
final staffDirectoryProvider = FutureProvider.autoDispose<List<StaffDirectoryEntryEntity>>(
  (ref) => ref.watch(authRepositoryProvider).listStaffDirectory(),
);


/// Pre-login staff entry gate.
///
/// Lists the ACTIVE platform staff (owner "DR" + admins) from the backend
/// directory. Accounts are provisioned by the owner from the dashboard —
/// a name that is not in the directory has no access at all.
/// Firestore rules intentionally deny `users` reads pre-auth
/// (anti-enumeration), so this screen uses the `listStaffDirectory`
/// callable which exposes only display names + role kind.
class TeacherAdminSelectionScreen extends ConsumerWidget {
  const TeacherAdminSelectionScreen({super.key});

  static const Color backgroundColor = Color(0xFFFFFCF7);
  static const Color accentBlue = Color(0xFF2563EB);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rs = context.rs;
    final staffAsync = ref.watch(staffDirectoryProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
        title: Text(
          'إدارة المنصة',
          style: TextStyle(
            color: Colors.black,
            fontSize: rs(20),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(context.pagePadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: rs(24)),
                  CircleAvatar(
                    radius: rs(50),
                    backgroundColor: Colors.white,
                    child: Padding(
                      padding: EdgeInsets.all(rs(8)),
                      child: Image.asset(
                        'assets/images/teacher & admin icone.png',
                        width: rs(60),
                        height: rs(60),
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.admin_panel_settings_outlined,
                          size: rs(50),
                          color: accentBlue,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: rs(32)),
                  staffAsync.when(
                    loading: () => SizedBox(
                      height: rs(80),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: accentBlue,
                        ),
                      ),
                    ),
                    error: (error, _) => Column(
                      children: [
                        Text(
                          friendlyErrorMessage(context, error),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: rs(14)),
                        ),
                        SizedBox(height: rs(12)),
                        TextButton.icon(
                          onPressed: () =>
                              ref.invalidate(staffDirectoryProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                        SizedBox(height: rs(16)),
                        TextButton(
                          onPressed: () => _openLogin(context),
                          child: Text(
                            'الدخول برقم الهاتف بدلاً من ذلك',
                            style: TextStyle(fontSize: rs(14)),
                          ),
                        ),
                      ],
                    ),
                    data: (staff) {
                      if (staff.isEmpty) {
                        return Column(
                          children: [
                            Text(
                              'لا توجد حسابات إدارة مفعّلة حالياً.',
                              style: TextStyle(fontSize: rs(15)),
                            ),
                            SizedBox(height: rs(16)),
                            TextButton(
                              onPressed: () => _openLogin(context),
                              child: Text(
                                'الدخول برقم الهاتف',
                                style: TextStyle(fontSize: rs(14)),
                              ),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          for (var i = 0; i < staff.length; i++) ...[
                            _AdminUserTile(entry: staff[i]),
                            if (i < staff.length - 1)
                              SizedBox(height: rs(16)),
                          ],
                        ],
                      );
                    },
                  ),
                  SizedBox(height: rs(48)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }
}

class _AdminUserTile extends StatelessWidget {
  final StaffDirectoryEntryEntity entry;

  const _AdminUserTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final isDr = entry.roleKind == 'dr';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                StaffPasswordScreen(displayName: entry.displayName),
          ),
        ),
        borderRadius: BorderRadius.circular(rs(24)),
        child: Container(
          height: rs(60),
          width: double.infinity,
          padding: EdgeInsets.only(left: rs(18), right: rs(8)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(rs(24)),
            border: Border.all(color: const Color(0xFFD0D0D0), width: 1),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                spreadRadius: 0,
                offset: Offset(0, 7),
                color: Color(0x11000000),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  entry.displayName,
                  style: TextStyle(
                    fontSize: rs(16),
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: rs(14),
                  vertical: rs(6),
                ),
                decoration: BoxDecoration(
                  color:
                      isDr ? const Color(0xFFFFC96B) : const Color(0xFFC084FC),
                  borderRadius: BorderRadius.circular(rs(16)),
                ),
                child: Text(
                  isDr ? 'DR' : 'ADMIN',
                  style: TextStyle(
                    fontSize: rs(12),
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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
