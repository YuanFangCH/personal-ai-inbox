import '../core/deterministic_parser.dart';
import '../core/models.dart';
import '../data/settings_service.dart';
import 'model_client.dart';

class CaptureAnalysis {
  const CaptureAnalysis({
    required this.candidate,
    required this.usedModel,
    this.warning,
  });

  final ClassificationCandidate candidate;
  final bool usedModel;
  final String? warning;
}

class CaptureService {
  CaptureService({
    required SettingsService settings,
    required DeterministicParser parser,
    ModelClient? modelClient,
  }) : _settings = settings,
       _parser = parser,
       _modelClient = modelClient ?? ModelClient();

  final SettingsService _settings;
  final DeterministicParser _parser;
  final ModelClient _modelClient;

  Future<CaptureAnalysis> analyze({
    required String text,
    required DateTime now,
    required bool preferModel,
  }) async {
    final settings = await _settings.load();
    final deterministic = _parser.parse(text, now);
    if (!preferModel || !settings.hasModelKey) {
      return CaptureAnalysis(candidate: deterministic, usedModel: false);
    }

    final apiKey = await _settings.readModelKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      return CaptureAnalysis(candidate: deterministic, usedModel: false);
    }

    try {
      final candidate = await _modelClient.classify(
        text: text,
        now: now,
        configuration: ModelConfiguration(
          baseUrl: settings.modelBaseUrl,
          model: settings.modelName,
          apiKey: apiKey,
        ),
      );
      final merged = _mergeWithRules(
        candidate: candidate,
        rules: deterministic,
      );
      return CaptureAnalysis(candidate: merged, usedModel: true);
    } catch (error) {
      return CaptureAnalysis(
        candidate: deterministic.copyWithForReview(
          reviewReason: '云端模型不可用，已按本地规则整理',
        ),
        usedModel: false,
        warning: error.toString(),
      );
    }
  }

  ClassificationCandidate _mergeWithRules({
    required ClassificationCandidate candidate,
    required ClassificationCandidate rules,
  }) {
    if (candidate.type == rules.type) {
      return candidate;
    }
    if (rules.confidence >= 0.85 && !rules.needsReview) {
      return rules;
    }
    return ClassificationCandidate(
      type: candidate.type,
      title: candidate.title,
      confidence: candidate.confidence,
      summary: candidate.summary,
      tags: candidate.tags,
      start: candidate.start,
      end: candidate.end,
      due: candidate.due,
      allDay: candidate.allDay,
      recurrence: candidate.recurrence,
      needsReview: true,
      reviewReason: '本地规则与模型分类不一致',
    );
  }
}

extension on ClassificationCandidate {
  ClassificationCandidate copyWithForReview({required String reviewReason}) {
    return ClassificationCandidate(
      type: type,
      title: title,
      confidence: confidence,
      summary: summary,
      tags: tags,
      start: start,
      end: end,
      due: due,
      allDay: allDay,
      recurrence: recurrence,
      needsReview: true,
      reviewReason: reviewReason,
    );
  }
}
