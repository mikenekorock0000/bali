import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/generation_progress.dart';
import '../services/app_state.dart';
import '../widgets/generation_failure_panel.dart';

class GeneratingScreen extends StatelessWidget {
  const GeneratingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final progress = app.generationProgress;
    final failed = progress.status == GenerationStatus.failed;

    return Scaffold(
      body: SafeArea(
        child: failed
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '生成に失敗しました',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    GenerationFailurePanel(
                      progress: progress,
                      diagnosticLogPath: app.generationDiagnosticLogPath,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: app.goToScenarioConfig,
                      child: const Text('設定に戻る'),
                    ),
                    TextButton(
                      onPressed: app.goToHome,
                      child: const Text('ホームに戻る'),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Icon(
                      Icons.auto_awesome,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'シナリオ生成中',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 32),
                    LinearProgressIndicator(value: progress.progress),
                    const SizedBox(height: 16),
                    Text(
                      progress.message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (progress.attempt > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '再生成 ${progress.attempt}/${progress.maxAttempts}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    const SizedBox(height: 24),
                    ...GenerationStep.steps.map((step) {
                      final done = progress.currentStep > step.index;
                      final current = progress.currentStep == step.index;
                      return ListTile(
                        leading: Icon(
                          done
                              ? Icons.check_circle
                              : current
                                  ? Icons.hourglass_top
                                  : Icons.circle_outlined,
                          color: done
                              ? Colors.green
                              : current
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                        ),
                        title: Text(
                          '[${step.index}/${GenerationStep.steps.length}] ${step.label}',
                          style: TextStyle(
                            fontWeight: current ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    }),
                    const Spacer(),
                  ],
                ),
              ),
      ),
    );
  }
}
