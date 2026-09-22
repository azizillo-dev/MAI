import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'group_models.dart';

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) => GroupsRepository(ref.watch(dioProvider)));

// ---------------- O'qituvchi
final teacherGroupsProvider = FutureProvider.autoDispose<List<TeacherGroup>>(
  (ref) => ref.watch(groupsRepositoryProvider).myGroups(),
);

final teacherGroupProvider = FutureProvider.autoDispose.family<TeacherGroup, String>(
  (ref, id) => ref.watch(groupsRepositoryProvider).group(id),
);

final groupMembersProvider = FutureProvider.autoDispose.family<List<GroupMember>, String>(
  (ref, id) => ref.watch(groupsRepositoryProvider).members(id),
);

final planUsageProvider = FutureProvider.autoDispose<PlanUsage>(
  (ref) => ref.watch(groupsRepositoryProvider).planUsage(),
);

// ---------------- O'quvchi
final membershipsProvider = FutureProvider.autoDispose<List<Membership>>(
  (ref) => ref.watch(groupsRepositoryProvider).memberships(),
);

class GroupsRepository {
  GroupsRepository(this._dio);

  final Dio _dio;

  Future<List<TeacherGroup>> myGroups() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/groups');
        return [for (final g in r.data!) TeacherGroup.fromJson(g as Map<String, dynamic>)];
      });

  Future<TeacherGroup> group(String id) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/groups/$id');
        return TeacherGroup.fromJson(r.data!);
      });

  Future<TeacherGroup> create({
    required String name,
    required String subject,
    required String gradingScale,
  }) =>
      guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/groups', data: {
          'name': name,
          'subject': subject,
          'grading_scale': gradingScale,
        });
        return TeacherGroup.fromJson(r.data!);
      });

  Future<TeacherGroup> update(String id, {String? name, String? gradingScale}) =>
      guard(() async {
        final r = await _dio.patch<Map<String, dynamic>>('/groups/$id', data: {
          'name': ?name,
          'grading_scale': ?gradingScale,
        });
        return TeacherGroup.fromJson(r.data!);
      });

  Future<TeacherGroup> rotateCredentials(String id) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/groups/$id/rotate-credentials');
        return TeacherGroup.fromJson(r.data!);
      });

  /// Qo'shilishni yopish/ochish
  Future<TeacherGroup> setJoinEnabled(String id, bool enabled) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/groups/$id/join-status', data: {'enabled': enabled});
        return TeacherGroup.fromJson(r.data!);
      });

  /// Kutayotganlarning hammasini qabul qiladi. Qaytaradi: (qabul qilindi, limit sabab qolgani)
  Future<(int, int)> approveAll(String groupId) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/groups/$groupId/members/approve-all');
        return (r.data!['approved'] as int, r.data!['left_pending'] as int);
      });

  Future<List<GroupMember>> members(String groupId) => guard(() async {
        final r = await _dio.get<List<dynamic>>('/groups/$groupId/members');
        return [for (final m in r.data!) GroupMember.fromJson(m as Map<String, dynamic>)];
      });

  /// action: approve | reject | remove
  Future<void> decide(String groupId, String studentId, String action) =>
      guard(() => _dio.post<void>('/groups/$groupId/members/$studentId/$action'));

  Future<void> grantProfileEdit(String groupId, String studentId) =>
      guard(() => _dio.post<void>('/groups/$groupId/members/$studentId/grant-profile-edit'));

  Future<PlanUsage> planUsage() => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/teachers/me/plan');
        return PlanUsage.fromJson(r.data!);
      });

  Future<List<Membership>> memberships() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/memberships');
        return [for (final m in r.data!) Membership.fromJson(m as Map<String, dynamic>)];
      });

  Future<JoinPreview> preview(String code) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/memberships/preview', data: {'code': code});
        return JoinPreview.fromJson(r.data!);
      });

  Future<Membership> join({required String code, String? password, String? inviteToken}) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/memberships', data: {
          'code': code,
          'password': ?password,
          'invite_token': ?inviteToken,
        });
        return Membership.fromJson(r.data!);
      });

  Future<void> leave(String groupId) => guard(() => _dio.delete<void>('/memberships/$groupId'));
}
