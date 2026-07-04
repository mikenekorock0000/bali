class SimTestStep {
  SimTestStep({
    required this.id,
    required this.label,
    required this.passed,
    this.detail,
    this.durationMs,
  });

  final String id;
  final String label;
  final bool passed;
  final String? detail;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'passed': passed,
        'detail': detail,
        'durationMs': durationMs,
      };
}

class SimTestReport {
  SimTestReport({
    required this.steps,
    required this.startedAt,
    required this.finishedAt,
  });

  final List<SimTestStep> steps;
  final DateTime startedAt;
  final DateTime finishedAt;

  bool get allPassed => steps.every((s) => s.passed);
  int get passCount => steps.where((s) => s.passed).length;
  int get failCount => steps.where((s) => !s.passed).length;
}
