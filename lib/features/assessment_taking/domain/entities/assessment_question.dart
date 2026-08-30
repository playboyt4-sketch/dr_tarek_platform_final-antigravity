class AssessmentQuestion {
  final String id;
  final String type; // 'mcq', 'true-false'
  final String text;
  final List<String> options;
  final int marks;

  const AssessmentQuestion({
    required this.id,
    required this.type,
    required this.text,
    required this.options,
    required this.marks,
  });

  factory AssessmentQuestion.fromMap(Map<String, dynamic> map) {
    return AssessmentQuestion(
      id: map['id'] as String? ?? '',
      type: map['type'] as String? ?? 'mcq',
      text: map['text'] as String? ?? '',
      options: List<String>.from(map['options'] ?? const []),
      marks: (map['marks'] as num?)?.toInt() ?? 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssessmentQuestion &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          text == other.text &&
          marks == other.marks;

  @override
  int get hashCode =>
      id.hashCode ^ type.hashCode ^ text.hashCode ^ marks.hashCode;
}
