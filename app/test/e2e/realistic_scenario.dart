/// Data model for the realistic end-to-end scenario matrix.
///
/// A scenario is a deterministic list of user-visible steps plus assertions.
/// The same data drives the host smoke run, both Android AVD legs and the
/// Windows desktop leg, so the matrix cannot drift between platforms.
library;

/// Supported platforms. `phone` and `tablet` run on Android AVDs, `windows`
/// runs natively on the Windows desktop renderer.
enum RealisticPlatform {
  phone,
  tablet,
  windows;

  static RealisticPlatform parse(String value) {
    return RealisticPlatform.values.firstWhere(
      (platform) => platform.name == value,
      orElse: () => throw FormatException('Unknown platform: $value'),
    );
  }

  /// Logical viewport used when a platform is simulated on the host.
  ({double width, double height, double pixelRatio}) get hostViewport {
    return switch (this) {
      RealisticPlatform.phone => (width: 411, height: 914, pixelRatio: 2.625),
      RealisticPlatform.tablet => (width: 1280, height: 800, pixelRatio: 1.0),
      RealisticPlatform.windows => (width: 1440, height: 900, pixelRatio: 1.0),
    };
  }

  bool get isAndroid => this != RealisticPlatform.windows;
}

/// How the scripted model answers a chat request.
enum ChatScript {
  /// Streams text and a valid `[DONE]` terminal.
  text,

  /// Streams text and a `create_result` tool call, then `[DONE]`.
  tool,

  /// Streams text and a `create_result` tool call, then closes without `[DONE]`.
  toolNoDone,

  /// Streams text and closes the connection without `[DONE]`.
  noDone,

  /// Fails the request with HTTP 500 so the UI offers a retry.
  httpError,

  /// Emits chunks slowly so the user can stop generation.
  slow,
}

class RealisticStep {
  const RealisticStep(this.op, [this.args = const {}]);

  final String op;
  final Map<String, Object?> args;

  String? get string => args['value'] as String?;
  int? get intValue => (args['value'] as num?)?.toInt();
  bool? get boolValue => args['value'] as bool?;
}

class RealisticScenario {
  const RealisticScenario({
    required this.id,
    required this.platform,
    required this.category,
    required this.title,
    required this.theme,
    required this.fontScale,
    required this.steps,
    this.reply = '已记录。',
    this.chatScript = ChatScript.text,
    this.toolPayload = const {},
  });

  final String id;
  final RealisticPlatform platform;
  final String category;
  final String title;
  final String theme;
  final double fontScale;
  final List<RealisticStep> steps;
  final String reply;
  final ChatScript chatScript;
  final Map<String, Object?> toolPayload;

  bool get isDark => theme == 'dark';

  factory RealisticScenario.fromMap(Map<String, Object?> json) {
    final steps = (json['steps'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(
          (step) => RealisticStep(
            step['op'] as String,
            (step['args'] as Map<Object?, Object?>? ?? const {}).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .toList(growable: false);
    return RealisticScenario(
      id: json['id'] as String,
      platform: RealisticPlatform.parse(json['platform'] as String),
      category: json['category'] as String,
      title: json['title'] as String,
      theme: json['theme'] as String? ?? 'light',
      fontScale: (json['fontScale'] as num? ?? 1.0).toDouble(),
      steps: steps,
      reply: json['reply'] as String? ?? '已记录。',
      chatScript: ChatScript.values.byName(
        json['chatScript'] as String? ?? 'text',
      ),
      toolPayload: (json['toolPayload'] as Map<Object?, Object?>? ?? const {})
          .map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

/// Ops the runner understands. The integrity test rejects anything else so a
/// generated scenario can never silently do nothing.
const supportedOps = <String, int>{
  'nav': 0,
  'capture': 0,
  'calendarMode': 0,
  'calendarSection': 0,
  'quickCreate': 0,
  'toggleTodo': 0,
  'openDoc': 0,
  'searchKnowledge': 0,
  'newChat': 0,
  'startChat': 0,
  'retryChat': 0,
  'stopChat': 0,
  'undoAutoRecord': 0,
  'tapText': 0,
  'sync': 0,
  'resolveConflict': 0,
  'theme': 0,
  'imageEgress': 0,
  'restart': 0,
  'scroll': 0,
  'seed': 0,
  'secretaryCase': 0,
  'assert': 0,
};

/// Assertion kinds the runner understands.
const supportedAsserts = <String>{
  'resultCount',
  'typeCount',
  'titleExists',
  'titleMissing',
  'reviewCount',
  'conflictCount',
  'textVisible',
  'bodyContains',
  'todoDone',
  'themeDark',
  'imageEgress',
  'noException',
  'conversationCount',
  'chatReplyContains',
  'assistantStatus',
  'caseState',
  'caseVisibleTitle',
};
