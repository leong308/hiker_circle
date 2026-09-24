import 'package:cloud_functions/cloud_functions.dart';

typedef HikerCircleAssistantCallable =
    Future<Map<String, dynamic>> Function(String question);

class HikerCircleAssistantSource {
  const HikerCircleAssistantSource({required this.id, required this.title});

  final String id;
  final String title;

  factory HikerCircleAssistantSource.fromMap(Map<String, dynamic> map) {
    return HikerCircleAssistantSource(
      id: map['id']?.toString().trim() ?? '',
      title: map['title']?.toString().trim() ?? '',
    );
  }
}

class HikerCircleAssistantAnswer {
  const HikerCircleAssistantAnswer({
    required this.answer,
    required this.sources,
    required this.responseMode,
    this.notice,
  });

  final String answer;
  final List<HikerCircleAssistantSource> sources;
  final String responseMode;
  final String? notice;

  bool get isEmergency => responseMode == 'curated_emergency';
  bool get isCuratedFallback => responseMode == 'curated_fallback';

  factory HikerCircleAssistantAnswer.fromMap(Map<String, dynamic> map) {
    final answer = map['answer']?.toString().trim() ?? '';
    if (answer.isEmpty) {
      throw const HikerCircleAssistantException(
        'The assistant returned an empty answer. Try again.',
      );
    }
    final sourceValues = map['sources'];
    final sources = sourceValues is List
        ? sourceValues
              .whereType<Map>()
              .map(
                (value) => HikerCircleAssistantSource.fromMap(
                  Map<String, dynamic>.from(value),
                ),
              )
              .where(
                (source) => source.id.isNotEmpty && source.title.isNotEmpty,
              )
              .toList(growable: false)
        : const <HikerCircleAssistantSource>[];
    return HikerCircleAssistantAnswer(
      answer: answer,
      sources: sources,
      responseMode: map['responseMode']?.toString().trim() ?? 'unknown',
      notice: switch (map['notice']?.toString().trim()) {
        final value? when value.isNotEmpty => value,
        _ => null,
      },
    );
  }
}

class HikerCircleAssistantException implements Exception {
  const HikerCircleAssistantException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class HikerCircleAssistantRepository {
  HikerCircleAssistantRepository({
    FirebaseFunctions? functions,
    HikerCircleAssistantCallable? callable,
  }) : _callable =
           callable ??
           _firebaseCallable(
             functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
           );

  final HikerCircleAssistantCallable _callable;

  static HikerCircleAssistantCallable _firebaseCallable(
    FirebaseFunctions functions,
  ) {
    return (question) async {
      final result = await functions
          .httpsCallable(
            'askHikerCircleAssistant',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call(<String, dynamic>{'question': question});
      final data = result.data;
      if (data is! Map) {
        throw const HikerCircleAssistantException(
          'The assistant response could not be read.',
        );
      }
      return Map<String, dynamic>.from(data);
    };
  }

  Future<HikerCircleAssistantAnswer> ask(String question) async {
    final normalized = question.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length < 3) {
      throw const HikerCircleAssistantException(
        'Enter a little more detail in your question.',
        code: 'invalid-argument',
      );
    }
    if (normalized.length > 480) {
      throw const HikerCircleAssistantException(
        'Keep the question under 480 characters.',
        code: 'invalid-argument',
      );
    }
    try {
      return HikerCircleAssistantAnswer.fromMap(await _callable(normalized));
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleAssistantException(
        _friendlyMessage(error.code, error.message),
        code: error.code,
      );
    } on HikerCircleAssistantException {
      rethrow;
    } catch (_) {
      throw const HikerCircleAssistantException(
        'The assistant could not be reached. Check your connection and try again.',
        code: 'unavailable',
      );
    }
  }

  static String _friendlyMessage(String code, String? serverMessage) {
    final message = serverMessage?.trim();
    if (message != null && message.isNotEmpty) return message;
    return switch (code) {
      'unauthenticated' => 'Sign in before using the HikerCircle assistant.',
      'resource-exhausted' =>
        'The unpaid assistant quota is currently exhausted. Try again later.',
      'deadline-exceeded' =>
        'The assistant took too long to respond. Try again.',
      'failed-precondition' =>
        'The HikerCircle assistant is not configured yet.',
      'invalid-argument' => 'Review the question and try again.',
      _ => 'The assistant could not answer right now. Try again later.',
    };
  }
}
