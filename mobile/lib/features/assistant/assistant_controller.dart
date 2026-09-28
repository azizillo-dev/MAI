import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/theme_controller.dart' show sharedPrefsProvider;
import '../auth/application/auth_controller.dart';

/// Javobga ilova qilingan karta: o'quvchi yoki guruh qisqa ko'rsatkichlari
sealed class ChatAttachment {
  const ChatAttachment();

  static ChatAttachment? fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'student' => StudentAttachment(
            id: j['student_id'] as String,
            name: j['name'] as String,
            avgPercent: (j['avg_percent'] as num?)?.toDouble(),
            trend: j['trend'] as String? ?? '',
            points: [for (final p in (j['points'] as List? ?? const [])) (p as num).toDouble()],
            missing: j['missing'] as int? ?? 0,
            rank: j['rank'] as int?,
            groupSize: j['group_size'] as int? ?? 0,
          ),
        'group' => GroupAttachment(
            id: j['group_id'] as String,
            name: j['name'] as String,
            avgPercent: (j['avg_percent'] as num?)?.toDouble(),
            students: j['students'] as int? ?? 0,
            submissionRate: (j['submission_rate'] as num?)?.toDouble(),
          ),
        'assignment' => AssignmentAttachment(
            id: j['assignment_id'] as String,
            title: j['title'] as String,
            groupName: j['group_name'] as String? ?? '',
            count: j['count'] as int? ?? 0,
            difficulty: j['difficulty'] as String? ?? 'medium',
          ),
        _ => null,
      };
}

/// AI yordamchi chatda yaratgan vazifa (qoralama)
class AssignmentAttachment extends ChatAttachment {
  const AssignmentAttachment({
    required this.id,
    required this.title,
    required this.groupName,
    required this.count,
    required this.difficulty,
  });

  final String id;
  final String title;
  final String groupName;
  final int count;
  final String difficulty;
}

class StudentAttachment extends ChatAttachment {
  const StudentAttachment({
    required this.id,
    required this.name,
    required this.avgPercent,
    required this.trend,
    required this.points,
    required this.missing,
    required this.rank,
    required this.groupSize,
  });

  final String id;
  final String name;
  final double? avgPercent;
  final String trend;
  final List<double> points;
  final int missing;
  final int? rank;
  final int groupSize;
}

class GroupAttachment extends ChatAttachment {
  const GroupAttachment({
    required this.id,
    required this.name,
    required this.avgPercent,
    required this.students,
    required this.submissionRate,
  });

  final String id;
  final String name;
  final double? avgPercent;
  final int students;
  final double? submissionRate;
}

class ChatMessage {
  const ChatMessage({required this.fromUser, required this.text, this.attachmentsRaw = const [], this.failed = false});

  final bool fromUser;
  final String text;
  /// Serverdan kelgan ilovalar (kartalar) — telefon xotirasiga shu ko'rinishda saqlanadi
  final List<Map<String, dynamic>> attachmentsRaw;
  /// Xato haqida xabar (serverga tarix sifatida yuborilmaydi va saqlanmaydi)
  final bool failed;

  List<ChatAttachment> get attachments => [for (final a in attachmentsRaw) ?ChatAttachment.fromJson(a)];

  Map<String, dynamic> toJson() => {'u': fromUser, 't': text, if (attachmentsRaw.isNotEmpty) 'a': attachmentsRaw};

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        fromUser: j['u'] as bool? ?? false,
        text: j['t'] as String? ?? '',
        attachmentsRaw: [for (final a in (j['a'] as List? ?? const [])) (a as Map).cast<String, dynamic>()],
      );
}

class ChatState {
  const ChatState({this.messages = const [], this.sending = false});

  final List<ChatMessage> messages;
  final bool sending;
}

/// Suhbat telefon xotirasida saqlanadi: ilovadan chiqib qayta kirganda ham davom etadi.
/// Har bir akkaunt uchun alohida; "Yangi suhbat" bosilganda tozalanadi.
final assistantChatProvider = NotifierProvider<AssistantChat, ChatState>(AssistantChat.new);

class AssistantChat extends Notifier<ChatState> {
  static const _historyLimit = 12;
  static const _storeLimit = 60;

  String? _key;

  @override
  ChatState build() {
    // Boshqa akkauntga kirilsa — o'sha akkauntning suhbati yuklanadi
    final userId = ref.watch(currentUserProvider.select((me) => me?.id));
    _key = userId == null ? null : 'assistant_chat_$userId';
    return ChatState(messages: _load());
  }

  List<ChatMessage> _load() {
    final key = _key;
    if (key == null) return const [];
    try {
      final raw = ref.read(sharedPrefsProvider).getString(key);
      if (raw == null) return const [];
      return [for (final m in jsonDecode(raw) as List) ChatMessage.fromJson((m as Map).cast<String, dynamic>())];
    } on Object {
      return const []; // buzilgan yozuv ilovani to'xtatmasin
    }
  }

  void _save(List<ChatMessage> messages) {
    final key = _key;
    if (key == null) return;
    final keep = messages.where((m) => !m.failed).toList();
    final tail = keep.length > _storeLimit ? keep.sublist(keep.length - _storeLimit) : keep;
    ref.read(sharedPrefsProvider).setString(key, jsonEncode([for (final m in tail) m.toJson()]));
  }

  void clear() {
    state = const ChatState();
    final key = _key;
    if (key != null) ref.read(sharedPrefsProvider).remove(key);
  }

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || state.sending) return;
    final messages = [...state.messages, ChatMessage(fromUser: true, text: q)];
    state = ChatState(messages: messages, sending: true);
    _save(messages);

    final history = [
      for (final m in messages.where((m) => !m.failed))
        {'role': m.fromUser ? 'user' : 'assistant', 'content': _clip(m.text)},
    ];
    final payload = history.length > _historyLimit ? history.sublist(history.length - _historyLimit) : history;

    ChatMessage reply;
    try {
      final data = await guard(() async {
        final r = await ref.read(dioProvider).post<Map<String, dynamic>>(
              '/teachers/me/assistant',
              data: {'messages': payload},
              // Bir nechta vosita chaqirilsa javob 20 soniyadan oshishi mumkin
              options: Options(receiveTimeout: const Duration(seconds: 120)),
            );
        return r.data!;
      });
      reply = ChatMessage(
        fromUser: false,
        text: (data['reply'] as String?)?.trim() ?? '',
        attachmentsRaw: [for (final a in (data['attachments'] as List? ?? const [])) (a as Map).cast<String, dynamic>()],
      );
    } on ApiException catch (e) {
      reply = ChatMessage(
        fromUser: false,
        failed: true,
        text: e.code == 'AI_UNAVAILABLE'
            ? "AI hozir band yoki vaqtincha ishlamayapti. Birozdan keyin qayta urinib ko'ring."
            : e.message,
      );
    }
    final updated = [...state.messages, reply];
    state = ChatState(messages: updated);
    _save(updated);
  }

  static String _clip(String s) => s.length > 2000 ? s.substring(0, 2000) : s;
}
