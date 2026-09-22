import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class DashboardStats {
  const DashboardStats({
    required this.groups,
    required this.students,
    required this.pendingRequests,
    required this.openAssignments,
    required this.drafts,
    required this.toReview,
    required this.gradedThisWeek,
    this.avgPercentWeek,
  });

  final int groups;
  final int students;
  final int pendingRequests;
  final int openAssignments;
  final int drafts;
  final int toReview;
  final int gradedThisWeek;
  final double? avgPercentWeek;

  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
        groups: j['groups'] as int,
        students: j['students'] as int,
        pendingRequests: j['pending_requests'] as int,
        openAssignments: j['open_assignments'] as int,
        drafts: j['drafts'] as int,
        toReview: j['to_review'] as int,
        gradedThisWeek: j['graded_this_week'] as int,
        avgPercentWeek: (j['avg_percent_week'] as num?)?.toDouble(),
      );
}

class UpcomingItem {
  const UpcomingItem({
    required this.assignmentId,
    required this.title,
    required this.groupName,
    required this.dueAt,
    required this.submitted,
    required this.members,
  });

  final String assignmentId;
  final String title;
  final String groupName;
  final DateTime dueAt;
  final int submitted;
  final int members;

  factory UpcomingItem.fromJson(Map<String, dynamic> j) => UpcomingItem(
        assignmentId: j['assignment_id'] as String,
        title: j['title'] as String,
        groupName: j['group_name'] as String,
        dueAt: DateTime.parse(j['due_at'] as String).toLocal(),
        submitted: j['submitted'] as int,
        members: j['members'] as int,
      );
}

class ActivityDay {
  const ActivityDay({required this.day, required this.count});

  final DateTime day;
  final int count;

  factory ActivityDay.fromJson(Map<String, dynamic> j) =>
      ActivityDay(day: DateTime.parse(j['day'] as String), count: j['count'] as int);
}

class RecentWork {
  const RecentWork({
    required this.submissionId,
    required this.studentName,
    required this.assignmentTitle,
    required this.status,
    this.finalScore,
    required this.gradingScale,
    required this.submittedAt,
  });

  final String submissionId;
  final String studentName;
  final String assignmentTitle;
  final String status;
  final double? finalScore;
  final String gradingScale;
  final DateTime submittedAt;

  factory RecentWork.fromJson(Map<String, dynamic> j) => RecentWork(
        submissionId: j['submission_id'] as String,
        studentName: j['student_name'] as String,
        assignmentTitle: j['assignment_title'] as String,
        status: j['status'] as String,
        finalScore: (j['final_score'] as num?)?.toDouble(),
        gradingScale: j['grading_scale'] as String,
        submittedAt: DateTime.parse(j['submitted_at'] as String).toLocal(),
      );
}

class TeacherDashboard {
  const TeacherDashboard({required this.stats, required this.upcoming, required this.activity, required this.recent});

  final DashboardStats stats;
  final List<UpcomingItem> upcoming;
  final List<ActivityDay> activity;
  final List<RecentWork> recent;

  factory TeacherDashboard.fromJson(Map<String, dynamic> j) => TeacherDashboard(
        stats: DashboardStats.fromJson(j['stats'] as Map<String, dynamic>),
        upcoming: [for (final u in j['upcoming'] as List) UpcomingItem.fromJson(u as Map<String, dynamic>)],
        activity: [for (final a in j['activity'] as List) ActivityDay.fromJson(a as Map<String, dynamic>)],
        recent: [for (final r in j['recent'] as List) RecentWork.fromJson(r as Map<String, dynamic>)],
      );
}

final teacherDashboardProvider = FutureProvider.autoDispose<TeacherDashboard>((ref) async {
  final Dio dio = ref.watch(dioProvider);
  return guard(() async {
    final r = await dio.get<Map<String, dynamic>>('/teachers/me/dashboard');
    return TeacherDashboard.fromJson(r.data!);
  });
});
