import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'assignment_models.dart';

final assignmentsRepositoryProvider =
    Provider<AssignmentsRepository>((ref) => AssignmentsRepository(ref.watch(dioProvider)));

// ---------------- O'qituvchi
final booksProvider = FutureProvider.autoDispose<List<Book>>((ref) => ref.watch(assignmentsRepositoryProvider).books());

final groupAssignmentsProvider = FutureProvider.autoDispose.family<List<Assignment>, String>(
  (ref, groupId) => ref.watch(assignmentsRepositoryProvider).groupAssignments(groupId),
);

final assignmentProvider = FutureProvider.autoDispose.family<Assignment, String>(
  (ref, id) => ref.watch(assignmentsRepositoryProvider).assignment(id),
);

final assignmentSubmissionsProvider = FutureProvider.autoDispose.family<List<Submission>, String>(
  (ref, id) => ref.watch(assignmentsRepositoryProvider).submissions(id),
);

final submissionProvider = FutureProvider.autoDispose.family<Submission, String>(
  (ref, id) => ref.watch(assignmentsRepositoryProvider).submission(id),
);

final reviewQueueProvider =
    FutureProvider.autoDispose<List<Submission>>((ref) => ref.watch(assignmentsRepositoryProvider).reviewQueue());

// ---------------- O'quvchi
final studentAssignmentsProvider = FutureProvider.autoDispose<List<StudentAssignment>>(
  (ref) => ref.watch(assignmentsRepositoryProvider).studentAssignments(),
);

final studentAssignmentProvider = FutureProvider.autoDispose.family<StudentAssignment, String>(
  (ref, id) => ref.watch(assignmentsRepositoryProvider).studentAssignment(id),
);

class AssignmentsRepository {
  AssignmentsRepository(this._dio);

  final Dio _dio;

  // Katta fayllar sekin internetda ham yuklanishi uchun
  static final _uploadOptions = Options(sendTimeout: const Duration(minutes: 3), receiveTimeout: const Duration(minutes: 1));

  Future<List<Book>> books() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/books');
        return [for (final b in r.data!) Book.fromJson(b as Map<String, dynamic>)];
      });

  Future<Book> uploadBook({
    required String title,
    required int pageOffset,
    required String filePath,
    required String fileName,
    void Function(double)? onProgress,
  }) =>
      guard(() async {
        final form = FormData.fromMap({
          'title': title,
          'page_offset': pageOffset,
          'file': await MultipartFile.fromFile(filePath, filename: fileName, contentType: DioMediaType('application', 'pdf')),
        });
        final r = await _dio.post<Map<String, dynamic>>(
          '/books',
          data: form,
          options: _uploadOptions,
          onSendProgress: (s, t) => onProgress?.call(t > 0 ? s / t : 0),
        );
        return Book.fromJson(r.data!);
      });

  Future<Assignment> create({
    required String groupId,
    required String title,
    required SourceType sourceType,
    required DateTime dueAt,
    String? instructions,
    bool allowLate = true,
    int latePenaltyPercent = 0,
    String? bookId,
    int? pageFrom,
    int? pageTo,
    String? problems,
    List<String> imagePaths = const [],
    void Function(double)? onProgress,
  }) =>
      guard(() async {
        final form = FormData.fromMap({
          'group_id': groupId,
          'title': title,
          'source_type': sourceType.name,
          'due_at': dueAt.toUtc().toIso8601String(),
          'allow_late': allowLate,
          'late_penalty_percent': latePenaltyPercent,
          if (instructions != null && instructions.isNotEmpty) 'instructions': instructions,
          'book_id': ?bookId,
          'page_from': ?pageFrom,
          'page_to': ?pageTo,
          if (problems != null && problems.isNotEmpty) 'problems': problems,
        });
        for (final (i, path) in imagePaths.indexed) {
          form.files.add(MapEntry('images', await MultipartFile.fromFile(path, filename: 'image_$i.jpg')));
        }
        final r = await _dio.post<Map<String, dynamic>>(
          '/assignments',
          data: form,
          options: _uploadOptions,
          onSendProgress: (s, t) => onProgress?.call(t > 0 ? s / t : 0),
        );
        return Assignment.fromJson(r.data!);
      });

  Future<List<Assignment>> groupAssignments(String groupId) => guard(() async {
        final r = await _dio.get<List<dynamic>>('/groups/$groupId/assignments');
        return [for (final a in r.data!) Assignment.fromJson(a as Map<String, dynamic>)];
      });

  Future<Assignment> assignment(String id) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/assignments/$id');
        return Assignment.fromJson(r.data!);
      });

  Future<Assignment> updateContent(String id, {List<AssignmentItem>? items, List<Criterion>? rubric}) =>
      guard(() async {
        final r = await _dio.put<Map<String, dynamic>>('/assignments/$id/content', data: {
          if (items != null) 'items': [for (final i in items) i.toJson()],
          if (rubric != null) 'rubric': [for (final c in rubric) c.toJson()],
        });
        return Assignment.fromJson(r.data!);
      });

  Future<Assignment> retry(String id) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/assignments/$id/retry');
        return Assignment.fromJson(r.data!);
      });

  Future<Assignment> publish(String id) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/assignments/$id/publish');
        return Assignment.fromJson(r.data!);
      });

  Future<void> delete(String id) => guard(() => _dio.delete<void>('/assignments/$id'));

  Future<List<Submission>> submissions(String assignmentId) => guard(() async {
        final r = await _dio.get<List<dynamic>>('/assignments/$assignmentId/submissions');
        return [for (final s in r.data!) Submission.fromJson(s as Map<String, dynamic>)];
      });

  Future<Submission> submission(String id) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/submissions/$id');
        return Submission.fromJson(r.data!);
      });

  Future<Submission> review(String id, double score, String? comment) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/submissions/$id/review', data: {
          'score': score,
          if (comment != null && comment.isNotEmpty) 'comment': comment,
        });
        return Submission.fromJson(r.data!);
      });

  Future<List<Submission>> reviewQueue() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/teachers/me/review-queue');
        return [for (final s in r.data!) Submission.fromJson(s as Map<String, dynamic>)];
      });

  Future<List<StudentAssignment>> studentAssignments() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/student/assignments');
        return [for (final a in r.data!) StudentAssignment.fromJson(a as Map<String, dynamic>)];
      });

  Future<StudentAssignment> studentAssignment(String id) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/student/assignments/$id');
        return StudentAssignment.fromJson(r.data!);
      });

  Future<StudentAssignment> submit(
    String assignmentId, {
    required List<String> imagePaths,
    String? textAnswer,
    void Function(double)? onProgress,
  }) =>
      guard(() async {
        final form = FormData.fromMap({
          if (textAnswer != null && textAnswer.isNotEmpty) 'text_answer': textAnswer,
        });
        for (final (i, path) in imagePaths.indexed) {
          form.files.add(MapEntry('files', await MultipartFile.fromFile(path, filename: 'page_${i + 1}.jpg')));
        }
        final r = await _dio.post<Map<String, dynamic>>(
          '/student/assignments/$assignmentId/submission',
          data: form,
          options: _uploadOptions,
          onSendProgress: (s, t) => onProgress?.call(t > 0 ? s / t : 0),
        );
        return StudentAssignment.fromJson(r.data!);
      });
}
