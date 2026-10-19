import '../core/models.dart';

/// Capabilities that the client may safely request from an OpenAI-compatible
/// endpoint. Unknown models use the conservative text-only profile.
class ModelCapabilities {
  const ModelCapabilities({
    this.vision = false,
    this.toolCalls = false,
    this.jsonOutput = false,
    this.thinking = false,
    this.webSearch = false,
  });

  static const textOnly = ModelCapabilities();
  static const deepseekFlash = ModelCapabilities(
    vision: true,
    toolCalls: true,
    jsonOutput: true,
    thinking: true,
  );

  final bool vision;
  final bool toolCalls;
  final bool jsonOutput;
  final bool thinking;

  /// Built-in web search is unavailable on this app's Chat Completions route.
  final bool webSearch;

  static ModelCapabilities forModel(String model) {
    return switch (model.trim().toLowerCase()) {
      'deepseek-flash' => deepseekFlash,
      _ => textOnly,
    };
  }

  static ModelCapabilities resolve(AppSettings settings) {
    final defaults = forModel(settings.modelName);
    final overrides = settings.capabilityOverrides;
    final baseUrl = Uri.tryParse(settings.modelBaseUrl.trim());
    final knownDeepSeekEndpoint =
        baseUrl?.host.toLowerCase() == 'api.deepseek.com';
    return ModelCapabilities(
      vision: overrides.vision ?? defaults.vision,
      toolCalls: overrides.toolCalls ?? defaults.toolCalls,
      jsonOutput: overrides.jsonOutput ?? defaults.jsonOutput,
      thinking:
          overrides.thinking ?? (knownDeepSeekEndpoint && defaults.thinking),
      webSearch: defaults.webSearch,
    );
  }
}
