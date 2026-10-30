import '../../core/models.dart';
import '../../core/table_models.dart';

class CaptureOutcome {
  const CaptureOutcome._({
    required this.status,
    this.document,
    this.tableEntry,
    this.capture,
    this.usedModel = false,
    this.warning,
    this.message,
  });

  const CaptureOutcome.created(
    ResultDocument document, {
    bool usedModel = false,
    String? warning,
  }) : this._(
         status: CaptureOutcomeStatus.created,
         document: document,
         usedModel: usedModel,
         warning: warning,
       );

  const CaptureOutcome.tableCreated(
    TableEntryDocument entry, {
    bool usedModel = false,
    String? warning,
  }) : this._(
         status: CaptureOutcomeStatus.created,
         tableEntry: entry,
         usedModel: usedModel,
         warning: warning,
       );

  const CaptureOutcome.review(CaptureRecord capture, {String? warning})
    : this._(
        status: CaptureOutcomeStatus.review,
        capture: capture,
        warning: warning,
      );

  const CaptureOutcome.failure(String message)
    : this._(status: CaptureOutcomeStatus.failure, message: message);

  final CaptureOutcomeStatus status;
  final ResultDocument? document;
  final TableEntryDocument? tableEntry;
  final CaptureRecord? capture;
  final bool usedModel;
  final String? warning;
  final String? message;
}

enum CaptureOutcomeStatus { created, review, failure }
