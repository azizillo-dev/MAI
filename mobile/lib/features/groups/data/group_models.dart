class TeacherGroup {
  const TeacherGroup({
    required this.id,
    required this.name,
    required this.subject,
    required this.gradingScale,
    required this.status,
    required this.joinEnabled,
    required this.joinCode,
    required this.joinPassword,
    required this.inviteUrl,
    required this.membersActive,
    required this.membersPending,
  });

  final String id;
  final String name;
  final String subject;
  final String gradingScale;
  final String status;

  /// Ustoz qo'shilishni yopib qo'ygan bo'lsa false: kod, QR va havola ishlamaydi
  final bool joinEnabled;

  /// "K7M4-XQ9P"
  final String joinCode;
  final String joinPassword;
  final String inviteUrl;
  final int membersActive;
  final int membersPending;

  factory TeacherGroup.fromJson(Map<String, dynamic> j) => TeacherGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        subject: j['subject'] as String,
        gradingScale: j['grading_scale'] as String,
        status: j['status'] as String,
        joinEnabled: j['join_enabled'] as bool,
        joinCode: j['join_code'] as String,
        joinPassword: j['join_password'] as String,
        inviteUrl: j['invite_url'] as String,
        membersActive: j['members_active'] as int,
        membersPending: j['members_pending'] as int,
      );

  /// "48291375" -> "4829 1375" (o'qish va aytish oson)
  String get passwordPretty =>
      joinPassword.length == 8 ? '${joinPassword.substring(0, 4)} ${joinPassword.substring(4)}' : joinPassword;
}

class GroupMember {
  const GroupMember({
    required this.studentId,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    this.phone,
    this.email,
    this.avatarUrl,
    required this.status,
    required this.requestedAt,
  });

  final String studentId;
  final String firstName;
  final String lastName;
  final String fullName;
  final String? phone;
  final String? email;
  final String? avatarUrl;
  final String status;
  final DateTime requestedAt;

  bool get isPending => status == 'pending';

  String get contact => phone ?? email ?? '';

  String get initials => '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}';

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
        studentId: j['student_id'] as String,
        firstName: j['first_name'] as String,
        lastName: j['last_name'] as String,
        fullName: j['full_name'] as String,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        status: j['status'] as String,
        requestedAt: DateTime.parse(j['requested_at'] as String),
      );
}

class Membership {
  const Membership({
    required this.groupId,
    required this.groupName,
    required this.subject,
    required this.gradingScale,
    required this.teacherName,
    required this.status,
  });

  final String groupId;
  final String groupName;
  final String subject;
  final String gradingScale;
  final String teacherName;
  final String status;

  bool get isPending => status == 'pending';

  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
        groupId: j['group_id'] as String,
        groupName: j['group_name'] as String,
        subject: j['subject'] as String,
        gradingScale: j['grading_scale'] as String,
        teacherName: (j['teacher'] as Map)['full_name'] as String,
        status: j['status'] as String,
      );
}

class JoinPreview {
  const JoinPreview({
    required this.code,
    required this.groupName,
    required this.subject,
    required this.teacherName,
    required this.membersActive,
  });

  final String code;
  final String groupName;
  final String subject;
  final String teacherName;
  final int membersActive;

  factory JoinPreview.fromJson(Map<String, dynamic> j) => JoinPreview(
        code: j['code'] as String,
        groupName: j['group_name'] as String,
        subject: j['subject'] as String,
        teacherName: j['teacher_name'] as String,
        membersActive: j['members_active'] as int,
      );
}

class PlanUsage {
  const PlanUsage({
    required this.planCode,
    required this.planName,
    required this.maxGroups,
    required this.maxStudents,
    required this.maxAssignmentsPerWeek,
    required this.groupsUsed,
    required this.studentsUsed,
    this.status = 'active',
    this.daysLeft,
    this.endsAt,
  });

  final String planCode;
  final String planName;
  final int maxGroups;
  final int maxStudents;
  final int? maxAssignmentsPerWeek;
  final int groupsUsed;
  final int studentsUsed;
  /// trial | active | expired
  final String status;
  final int? daysLeft;
  final DateTime? endsAt;

  bool get isTrial => status == 'trial';
  bool get isExpired => status == 'expired';
  /// Sinov yoki tarif tugashiga oz qolgan — ogohlantirish ko'rsatiladi
  bool get endsSoon => !isExpired && daysLeft != null && daysLeft! <= 3;
  bool get canCreateGroup => !isExpired && groupsUsed < maxGroups;

  factory PlanUsage.fromJson(Map<String, dynamic> j) {
    final p = j['plan'] as Map<String, dynamic>;
    return PlanUsage(
      planCode: p['code'] as String,
      planName: p['name'] as String,
      maxGroups: p['max_groups'] as int,
      maxStudents: p['max_students'] as int,
      maxAssignmentsPerWeek: p['max_assignments_per_week'] as int?,
      groupsUsed: j['groups_used'] as int,
      studentsUsed: j['students_used'] as int,
      status: j['status'] as String? ?? 'active',
      daysLeft: j['days_left'] as int?,
      endsAt: j['ends_at'] == null ? null : DateTime.parse(j['ends_at'] as String),
    );
  }
}

/// QR yoki havoladan olingan taklif: https://mentorai.uz/join/K7M4XQ9P?t=TOKEN
class InviteLink {
  const InviteLink({required this.code, this.token});

  final String code;
  final String? token;

  static InviteLink? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final segments = uri.pathSegments;
    final i = segments.indexOf('join');
    // mentorai://join/K7M4XQ da "join" host bo'ladi
    final code = i >= 0 && i + 1 < segments.length
        ? segments[i + 1]
        : (uri.host == 'join' && segments.isNotEmpty ? segments.first : null);
    if (code == null || code.replaceAll('-', '').length != 8) return null;
    return InviteLink(code: code.toUpperCase(), token: uri.queryParameters['t']);
  }
}
