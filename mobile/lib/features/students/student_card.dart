import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../gamification/data/gamification_models.dart';

class CardSubmission {
  const CardSubmission({
    required this.id,
    required this.title,
    required this.groupName,
    required this.status,
    required this.finalScore,
    required this.gradingScale,
    required this.percent,
    required this.isLate,
    required this.submittedAt,
  });

  final String id;
  final String title;
  final String groupName;
  final String status;
  final double? finalScore;
  final String gradingScale;
  final double? percent;
  final bool isLate;
  final DateTime submittedAt;

  factory CardSubmission.fromJson(Map<String, dynamic> j) => CardSubmission(
        id: j['id'] as String,
        title: j['title'] as String,
        groupName: j['group_name'] as String,
        status: j['status'] as String,
        finalScore: (j['final_score'] as num?)?.toDouble(),
        gradingScale: j['grading_scale'] as String,
        percent: (j['percent'] as num?)?.toDouble(),
        isLate: j['is_late'] as bool? ?? false,
        submittedAt: DateTime.parse(j['submitted_at'] as String).toLocal(),
      );
}

class CardTask {
  const CardTask({required this.assignmentId, required this.title, required this.groupName, required this.dueAt});

  final String assignmentId;
  final String title;
  final String groupName;
  final DateTime dueAt;

  factory CardTask.fromJson(Map<String, dynamic> j) => CardTask(
        assignmentId: j['assignment_id'] as String,
        title: j['title'] as String,
        groupName: j['group_name'] as String,
        dueAt: DateTime.parse(j['due_at'] as String).toLocal(),
      );
}

/// Faqat ustozga ko'rinadigan qism
class TeacherView {
  const TeacherView({
    this.phone,
    this.email,
    this.birthDate,
    required this.assigned,
    required this.submitted,
    required this.missingCount,
    required this.late,
    required this.avgPercent,
    required this.waitingReview,
    required this.submissions,
    required this.missing,
    required this.open,
  });

  final String? phone;
  final String? email;
  final DateTime? birthDate;
  final int assigned;
  final int submitted;
  final int missingCount;
  final int late;
  final double? avgPercent;
  final int waitingReview;
  final List<CardSubmission> submissions;
  final List<CardTask> missing;
  final List<CardTask> open;

  factory TeacherView.fromJson(Map<String, dynamic> j) {
    final s = j['summary'] as Map<String, dynamic>;
    return TeacherView(
      phone: j['phone'] as String?,
      email: j['email'] as String?,
      birthDate: j['birth_date'] == null ? null : DateTime.parse(j['birth_date'] as String),
      assigned: s['assigned'] as int,
      submitted: s['submitted'] as int,
      missingCount: s['missing'] as int,
      late: s['late'] as int,
      avgPercent: (s['avg_percent'] as num?)?.toDouble(),
      waitingReview: s['waiting_review'] as int? ?? 0,
      submissions: [for (final x in j['submissions'] as List) CardSubmission.fromJson(x as Map<String, dynamic>)],
      missing: [for (final x in j['missing'] as List) CardTask.fromJson(x as Map<String, dynamic>)],
      open: [for (final x in j['open'] as List) CardTask.fromJson(x as Map<String, dynamic>)],
    );
  }
}

class StudentCard {
  const StudentCard({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    this.avatarUrl,
    required this.joinedAt,
    required this.isSelf,
    required this.progress,
    required this.groups,
    this.teacherView,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String fullName;
  final String? avatarUrl;
  final DateTime joinedAt;
  final bool isSelf;
  /// XP, daraja, statistika, reyting, olingan jetonlar va medallar
  final StudentProgress progress;
  final List<(String id, String name, String subject)> groups;
  final TeacherView? teacherView;

  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'.toUpperCase();

  factory StudentCard.fromJson(Map<String, dynamic> j) => StudentCard(
        id: j['id'] as String,
        firstName: j['first_name'] as String,
        lastName: j['last_name'] as String,
        fullName: j['full_name'] as String,
        avatarUrl: j['avatar_url'] as String?,
        joinedAt: DateTime.parse(j['joined_at'] as String).toLocal(),
        isSelf: j['is_self'] as bool? ?? false,
        progress: StudentProgress.fromJson(j),
        groups: [
          for (final g in j['groups'] as List)
            ((g as Map)['id'] as String, g['name'] as String, g['subject'] as String),
        ],
        teacherView: j['teacher_view'] == null ? null : TeacherView.fromJson(j['teacher_view'] as Map<String, dynamic>),
      );
}

final studentCardProvider = FutureProvider.autoDispose.family<StudentCard, String>((ref, id) async {
  final Dio dio = ref.watch(dioProvider);
  return guard(() async {
    final r = await dio.get<Map<String, dynamic>>('/students/$id/profile');
    return StudentCard.fromJson(r.data!);
  });
});
