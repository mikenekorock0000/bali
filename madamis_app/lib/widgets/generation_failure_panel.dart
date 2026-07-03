import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/generation_failure.dart';
import '../models/generation_progress.dart';

class GenerationFailurePanel extends StatelessWidget {
  const GenerationFailurePanel({
    super.key,
    required this.progress,
    this.diagnosticLogPath,
  });

  final GenerationProgress progress;
  final String? diagnosticLogPath;

  @override
  Widget build(BuildContext context) {
    final failure = progress.lastFailure;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failure != null) ...[
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failure.locationLabel,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(label: 'エラーコード', value: failure.code),
                  _InfoRow(label: failure.attemptLabel, value: failure.message),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text('パイプライン進捗', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        ...GenerationStep.steps.map((step) {
          final failed = failure?.step == step.index;
          final reached = progress.currentStep >= step.index;
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              failed
                  ? Icons.cancel
                  : reached
                      ? Icons.check_circle
                      : Icons.circle_outlined,
              color: failed
                  ? theme.colorScheme.error
                  : reached
                      ? Colors.green
                      : Colors.grey,
              size: 20,
            ),
            title: Text(
              '[${step.index}] ${step.label}',
              style: TextStyle(
                fontWeight: failed ? FontWeight.bold : FontWeight.normal,
                color: failed ? theme.colorScheme.error : null,
              ),
            ),
          );
        }),
        if (progress.errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('詳細', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          ...progress.errors.take(8).map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $e', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            ),
          ),
        ],
        if (progress.failureHistory.length > 1) ...[
          const SizedBox(height: 12),
          Text('試行履歴 (${progress.failureHistory.length}件)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          ...progress.failureHistory.map(
            (item) => Text(
              '• 試行${item.attempt}: ${item.locationLabel}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
        ],
        if (diagnosticLogPath != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: diagnosticLogPath!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('診断ログのパスをコピーしました')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text('診断ログ: ${diagnosticLogPath!.split('/').last}', overflow: TextOverflow.ellipsis),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
