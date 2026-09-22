import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
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
        _ => null,
      };
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
  const ChatMessage({required this.fromUser, required this.text, this.attachments = const [], this.failed = false});

  final bool fromUser;
  final String text;
  final List<ChatAttachment> attachments;
  /// Xato haqida xabar (serverga tarix sifatida yuborilmaydi)
  final bool failed;
}

class ChatState {
  const ChatState({this.messages = const [], this.sending = false});

  final List<ChatMessage> messages;
  final bool sending;
}

/// Suhbat tarixi faqat ilova xotirasida: tab almashganda saqlanadi, chiqib ketganda o'chadi
final assistantChatProvider = NotifierProvider<AssistantChat, ChatState>(AssistantChat.new);

class AssistantChat extends Notifier<ChatState> {
  static const _historyLimit = 12;

  @override
  ChatState build() {
    // Boshqa akkauntga kirilsa suhbat tozalanadi
    ref.watch(currentUserProvider.select((me) => me?.id));
    return const ChatState();
  }

  void clear() => state = const ChatState();

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || state.sending) return;
    final messages = [...state.messages, ChatMessage(fromUser: true, text: q)];
    state = ChatState(messages: messages, sending: true);

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
        attachments: [
          for (final a in (data['attachments'] as List? ?? const []))
            ?ChatAttachment.fromJson(a as Map<String, dynamic>),
        ],
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
    state = ChatState(messages: [...state.messages, reply]);
  }

  static String _clip(String s) => s.length > 2000 ? s.substring(0, 2000) : s;
}
