import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_phase.dart';
import '../models/game_session.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
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
    final scenario = session.scenario;

    return Theme(
      data: AppTheme.forGenre(scenario.genre),
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(scenario.title, style: const TextStyle(fontSize: 16)),
              Text(
                'フェーズ: ${phase.label}',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PhaseGuideBanner(phase: phase),
                        const SizedBox(height: 16),
                        Expanded(child: _PhaseContent(phase: phase, session: session)),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: Colors.white.withValues(alpha: 0.1)),
                Expanded(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('プレイヤー状況', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Expanded(
                          child: PlayerList(players: session.players, showDetails: true),
                        ),
                        if (phase == GamePhase.results) ...[
                          const Divider(),
                          FilledButton.icon(
                            onPressed: () => app.stopHost(),
                            icon: const Icon(Icons.home),
                            label: const Text('ホームに戻る'),
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
      ),
    );
  }
}

class _PhaseGuideBanner extends StatelessWidget {
  const _PhaseGuideBanner({required this.phase});

  final GamePhase phase;

  String get _guide => switch (phase) {
        GamePhase.synopsis => '全員があらすじを読んでいます。スマホで「確認しました」を押すのを待ちます。',
        GamePhase.privateReading => '各プレイヤーが個人台本を読んでいます。「読了しました」を待ちます。',
        GamePhase.investigation => 'プレイヤーが手がかりを集めています。トークンを使って山札から引けます。',
        GamePhase.discussion => '自由に話し合う時間です。タイマー終了で次のフェーズへ進みます。',
        GamePhase.accusation => 'プレイヤーが推理を発表するフェーズです（任意）。',
        GamePhase.voting => '犯人だと思う人物への投票を受け付けています。',
        GamePhase.truthReveal => '真相を公開しています。自動で次へ進みます。',
        GamePhase.epilogue => '後日談を表示しています。',
        GamePhase.results => '結果発表です。全員の投票結果を確認できます。',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    if (_guide.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(_guide, style: const TextStyle(fontSize: 14))),
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
          subtitle: '全員に同じ内容が表示されています',
          content: session.scenario.synopsis,
        ),
      GamePhase.privateReading => _InfoCard(
          icon: Icons.lock,
          title: '個人台本',
          subtitle: '各プレイヤーのスマホに秘密情報が表示されています',
          content: 'ここには表示されません。全員が「読了」するまでお待ちください。',
        ),
      GamePhase.investigation => _InfoCard(
          icon: Icons.search,
          title: '調査フェーズ',
          subtitle: '手がかりの取得・公開・譲渡が可能',
          content: '山札残り: ${session.deckClues.length}枚\n'
              '全員公開済み: ${session.globalPublicClues.length}枚',
        ),
      GamePhase.discussion => _InfoCard(
          icon: Icons.forum,
          title: '議論フェーズ',
          subtitle: '口頭で話し合い、推理を練る時間',
          content: 'タイマーが終わると自動で推理発表フェーズへ進みます。',
        ),
      GamePhase.accusation => _InfoCard(
          icon: Icons.record_voice_over,
          title: '推理発表',
          subtitle: '任意 — 犯人と理由を発表',
          content: '発表済み: ${session.accusations.length} / ${session.players.length}人',
        ),
      GamePhase.voting => _InfoCard(
          icon: Icons.how_to_vote,
          title: '投票',
          subtitle: '犯人だと思う人物に投票',
          content: '投票済み: ${session.votes.length} / ${session.players.length}人',
        ),
      GamePhase.truthReveal => _TruthCard(session: session),
      GamePhase.epilogue => _InfoCard(
          icon: Icons.auto_stories,
          title: '後日談',
          subtitle: '事件のその後',
          content: session.scenario.epilogue,
        ),
      GamePhase.results => _ResultsCard(session: session),
      _ => const SizedBox.shrink(),
    };
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.content,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
              const SizedBox(height: 20),
              Text(content, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
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
        .where((c) => c.id == truth.culpritId)
        .firstOrNull;

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('真相', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              if (culprit != null)
                Text('犯人: ${culprit.name}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _truthRow('動機', truth.motive),
              _truthRow('手法', truth.method),
              const SizedBox(height: 16),
              Text(truth.explanation, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }

  Widget _truthRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 15),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
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
    final culprit = session.scenario.characters
        .where((c) => c.id == culpritId)
        .firstOrNull;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('結果', style: Theme.of(context).textTheme.headlineSmall),
            if (culprit != null) ...[
              const SizedBox(height: 8),
              Text('真犯人: ${culprit.name}', style: TextStyle(color: Colors.grey.shade400)),
            ],
            const SizedBox(height: 16),
            ...session.votes.map((vote) {
              final player = session.players.where((p) => p.id == vote.playerId).firstOrNull;
              final char = session.scenario.characters
                  .where((c) => c.id == vote.targetCharacterId)
                  .firstOrNull;
              final correct = vote.targetCharacterId == culpritId;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  correct ? Icons.check_circle : Icons.cancel,
                  color: correct ? Colors.green : Colors.red,
                ),
                title: Text(player?.nickname ?? '不明'),
                subtitle: Text('投票先: ${char?.name ?? vote.targetCharacterId}'),
              );
            }),
          ],
        ),
      ),
    );
  }
}
