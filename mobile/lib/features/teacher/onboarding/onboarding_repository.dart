import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class OnboardingOption {
  const OnboardingOption({required this.id, required this.label, this.description});

  final String id;
  final String label;
  final String? description;

  factory OnboardingOption.fromJson(Map<String, dynamic> j) => OnboardingOption(
        id: j['id'] as String,
        label: j['label'] as String,
        description: j['description'] as String?,
      );
}

enum QuestionType { single, multi, text }

class OnboardingQuestion {
  const OnboardingQuestion({
    required this.id,
    required this.type,
    required this.required,
    required this.title,
    this.hint,
    this.icon,
    this.options = const [],
    this.maxLength,
  });

  final String id;
  final QuestionType type;
  final bool required;
  final String title;
  final String? hint;
  final String? icon;
  final List<OnboardingOption> options;
  final int? maxLength;

  factory OnboardingQuestion.fromJson(Map<String, dynamic> j) => OnboardingQuestion(
        id: j['id'] as String,
        type: QuestionType.values.asNameMap()[j['type']] ?? QuestionType.text,
        required: j['required'] as bool? ?? false,
        title: j['title'] as String,
        hint: j['hint'] as String?,
        icon: j['icon'] as String?,
        options: [
          for (final o in (j['options'] as List? ?? const [])) OnboardingOption.fromJson(o as Map<String, dynamic>),
        ],
        maxLength: j['max_length'] as int?,
      );
}

final onboardingRepositoryProvider =
    Provider<OnboardingRepository>((ref) => OnboardingRepository(ref.watch(dioProvider)));

final onboardingQuestionsProvider = FutureProvider.autoDispose<List<OnboardingQuestion>>(
  (ref) => ref.watch(onboardingRepositoryProvider).questions(),
);

/// Oldin berilgan javoblar (sozlamalardan tahrirlashda oldindan to'ldirish uchun)
final onboardingAnswersProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(onboardingRepositoryProvider).myAnswers(),
);

class OnboardingRepository {
  OnboardingRepository(this._dio);

  final Dio _dio;

  Future<List<OnboardingQuestion>> questions({String lang = 'uz'}) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>(
          '/teachers/onboarding/questions',
          queryParameters: {'lang': lang},
        );
        return [
          for (final q in r.data!['questions'] as List) OnboardingQuestion.fromJson(q as Map<String, dynamic>),
        ];
      });

  Future<Map<String, dynamic>> myAnswers() => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/teachers/me/onboarding');
        return Map<String, dynamic>.from(r.data!['answers'] as Map);
      });

  Future<void> save(Map<String, dynamic> answers) => guard(() async {
        await _dio.put<void>('/teachers/me/onboarding', data: {'answers': answers});
      });
}
