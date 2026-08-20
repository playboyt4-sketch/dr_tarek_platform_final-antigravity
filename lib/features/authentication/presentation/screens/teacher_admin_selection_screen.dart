import 'package:flutter/material.dart';

class TeacherAdminSelectionScreen extends StatelessWidget {
  const TeacherAdminSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF7),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AdminUserTile(
                  name: 'Tarek el araby',
                  badge: 'DR',
                  onTap: () {},
                ),
                const SizedBox(height: 14),
                _AdminUserTile(
                  name: 'yusef khalid',
                  badge: 'ADMIN',
                  onTap: () {},
                ),
                const SizedBox(height: 14),
                _AdminUserTile(
                  name: 'Omnia gamal',
                  badge: 'ADMIN',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminUserTile extends StatelessWidget {
  final String name;
  final String badge;
  final VoidCallback onTap;

  const _AdminUserTile({
    required this.name,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 50,
          width: double.infinity,
          padding: const EdgeInsets.only(left: 18, right: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                spreadRadius: 0,
                offset: Offset(0, 7),
                color: Color(0x22000000),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF9A9A9A),
                  ),
                ),
              ),
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF168CF0),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
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
