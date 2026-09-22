class Book {
  const Book({
    required this.id,
    required this.title,
    required this.pageCount,
    required this.pageOffset,
    required this.lastPrintedPage,
  });

  final String id;
  final String title;
  final int pageCount;
  final int pageOffset;
  final int lastPrintedPage;

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        pageCount: j['page_count'] as int,
        pageOffset: j['page_offset'] as int,
        lastPrintedPage: j['last_printed_page'] as int,
      );
}

/// Misol: {"number": "56", "text": "...", "answer": "..."}
class AssignmentItem {
  const AssignmentItem({required this.number, required this.text, this.answer});

  final String number;
  final String text;
  final String? answer;

  factory AssignmentItem.fromJson(Map<String, dynamic> j) => AssignmentItem(
        number: j['number'].toString(),
        text: j['text'] as String? ?? '',
        answer: j['answer'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'number': number,
        'text': text,
        if (answer != null && answer!.isNotEmpty) 'answer': answer,
      };
}

class Criterion {
  const Criterion({required this.name, required this.weight, required this.description});

  final String name;
  final int weight;
  final String description;

  factory Criterion.fromJson(Map<String, dynamic> j) => Criterion(
        name: j['name'] as String,
        weight: (j['weight'] as num).toInt(),
        description: j['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'weight': weight, 'description': description};
}

enum AssignmentStatus {
  preparing,
  review,
  published,
  failed;

  static AssignmentStatus parse(String s) => values.asNameMap()[s] ?? failed;
}

enum SourceType {
  book,
  images,
  text;

  static SourceType parse(String s) => values.asNameMap()[s] ?? text;

  String get label => switch (this) {
        SourceType.book => 'Kitob',
        SourceType.images => 'Rasm',
        SourceType.text => 'Matn',
      };
}

class SubmissionStats {
  const SubmissionStats({required this.submitted, required this.graded, required this.needsReview, required this.members});

  final int submitted;
  final int graded;
  final int needsReview;
  final int members;

  factory SubmissionStats.fromJson(Map<String, dynamic> j) => SubmissionStats(
        submitted: j['submitted'] as int,
        graded: j['graded'] as int,
        needsReview: j['needs_review'] as int,
        members: j['members'] as int,
      );
}

class Assignment {
  const Assignment({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.title,
    this.instructions,
    required this.sourceType,
    this.book,
    this.pageFrom,
    this.pageTo,
    this.problems,
    required this.items,
    required this.rubric,
    required this.imageUrls,
    this.prepareError,
    required this.status,
    required this.dueAt,
    required this.allowLate,
    required this.latePenaltyPercent,
    this.stats,
  });

  final String id;
  final String groupId;
  final String groupName;
  final String title;
  final String? instructions;
  final SourceType sourceType;
  final Book? book;
  final int? pageFrom;
  final int? pageTo;
  final String? problems;
  final List<AssignmentItem> items;
  final List<Criterion> rubric;
  final List<String> imageUrls;

  /// AI eslatmasi yoki xato matni
  final String? prepareError;
  final AssignmentStatus status;
  final DateTime dueAt;
  final bool allowLate;
  final int latePenaltyPercent;
  final SubmissionStats? stats;

  factory Assignment.fromJson(Map<String, dynamic> j) => Assignment(
        id: j['id'] as String,
        groupId: j['group_id'] as String,
        groupName: j['group_name'] as String,
        title: j['title'] as String,
        instructions: j['instructions'] as String?,
        sourceType: SourceType.parse(j['source_type'] as String),
        book: j['book'] == null ? null : Book.fromJson(j['book'] as Map<String, dynamic>),
        pageFrom: j['page_from'] as int?,
        pageTo: j['page_to'] as int?,
        problems: j['problems'] as String?,
        items: [for (final i in j['items'] as List) AssignmentItem.fromJson(i as Map<String, dynamic>)],
        rubric: [for (final c in j['rubric'] as List) Criterion.fromJson(c as Map<String, dynamic>)],
        imageUrls: [for (final u in j['image_urls'] as List) u as String],
        prepareError: j['prepare_error'] as String?,
        status: AssignmentStatus.parse(j['status'] as String),
        dueAt: DateTime.parse(j['due_at'] as String).toLocal(),
        allowLate: j['allow_late'] as bool,
        latePenaltyPercent: j['late_penalty_percent'] as int,
        stats: j['stats'] == null ? null : SubmissionStats.fromJson(j['stats'] as Map<String, dynamic>),
      );
}

enum SubmissionStatus {
  grading,
  graded,
  needsReview,
  failed;

  static SubmissionStatus parse(String s) => switch (s) {
        'grading' => grading,
        'graded' => graded,
        'needs_review' => needsReview,
        _ => failed,
      };
}

enum Verdict {
  correct,
  partial,
  incorrect,
  missing;

  static Verdict parse(String? s) => values.asNameMap()[s] ?? missing;

  String get label => switch (this) {
        Verdict.correct => "To'g'ri",
        Verdict.partial => 'Qisman',
        Verdict.incorrect => 'Xato',
        Verdict.missing => 'Topilmadi',
      };
}

class GradedItem {
  const GradedItem({required this.number, required this.verdict, required this.comment});

  final String number;
  final Verdict verdict;
  final String comment;

  factory GradedItem.fromJson(Map<String, dynamic> j) => GradedItem(
        number: j['number'].toString(),
        verdict: Verdict.parse(j['verdict'] as String?),
        comment: j['comment'] as String? ?? '',
      );
}

class Submission {
  const Submission({
    required this.id,
    required this.assignmentId,
    required this.studentId,
    required this.studentName,
    required this.status,
    required this.submittedAt,
    required this.isLate,
    required this.attempt,
    this.textAnswer,
    required this.fileUrls,
    required this.aiItems,
    this.aiConfidence,
    this.aiMatchesAssignment,
    this.feedbackStudent,
    this.noteTeacher,
    this.aiScorePercent,
    this.teacherScore,
    this.teacherComment,
    this.finalScore,
    required this.gradingScale,
  });

  final String id;
  final String assignmentId;
  final String studentId;
  final String studentName;
  final SubmissionStatus status;
  final DateTime submittedAt;
  final bool isLate;
  final int attempt;
  final String? textAnswer;
  final List<String> fileUrls;
  final List<GradedItem> aiItems;
  final double? aiConfidence;
  final bool? aiMatchesAssignment;
  final String? feedbackStudent;
  final String? noteTeacher;
  final double? aiScorePercent;
  final double? teacherScore;
  final String? teacherComment;
  final double? finalScore;
  final String gradingScale;

  bool get isFinal => status == SubmissionStatus.graded;
  int get scaleMax => int.tryParse(gradingScale) ?? 5;

  factory Submission.fromJson(Map<String, dynamic> j) => Submission(
        id: j['id'] as String,
        assignmentId: j['assignment_id'] as String,
        studentId: j['student_id'] as String,
        studentName: j['student_name'] as String,
        status: SubmissionStatus.parse(j['status'] as String),
        submittedAt: DateTime.parse(j['submitted_at'] as String).toLocal(),
        isLate: j['is_late'] as bool,
        attempt: j['attempt'] as int,
        textAnswer: j['text_answer'] as String?,
        fileUrls: [for (final u in j['file_urls'] as List) u as String],
        aiItems: [for (final i in j['ai_items'] as List) GradedItem.fromJson(i as Map<String, dynamic>)],
        aiConfidence: (j['ai_confidence'] as num?)?.toDouble(),
        aiMatchesAssignment: j['ai_matches_assignment'] as bool?,
        feedbackStudent: j['feedback_student'] as String?,
        noteTeacher: j['note_teacher'] as String?,
        aiScorePercent: (j['ai_score_percent'] as num?)?.toDouble(),
        teacherScore: (j['teacher_score'] as num?)?.toDouble(),
        teacherComment: j['teacher_comment'] as String?,
        finalScore: (j['final_score'] as num?)?.toDouble(),
        gradingScale: j['grading_scale'] as String,
      );
}

class StudentAssignment {
  const StudentAssignment({
    required this.id,
    required this.groupName,
    required this.subject,
    required this.teacherName,
    required this.title,
    this.instructions,
    required this.sourceType,
    required this.items,
    required this.rubric,
    required this.imageUrls,
    this.bookTitle,
    this.pageFrom,
    this.pageTo,
    this.problems,
    required this.dueAt,
    required this.allowLate,
    required this.latePenaltyPercent,
    required this.gradingScale,
    this.submission,
  });

  final String id;
  final String groupName;
  final String subject;
  final String teacherName;
  final String title;
  final String? instructions;
  final SourceType sourceType;
  final List<AssignmentItem> items;
  final List<Criterion> rubric;
  final List<String> imageUrls;
  final String? bookTitle;
  final int? pageFrom;
  final int? pageTo;
  final String? problems;
  final DateTime dueAt;
  final bool allowLate;
  final int latePenaltyPercent;
  final String gradingScale;
  final Submission? submission;

  bool get isOverdue => DateTime.now().isAfter(dueAt);
  bool get canSubmit => submission == null && (!isOverdue || allowLate);

  factory StudentAssignment.fromJson(Map<String, dynamic> j) => StudentAssignment(
        id: j['id'] as String,
        groupName: j['group_name'] as String,
        subject: j['subject'] as String,
        teacherName: j['teacher_name'] as String,
        title: j['title'] as String,
        instructions: j['instructions'] as String?,
        sourceType: SourceType.parse(j['source_type'] as String),
        items: [for (final i in j['items'] as List) AssignmentItem.fromJson(i as Map<String, dynamic>)],
        rubric: [for (final c in j['rubric'] as List) Criterion.fromJson(c as Map<String, dynamic>)],
        imageUrls: [for (final u in j['image_urls'] as List) u as String],
        bookTitle: j['book_title'] as String?,
        pageFrom: j['page_from'] as int?,
        pageTo: j['page_to'] as int?,
        problems: j['problems'] as String?,
        dueAt: DateTime.parse(j['due_at'] as String).toLocal(),
        allowLate: j['allow_late'] as bool,
        latePenaltyPercent: j['late_penalty_percent'] as int,
        gradingScale: j['grading_scale'] as String,
        submission: j['submission'] == null ? null : Submission.fromJson(j['submission'] as Map<String, dynamic>),
      );
}

/// "34–35-betlar · 56–60-misollar"
String bookRangeLabel({String? bookTitle, int? pageFrom, int? pageTo, String? problems}) {
  final parts = <String>[];
  if (pageFrom != null) parts.add(pageFrom == pageTo ? '$pageFrom-bet' : '$pageFrom–$pageTo-betlar');
  if (problems != null && problems.isNotEmpty) parts.add('$problems-misollar');
  final range = parts.join(' · ');
  return bookTitle == null ? range : '$bookTitle: $range';
}

/// Baho matni: "4" / "8.5" (butun bo'lsa kasrsiz)
String scoreText(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
