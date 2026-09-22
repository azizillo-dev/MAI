import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/assignments/presentation/student/student_assignment_screen.dart';
import '../../features/assistant/assistant_screen.dart';
import '../../features/assignments/presentation/student/student_tasks_screen.dart';
import '../../features/assignments/presentation/teacher/assignment_screen.dart';
import '../../features/assignments/presentation/teacher/create_assignment_screen.dart';
import '../../features/assignments/presentation/teacher/submission_review_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/email_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/phone_screen.dart';
import '../../features/auth/presentation/register_screens.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/billing/plans_screen.dart';
import '../../features/gamification/presentation/badges_screen.dart';
import '../../features/gamification/presentation/leaderboard_screen.dart';
import '../../features/groups/data/group_models.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/settings_screen.dart';
import '../../features/profile/student_profile_edit_screen.dart';
import '../../features/student/home/student_home_screen.dart';
import '../../features/students/student_profile_screen.dart';
import '../../features/student/join/join_group_screen.dart';
import '../../features/student/join/qr_scan_screen.dart';
import '../../features/teacher/groups/group_detail_screen.dart';
import '../../features/teacher/groups/groups_screen.dart';
import '../../features/teacher/home/teacher_home_screen.dart';
import '../../features/teacher/onboarding/onboarding_screen.dart';
import 'shells.dart';
import 'splash_screen.dart';

/// Taklif havolasi (https://mentorai.uz/join/K7M4XQ?t=...) orqali ochilganda
/// o'quvchi kirguncha/ro'yxatdan o'tguncha shu yerda saqlanadi.
class PendingInvite {
  InviteLink? _value;

  bool get has => _value != null;

  void set(InviteLink link) => _value = link;

  InviteLink? take() {
    final v = _value;
    _value = null;
    return v;
  }

  void clear() => _value = null;
}

final pendingInviteProvider = Provider<PendingInvite>((ref) => PendingInvite());

final _rootKey = GlobalKey<NavigatorState>();

/// Ikkala rol uchun umumiy sahifalar
bool _shared(String loc) =>
    loc == '/settings' || loc == '/badges' || loc == '/leaderboard' || loc.startsWith('/students/');

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);
  final invite = ref.read(pendingInviteProvider);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;

      // Deep link: /join/K7M4XQ?t=TOKEN
      if (state.uri.pathSegments.firstOrNull == 'join') {
        final link = InviteLink.tryParse(state.uri.toString());
        if (link != null) invite.set(link);
      }

      final auth = ref.read(authControllerProvider);
      switch (auth) {
        case AuthLoading():
          return loc == '/splash' ? null : '/splash';

        case AuthGuest():
          final isAuthRoute = loc == '/welcome' || loc.startsWith('/auth/');
          return isAuthRoute ? null : '/welcome';

        case AuthSignedIn(:final me) when me.isTeacher:
          invite.clear(); // o'qituvchiga guruhga qo'shilish havolasi tegishli emas
          if (me.needsOnboarding) return loc == '/teacher/onboarding' ? null : '/teacher/onboarding';
          if (_shared(loc)) return null;
          if (!loc.startsWith('/teacher') || loc == '/teacher/onboarding') return '/teacher';
          return null;

        case AuthSignedIn():
          if (invite.has && loc != '/student/join') return '/student/join';
          if (_shared(loc)) return null;
          return loc.startsWith('/student') ? null : '/student';
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      // Faqat redirect uchun (yuqorida qayta ishlanadi)
      GoRoute(path: '/join/:code', redirect: (_, _) => '/splash'),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/auth/email', builder: (_, _) => const EmailScreen()),
      GoRoute(path: '/auth/phone', builder: (_, _) => const PhoneScreen()),
      GoRoute(path: '/auth/otp', builder: (_, _) => const OtpScreen()),
      GoRoute(path: '/auth/role', builder: (_, _) => const RolePickScreen()),
      GoRoute(path: '/auth/register/student', builder: (_, _) => const StudentRegisterScreen()),
      GoRoute(path: '/auth/register/teacher', builder: (_, _) => const TeacherRegisterScreen()),

      // ------------------------------------------------ Umumiy (ikkala rol)
      GoRoute(path: '/settings', parentNavigatorKey: _rootKey, builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/students/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => StudentProfileScreen(studentId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/badges', parentNavigatorKey: _rootKey, builder: (_, _) => const BadgesScreen()),
      GoRoute(
        path: '/leaderboard',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => LeaderboardScreen(groupId: state.uri.queryParameters['group']),
      ),

      // ------------------------------------------------ O'qituvchi
      GoRoute(path: '/teacher/onboarding', builder: (_, _) => const TeacherOnboardingScreen()),
      GoRoute(
        path: '/teacher/ai-profile',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const TeacherOnboardingScreen(editMode: true),
      ),
      GoRoute(
        path: '/teacher/groups/:id/assignments/new',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => CreateAssignmentScreen(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/teacher/assignments/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => TeacherAssignmentScreen(assignmentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/teacher/submissions/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => SubmissionReviewScreen(submissionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/teacher/plans',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const PlansScreen(),
      ),
      GoRoute(
        path: '/teacher/review',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ReviewQueueScreen(),
      ),
      GoRoute(
        path: '/teacher/groups/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => GroupDetailScreen(
          groupId: state.pathParameters['id']!,
          justCreated: state.uri.queryParameters['created'] == '1',
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => TeacherShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/teacher', builder: (_, _) => const TeacherHomeScreen())]),
          StatefulShellBranch(
            routes: [GoRoute(path: '/teacher/groups', builder: (_, _) => const TeacherGroupsScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/teacher/ai',
                builder: (_, _) => const AssistantScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/teacher/profile', builder: (_, _) => const ProfileScreen())],
          ),
        ],
      ),

      // ------------------------------------------------ O'quvchi
      GoRoute(
        path: '/student/join',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => JoinGroupScreen(invite: state.extra as InviteLink? ?? invite.take()),
      ),
      GoRoute(
        path: '/student/join/scan',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const QrScanScreen(),
      ),
      GoRoute(
        path: '/student/tasks/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => StudentAssignmentScreen(assignmentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/student/profile/edit',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const StudentProfileEditScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => StudentShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/student', builder: (_, _) => const StudentHomeScreen())]),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/student/tasks', builder: (_, _) => const StudentTasksScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/student/rating',
                builder: (_, _) => const LeaderboardScreen(embedded: true),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/student/profile', builder: (_, _) => const ProfileScreen())],
          ),
        ],
      ),
    ],
  );
});
