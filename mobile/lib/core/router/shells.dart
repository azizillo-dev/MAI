import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class _Tab {
  const _Tab(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Pastki menyu: har bir tab o'z holatini saqlaydi (IndexedStack),
/// tab almashtirilganda ro'yxatlar qayta yuklanmaydi va scroll joyida qoladi.
class _RoleShell extends StatelessWidget {
  const _RoleShell({required this.shell, required this.tabs});

  final StatefulNavigationShell shell;
  final List<_Tab> tabs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          // Faol tabni qayta bossa, tabning boshiga qaytadi
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
        ],
      ),
    );
  }
}

class TeacherShell extends StatelessWidget {
  const TeacherShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => _RoleShell(
        shell: shell,
        tabs: const [
          _Tab(Icons.today_outlined, Icons.today_rounded, 'Bugun'),
          _Tab(Icons.groups_outlined, Icons.groups_rounded, 'Guruhlar'),
          _Tab(Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'AI yordamchi'),
          _Tab(Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
        ],
      );
}

class StudentShell extends StatelessWidget {
  const StudentShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => _RoleShell(
        shell: shell,
        tabs: const [
          _Tab(Icons.home_outlined, Icons.home_rounded, 'Bosh sahifa'),
          _Tab(Icons.assignment_outlined, Icons.assignment_rounded, 'Vazifalar'),
          _Tab(Icons.emoji_events_outlined, Icons.emoji_events_rounded, 'Reyting'),
          _Tab(Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
        ],
      );
}
