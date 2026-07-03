import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/saved_scenario_summary.dart';
import '../services/app_state.dart';

class SavedScenarioSection extends StatefulWidget {
  const SavedScenarioSection({super.key});

  @override
  State<SavedScenarioSection> createState() => _SavedScenarioSectionState();
}

class _SavedScenarioSectionState extends State<SavedScenarioSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshSavedScenarios();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (app.loadingSavedScenarios) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (app.savedScenarios.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.library_books_outlined, size: 20),
                const SizedBox(width: 8),
                Text('保存シナリオ', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'AI生成済みのシナリオをそのままプレイできます',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ...app.savedScenarios.map((s) => _ScenarioTile(summary: s)),
          ],
        ),
      ),
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({required this.summary});

  final SavedScenarioSummary summary;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: summary.isCooperative
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.primaryContainer,
        child: Text(
          '${summary.playerCount}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: summary.isCooperative
                ? theme.colorScheme.onTertiaryContainer
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(summary.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${summary.modeLabel} · ${summary.clueCount}枚 · ${summary.genre}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.play_circle_outline),
      onTap: app.isRunning ? null : () => app.startHostWithSavedScenario(summary.assetPath),
    );
  }
}
