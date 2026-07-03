import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/scenario_config.dart';
import '../services/app_state.dart';

class GeneratingScreen extends StatelessWidget {
  const GeneratingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final progress = app.generationProgress;
    final failed = progress.status == GenerationStatus.failed;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                failed ? Icons.error_outline : Icons.auto_awesome,
                size: 64,
                color: failed
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                failed ? '生成に失敗しました' : 'シナリオ生成中',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),
              if (!failed) ...[
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
                      '[${step.index}/6] ${step.label}',
                      style: TextStyle(
                        fontWeight: current ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }),
              ] else ...[
                if (app.generationError != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(app.generationError!),
                    ),
                  ),
                if (progress.errors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ...progress.errors.map((e) => Text('• $e', style: const TextStyle(color: Colors.grey))),
                ],
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
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
