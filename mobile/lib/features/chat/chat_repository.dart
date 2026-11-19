import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

class ChatPeer {
  const ChatPeer({required this.id, required this.fullName, required this.initials, required this.role, this.avatarUrl});

  final String id;
  final String fullName;
  final String initials;
  final String role; // teacher | student
  final String? avatarUrl;

  bool get isTeacher => role == 'teacher';

  factory ChatPeer.fromJson(Map<String, dynamic> j) => ChatPeer(
        id: j['id'] as String,
        fullName: j['full_name'] as String,
        initials: j['initials'] as String,
        role: j['role'] as String,
        avatarUrl: j['avatar_url'] as String?,
      );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.peer,
    this.lastText,
    this.lastAt,
    required this.lastFromMe,
    required this.unread,
    this.peerReadAt,
    required this.canSend,
  });

  final String id;
  final ChatPeer peer;
  final String? lastText;
  final DateTime? lastAt;
  final bool lastFromMe;
  final int unread;
  final DateTime? peerReadAt;
  final bool canSend;

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        peer: ChatPeer.fromJson(j['peer'] as Map<String, dynamic>),
        lastText: j['last_message_text'] as String?,
        lastAt: j['last_message_at'] == null ? null : DateTime.parse(j['last_message_at'] as String).toLocal(),
        lastFromMe: j['last_from_me'] as bool,
        unread: j['unread'] as int,
        peerReadAt: j['peer_read_at'] == null ? null : DateTime.parse(j['peer_read_at'] as String).toLocal(),
        canSend: j['can_send'] as bool,
      );
}

class ChatMessage {
  const ChatMessage({required this.id, required this.text, required this.fromMe, required this.createdAt, this.raw});

  final String id;
  final String text;
  final bool fromMe;
  final DateTime createdAt;

  /// Serverdagi vaqt matni ("after" so'rovi uchun aynan shu qaytariladi — aniqlik yo'qolmasin)
  final String? raw;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        text: j['text'] as String,
        fromMe: j['from_me'] as bool,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        raw: j['created_at'] as String,
      );
}

class ChatRepository {
  ChatRepository(this._dio);

  final Dio _dio;

  Future<List<Conversation>> list() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/chats');
        return [for (final c in r.data!) Conversation.fromJson(c as Map<String, dynamic>)];
      });

  Future<int> unread() => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/chats/unread');
        return r.data!['unread'] as int;
      });

  Future<Conversation> openWith(String userId) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/chats/with/$userId');
        return Conversation.fromJson(r.data!);
      });

  Future<Conversation> get(String id) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/chats/$id');
        return Conversation.fromJson(r.data!);
      });

  Future<List<ChatMessage>> messages(String id, {String? after, String? before}) => guard(() async {
        final r = await _dio.get<List<dynamic>>(
          '/chats/$id/messages',
          queryParameters: {'after': ?after, 'before': ?before},
        );
        return [for (final m in r.data!) ChatMessage.fromJson(m as Map<String, dynamic>)];
      });

  Future<ChatMessage> send(String id, String text) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/chats/$id/messages', data: {'text': text});
        return ChatMessage.fromJson(r.data!);
      });

  Future<void> markRead(String id) => guard(() => _dio.post<void>('/chats/$id/read'));
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) => ChatRepository(ref.watch(dioProvider)));

final chatListProvider = FutureProvider.autoDispose<List<Conversation>>((ref) => ref.watch(chatRepositoryProvider).list());

/// O'qilmagan xabarlar soni (belgi uchun): har 30 soniyada yangilanadi
final chatUnreadProvider = StreamProvider.autoDispose<int>((ref) async* {
  final repo = ref.watch(chatRepositoryProvider);
  while (true) {
    try {
      yield await repo.unread();
    } on Object {
      // Tarmoq yo'q — belgi oldingi holatida qoladi
    }
    await Future<void>.delayed(const Duration(seconds: 30));
  }
});
