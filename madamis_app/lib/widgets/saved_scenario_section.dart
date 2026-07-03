import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/saved_scenario_summary.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

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
          child: Center(child: Text('シナリオ一覧を読み込み中...')),
        ),
      );
    }

    if (app.savedScenarios.isEmpty) return const SizedBox.shrink();

    return Column(
      children: app.savedScenarios.map((s) => _ScenarioTile(summary: s)).toList(),
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({required this.summary});

  final SavedScenarioSummary summary;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final palette = GenrePalette.forGenre(summary.genre);
    final disabled = app.isRunning;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: disabled ? null : () => app.startHostWithSavedScenario(summary),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(palette.icon, color: palette.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${summary.modeLabel} · ${summary.playerCount}人 · 手がかり${summary.clueCount}枚${summary.isLocal ? ' · アプリ生成' : ''}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.play_circle_fill,
                color: disabled ? Colors.grey : palette.primary,
                size: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
