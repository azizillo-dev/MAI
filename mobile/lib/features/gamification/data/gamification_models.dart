import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class BadgeInfo {
  const BadgeInfo({
    required this.code,
    required this.name,
    required this.description,
    required this.category,
    required this.categoryName,
    required this.icon,
    required this.tier,
    required this.target,
    required this.value,
    this.subject,
    this.earnedAt,
  });

  final String code;
  final String name;
  final String description;
  final String category;
  final String categoryName;
  final String icon;
  final String tier;
  final int target;
  final int value;
  final String? subject;
  final DateTime? earnedAt;

  bool get earned => earnedAt != null;
  double get progress => target == 0 ? 0 : (value / target).clamp(0.0, 1.0);

  factory BadgeInfo.fromJson(Map<String, dynamic> j) => BadgeInfo(
        code: j['code'] as String,
        name: j['name'] as String,
        description: j['description'] as String,
        category: j['category'] as String,
        categoryName: j['category_name'] as String,
        icon: j['icon'] as String,
        tier: j['tier'] as String,
        target: j['target'] as int,
        value: j['value'] as int,
        subject: j['subject'] as String?,
        earnedAt: j['earned_at'] == null ? null : DateTime.parse(j['earned_at'] as String).toLocal(),
      );
}

class Medal {
  const Medal({required this.code, required this.name, required this.tier, required this.month, this.groupName, this.points});

  final String code;
  final String name;
  final String tier;
  final String month; // "2026-08"
  final String? groupName;
  final int? points;

  factory Medal.fromJson(Map<String, dynamic> j) => Medal(
        code: j['code'] as String,
        name: j['name'] as String,
        tier: j['tier'] as String,
        month: j['month'] as String? ?? '',
        groupName: j['group'] as String?,
        points: j['points'] as int?,
      );
}

class GroupRank {
  const GroupRank({required this.groupId, required this.groupName, required this.rank, required this.of});

  final String groupId;
  final String groupName;
  final int rank;
  final int of;

  factory GroupRank.fromJson(Map<String, dynamic> j) => GroupRank(
        groupId: j['group_id'] as String,
        groupName: j['group_name'] as String,
        rank: j['rank'] as int,
        of: j['of'] as int,
      );
}

class StudentProgress {
  const StudentProgress({
    required this.xp,
    required this.level,
    required this.levelName,
    required this.levelXp,
    required this.levelSpan,
    required this.works,
    required this.avgPercent,
    required this.currentStreak,
    required this.bestStreak,
    required this.badgesEarned,
    required this.badgesTotal,
    required this.ranks,
    required this.badges,
    required this.medals,
  });

  final int xp;
  final int level;
  final String levelName;
  final int levelXp;
  final int levelSpan;
  final int works;
  final int avgPercent;
  final int currentStreak;
  final int bestStreak;
  final int badgesEarned;
  final int badgesTotal;
  final List<GroupRank> ranks;
  final List<BadgeInfo> badges;
  final List<Medal> medals;

  double get levelProgress => levelSpan == 0 ? 0 : levelXp / levelSpan;
  GroupRank? get bestRank => ranks.isEmpty ? null : ranks.first;

  factory StudentProgress.fromJson(Map<String, dynamic> j) {
    final s = j['stats'] as Map<String, dynamic>;
    return StudentProgress(
      xp: j['xp'] as int,
      level: j['level'] as int,
      levelName: j['level_name'] as String,
      levelXp: j['level_xp'] as int,
      levelSpan: j['level_span'] as int,
      works: s['works'] as int,
      avgPercent: s['avg_percent'] as int,
      currentStreak: s['current_streak'] as int,
      bestStreak: s['best_streak'] as int,
      badgesEarned: s['badges_earned'] as int,
      badgesTotal: s['badges_total'] as int,
      ranks: [for (final r in j['ranks'] as List) GroupRank.fromJson(r as Map<String, dynamic>)],
      badges: [for (final b in j['badges'] as List) BadgeInfo.fromJson(b as Map<String, dynamic>)],
      medals: [for (final m in j['medals'] as List) Medal.fromJson(m as Map<String, dynamic>)],
    );
  }
}

class LeaderEntry {
  const LeaderEntry({
    required this.rank,
    required this.studentId,
    required this.name,
    this.avatarUrl,
    required this.points,
    required this.level,
  });

  final int rank;
  final String studentId;
  final String name;
  final String? avatarUrl;
  final int points;
  final int level;

  String get initials => name.split(' ').where((p) => p.isNotEmpty).map((p) => p[0]).take(2).join().toUpperCase();

  factory LeaderEntry.fromJson(Map<String, dynamic> j) => LeaderEntry(
        rank: j['rank'] as int,
        studentId: j['student_id'] as String,
        name: j['name'] as String,
        avatarUrl: j['avatar_url'] as String?,
        points: j['points'] as int,
        level: j['level'] as int,
      );
}

class Leaderboard {
  const Leaderboard({required this.groupName, required this.teacherName, required this.entries, this.me});

  final String groupName;
  final String teacherName;
  final List<LeaderEntry> entries;
  final LeaderEntry? me;

  factory Leaderboard.fromJson(Map<String, dynamic> j) => Leaderboard(
        groupName: j['group_name'] as String,
        teacherName: j['teacher_name'] as String,
        entries: [for (final e in j['entries'] as List) LeaderEntry.fromJson(e as Map<String, dynamic>)],
        me: j['me'] == null ? null : LeaderEntry.fromJson(j['me'] as Map<String, dynamic>),
      );
}

enum LeaderScope { group, teacher }

enum LeaderPeriod {
  month('month', 'Shu oy'),
  threeMonths('3months', '3 oy'),
  all('all', 'Butun vaqt');

  const LeaderPeriod(this.api, this.label);
  final String api;
  final String label;
}

typedef LeaderQuery = ({String groupId, LeaderScope scope, LeaderPeriod period});

final studentProgressProvider = FutureProvider.autoDispose<StudentProgress>((ref) async {
  final Dio dio = ref.watch(dioProvider);
  return guard(() async {
    final r = await dio.get<Map<String, dynamic>>('/students/me/progress');
    return StudentProgress.fromJson(r.data!);
  });
});

final leaderboardProvider = FutureProvider.autoDispose.family<Leaderboard, LeaderQuery>((ref, q) async {
  final Dio dio = ref.watch(dioProvider);
  return guard(() async {
    final r = await dio.get<Map<String, dynamic>>('/leaderboard', queryParameters: {
      'group_id': q.groupId,
      'scope': q.scope.name,
      'period': q.period.api,
    });
    return Leaderboard.fromJson(r.data!);
  });
});
