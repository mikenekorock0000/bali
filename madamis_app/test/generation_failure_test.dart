import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/models/generation_failure.dart';
import 'package:madamis_app/models/generation_progress.dart';
import 'package:madamis_app/services/generation_diagnostic_log.dart';

void main() {
  test('GenerationFailure validation extracts check code', () {
    final failure = GenerationFailure.validation(
      step: 5,
      attempt: 2,
      errors: ['[clue_reachability] critical手がかりに犯行情報が不足'],
      repairPass: 4,
      exhaustedRepairs: true,
    );

    expect(failure.code, 'validation.clue_reachability');
    expect(failure.stepLabel, '整合性チェック');
    expect(failure.phaseLabel, '整合性チェック');
    expect(failure.locationLabel, contains('ステップ5'));
    expect(failure.summary, contains('整合性チェックが修復上限に達しました'));
  });

  test('GenerationFailure audit uses failed check name', () {
    final failure = GenerationFailure.audit(
      attempt: 3,
      issues: ['犯人特定に必要な手がかりが不足'],
      failedCheckNames: ['solvable'],
      afterRepair: true,
    );

    expect(failure.code, 'audit.solvable');
    expect(failure.step, 6);
    expect(failure.phase, GenerationPhase.auditRepair);
  });

  test('formatGenerationFailureReport includes history', () {
    final progress = GenerationProgress(
      status: GenerationStatus.failed,
      currentStep: 5,
      lastFailure: GenerationFailure.validation(
        step: 5,
        attempt: 2,
        errors: ['[clue_reachability] 不足'],
        exhaustedRepairs: true,
      ),
      failureHistory: [
        GenerationFailure.validation(
          step: 5,
          attempt: 1,
          errors: ['[required_fields] alibi不足'],
          exhaustedRepairs: true,
        ),
        GenerationFailure.validation(
          step: 5,
          attempt: 2,
          errors: ['[clue_reachability] 不足'],
          exhaustedRepairs: true,
        ),
      ],
    );

    final report = formatGenerationFailureReport(progress);
    expect(report, contains('失敗箇所:'));
    expect(report, contains('validation.clue_reachability'));
    expect(report, contains('試行履歴 (2件)'));
  });
}
