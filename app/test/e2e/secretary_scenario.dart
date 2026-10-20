import 'realistic_scenario.dart';

class SecretaryScenario {
  const SecretaryScenario({
    required this.id,
    required this.platform,
    required this.category,
    required this.title,
    required this.assertions,
    required this.steps,
  });

  final String id;
  final RealisticPlatform platform;
  final String category;
  final String title;
  final String assertions;
  final List<String> steps;

  factory SecretaryScenario.fromMap(Map<String, Object?> json) {
    return SecretaryScenario(
      id: json['id'] as String,
      platform: RealisticPlatform.parse(json['platform'] as String),
      category: json['category'] as String,
      title: json['title'] as String,
      assertions: json['assertions'] as String,
      steps: (json['steps'] as List<Object?>).cast<String>(),
    );
  }
}

const secretaryCategoryCounts = <String, int>{
  'navigation': 10,
  'permissions': 12,
  'retrieval': 18,
  'actions': 14,
  'globalApproval': 18,
  'datesSync': 10,
  'model': 8,
  'files': 6,
  'voice': 4,
};
