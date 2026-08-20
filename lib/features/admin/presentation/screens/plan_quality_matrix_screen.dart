import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class PlanQualityMatrixScreen extends StatelessWidget {
  const PlanQualityMatrixScreen({super.key});

  static const qualities = <({String key, String label})>[
    (key: '144p', label: '144p'),
    (key: '240p', label: '240p'),
    (key: '360p', label: '360p'),
    (key: '480p', label: '480p'),
    (key: '720p', label: '720p'),
    (key: '1080p', label: '1080p'),
    (key: '1440p', label: '1440p'),
    (key: '4k', label: '4K'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('جودات الفيديو حسب الخطة')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('plans').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل الخطط حالياً.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('لا توجد خطط مسجلة.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            itemCount: snapshot.data!.docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final plan = snapshot.data!.docs[index];
              final data = plan.data();
              return _PlanQualityCard(
                planId: plan.id,
                title: (data['name'] ?? data['title'] ?? plan.id).toString(),
              );
            },
          );
        },
      ),
    );
  }
}

class _PlanQualityCard extends StatefulWidget {
  final String planId;
  final String title;

  const _PlanQualityCard({required this.planId, required this.title});

  @override
  State<_PlanQualityCard> createState() => _PlanQualityCardState();
}

class _PlanQualityCardState extends State<_PlanQualityCard> {
  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
  final _pending = <String>{};

  Future<void> _setQuality(String quality, bool enabled) async {
    setState(() => _pending.add(quality));
    try {
      await _functions.httpsCallable('setPlanQualityFeature').call({
        'planId': widget.planId,
        'quality': quality,
        'enabled': enabled,
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'تعذر حفظ الجودة.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pending.remove(quality));
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = _firestore
        .collection('plan_features')
        .where('plan_id', isEqualTo: widget.planId)
        .snapshots();
    return Card(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: features,
        builder: (context, snapshot) {
          final enabled = {
            for (final doc
                in snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              if (doc.data()['enabled'] == true)
                (doc.data()['feature_key'] ?? '').toString().replaceFirst(
                  'video.quality.',
                  '',
                ),
          };
          return ExpansionTile(
            title: Text(widget.title),
            subtitle: const Text('جودات الفيديو المتاحة للمشتركين'),
            children: [
              for (final quality in PlanQualityMatrixScreen.qualities)
                ListTile(
                  title: Text(quality.label),
                  trailing: _pending.contains(quality.key)
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : CupertinoSwitch(
                          value: enabled.contains(quality.key),
                          activeTrackColor: AppColors.primary,
                          onChanged: (value) => _setQuality(quality.key, value),
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}
