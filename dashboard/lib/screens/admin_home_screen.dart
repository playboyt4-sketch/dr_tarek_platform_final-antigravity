import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});
  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _index = 0;

  Future<void> _callFn(String name, Map<String, dynamic> data) async {
    try {
      await FirebaseFunctions.instance.httpsCallable(name).call(data);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم بنجاح')));
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final pages = [
      _StudentsTab(callFn: _callFn),
      _AuditTab(),
      _PeriodsTab(callFn: _callFn),
      _SubjectsTab(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text('Dr Tarek Admin — ${user?.uid.substring(0, 8) ?? ""}'), actions: [
        IconButton(icon: Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
      ]),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people), label: 'الطلاب'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'التدقيق'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'الفترات'),
          NavigationDestination(icon: Icon(Icons.book), label: 'المواد'),
        ],
      ),
    );
  }
}

class _StudentsTab extends StatelessWidget {
  final void Function(String, Map<String, dynamic>) callFn;
  const _StudentsTab({required this.callFn});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance.collection('users').where('role', whereIn: ['student', 'new_student']);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('لا يوجد طلاب'));
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final approved = d['approval_status'] == 'approved';
            return Card(
              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: Icon(approved ? Icons.check_circle : Icons.pending, color: approved ? Colors.green : Colors.orange),
                title: Text(d['full_name'] ?? 'طالب'),
                subtitle: Text('${d['phone_number'] ?? ''} • ${d['grade'] ?? ''} • ${approved ? "معتمد" : "بانتظار"}'),
                trailing: approved
                    ? PopupMenuButton<String>(onSelected: (v) {
                        if (v == 'reset') _showResetDialog(context, docs[i].id);
                      }, itemBuilder: (_) => [PopupMenuItem(value: 'reset', child: Text('إعادة تعيين كلمة المرور'))])
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        FilledButton(onPressed: () => callFn('approveStudent', {'studentId': docs[i].id, 'studentType': 'center_student', 'subjectAccess': []}), child: Text('اعتماد')),
                      ]),
              ),
            );
          },
        );
      },
    );
  }

  void _showResetDialog(BuildContext ctx, String studentId) {
    final ctrl = TextEditingController();
    showDialog(context: ctx, builder: (c) => AlertDialog(
      title: Text('إعادة تعيين كلمة المرور'),
      content: TextField(controller: ctrl, obscureText: true, decoration: InputDecoration(labelText: 'كلمة مرور مؤقتة (8+ أحرف معقدة)'), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text('إلغاء')),
        FilledButton(onPressed: () async {
          // Create reset request doc then approve it.
          final db = FirebaseFirestore.instance;
          final reqRef = await db.collection('password_reset_requests').add({
            'student_id': studentId,
            'status': 'pending',
            'created_at': FieldValue.serverTimestamp(),
          });
          await Future.delayed(Duration(seconds: 1));
          try {
            await FirebaseFunctions.instance.httpsCallable('onPasswordResetApproved').call({'requestId': reqRef.id, 'newPassword': ctrl.text});
            if (ctx.mounted) { Navigator.pop(c); ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('تم إعادة التعيين'))); }
          } on FirebaseFunctionsException catch (e) {
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message ?? e.code), backgroundColor: Colors.red));
          }
        }, child: Text('تأكيد')),
      ],
    ));
  }
}

class _AuditTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance.collection('admin_audit_log').orderBy('created_at', descending: true).limit(100);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('لا يوجد سجل تدقيق'));
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final ts = (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
            return ListTile(
              dense: true,
              leading: Icon(Icons.history, size: 20),
              title: Text(d['action'] ?? ''),
              subtitle: Text('${d['actor_role'] ?? ''} → ${d['target_id'] ?? ''}'),
              trailing: Text('${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 11)),
            );
          },
        );
      },
    );
  }
}

class _PeriodsTab extends StatelessWidget {
  final void Function(String, Map<String, dynamic>) callFn;
  const _PeriodsTab({required this.callFn});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('academic_periods').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        return ListView(
          padding: EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              icon: Icon(Icons.add),
              label: Text('تهيئة الفترات الأساسية'),
              onPressed: () => callFn('initializeAcademicPeriods', {}),
            ),
            ...docs.map((doc) {
              final d = doc.data();
              final active = d['status'] == 'active';
              return Card(child: SwitchListTile(
                title: Text(d['label'] ?? doc.id),
                subtitle: Text(active ? 'نشطة' : 'منتهية'),
                value: active,
                onChanged: (v) => callFn('setAcademicPeriodStatus', {'periodId': doc.id, 'status': v ? 'active' : 'ended'}),
              ));
            }),
          ],
        );
      },
    );
  }
}

class _SubjectsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('subjects').where('is_deleted', isEqualTo: false).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        return ListView(padding: EdgeInsets.all(16), children: [
          FilledButton.icon(icon: Icon(Icons.add), label: Text('إضافة مادة'), onPressed: () => _addSubject(context)),
          ...docs.map((doc) => Card(child: ListTile(
            title: Text(doc.data()['title'] ?? doc.id),
            subtitle: Text(doc.data()['description'] ?? ''),
            trailing: IconButton(icon: Icon(Icons.delete_outline), onPressed: () {
              FirebaseFunctions.instance.httpsCallable('deleteSubject').call({'subjectId': doc.id});
            }),
          ))),
        ]);
      },
    );
  }

  void _addSubject(BuildContext ctx) {
    final title = TextEditingController();
    showDialog(context: ctx, builder: (c) => AlertDialog(
      title: Text('مادة جديدة'),
      content: TextField(controller: title, decoration: InputDecoration(labelText: 'عنوان المادة'), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text('إلغاء')),
        FilledButton(onPressed: () async {
          if (title.text.trim().isEmpty) return;
          try {
            await FirebaseFunctions.instance.httpsCallable('createSubject').call({'title': title.text.trim(), 'description': '', 'displayOrder': 0});
            if (ctx.mounted) Navigator.pop(c);
          } on FirebaseFunctionsException catch (e) {
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
          }
        }, child: Text('حفظ')),
      ],
    ));
  }
}
