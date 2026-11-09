import '../core/chat_models.dart';
import '../core/models.dart';

/// Runtime policy derived from the device-wide full-agent switch.
///
/// The switch is an overlay: it never rewrites the policy stored on an
/// existing conversation, so disabling it restores the user's previous
/// conversation-level choices exactly.
class AgentExecutionProfile {
  const AgentExecutionProfile({required this.fullAgentMode});

  factory AgentExecutionProfile.fromSettings(AppSettings settings) =>
      AgentExecutionProfile(fullAgentMode: settings.fullAgentMode);

  final bool fullAgentMode;

  AiPolicy policyFor(Conversation? conversation, AppSettings settings) {
    if (fullAgentMode) return AiPolicy.forPreset(AiPolicyPreset.fullAccess);
    return conversation?.effectiveAiPolicy ?? settings.effectiveDefaultAiPolicy;
  }

  bool get unboundedRetrieval => fullAgentMode;

  bool get retryTransientIndefinitely => fullAgentMode;

  bool get autoResumeSafeTasks => fullAgentMode;

  bool get continueTruncatedOutput => fullAgentMode;
}
