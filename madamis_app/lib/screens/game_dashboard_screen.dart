import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_phase.dart';
import '../models/game_session.dart';
import '../services/app_state.dart';
import '../widgets/phase_overlay.dart';
import '../widgets/phase_timer.dart';
import '../widgets/player_list.dart';

class GameDashboardScreen extends StatelessWidget {
  const GameDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final session = app.engine.session;
    if (session == null) return const SizedBox.shrink();

    final phase = session.phase;

    return Scaffold(
      appBar: AppBar(
        title: Text('${session.scenario.title} — ${phase.label}'),
        actions: [
          if (session.phaseTimeoutAt != null)
            PhaseTimer(timeoutAt: session.phaseTimeoutAt!),
          const SizedBox(width: 16),
        ],
      ),
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _PhaseContent(phase: phase, session: session),
                ),
              ),
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('プレイヤー', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Expanded(child: PlayerList(players: session.players, showDetails: true)),
                      if (phase == GamePhase.results) ...[
                        const Divider(),
                        FilledButton(
                          onPressed: () => app.stopHost(),
                          child: const Text('ゲーム終了'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const PhaseOverlay(),
        ],
      ),
    );
  }
}

class _PhaseContent extends StatelessWidget {
  const _PhaseContent({required this.phase, required this.session});

  final GamePhase phase;
  final GameSession session;

  @override
  Widget build(BuildContext context) {
    return switch (phase) {
      GamePhase.synopsis => _InfoCard(
          icon: Icons.menu_book,
          title: 'あらすじ',
          content: session.scenario.synopsis,
        ),
      GamePhase.privateReading => _InfoCard(
          icon: Icons.lock,
          title: '個人台本',
          content: '各プレイヤーが自分の台本を読んでいます...',
        ),
      GamePhase.investigation => _InfoCard(
          icon: Icons.search,
          title: '調査フェーズ',
          content: '残り手がかり: ${session.deckClues.length}枚\n'
              '公開済み: ${session.globalPublicClues.length}枚',
        ),
      GamePhase.discussion => _InfoCard(
          icon: Icons.forum,
          title: '議論フェーズ',
          content: 'プレイヤー同士が議論しています...',
        ),
      GamePhase.accusation => _InfoCard(
          icon: Icons.record_voice_over,
          title: '推理発表',
          content: '発表数: ${session.accusations.length}/${session.players.length}',
        ),
      GamePhase.voting => _InfoCard(
          icon: Icons.how_to_vote,
          title: '投票',
          content: '投票数: ${session.votes.length}/${session.players.length}',
        ),
      GamePhase.truthReveal => _TruthCard(session: session),
      GamePhase.epilogue => _InfoCard(
          icon: Icons.auto_stories,
          title: '後日談',
          content: session.scenario.epilogue,
        ),
      GamePhase.results => _ResultsCard(session: session),
      _ => const SizedBox.shrink(),
    };
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.content});

  final IconData icon;
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Text(content, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _TruthCard extends StatelessWidget {
  const _TruthCard({required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final truth = session.scenario.truth;
    final culprit = session.scenario.characters
        .firstWhere((c) => c.id == truth.culpritId);

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⚡ 真相', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Text('犯人: ${culprit.name}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('動機: ${truth.motive}'),
            const SizedBox(height: 8),
            Text('手法: ${truth.method}'),
            const SizedBox(height: 16),
            Text(truth.explanation),
          ],
        ),
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final culpritId = session.scenario.truth.culpritId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🏆 結果', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            ...session.votes.map((vote) {
              final player = session.players.firstWhere((p) => p.id == vote.playerId);
              final char = session.scenario.characters
                  .firstWhere((c) => c.id == vote.targetCharacterId);
              final correct = vote.targetCharacterId == culpritId;
              return ListTile(
                title: Text(player.nickname),
                subtitle: Text('投票: ${char.name}'),
                trailing: Icon(
                  correct ? Icons.check_circle : Icons.cancel,
                  color: correct ? Colors.green : Colors.red,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
