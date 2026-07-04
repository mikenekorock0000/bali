import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/scenario.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/hotspot_info_card.dart';
import '../widgets/player_list.dart';
import '../widgets/ui_helpers.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  int _lobbyStep(AppState app) {
    if (app.canStart) return 2;
    if (app.playerCount >= 1) return 1;
    return 0;
  }

  bool _isCompact(BoxConstraints constraints) {
    return constraints.maxHeight < 720 || constraints.maxWidth < 900;
  }

  double _qrSize(BoxConstraints constraints, {required bool compact}) {
    if (compact) {
      return (constraints.maxWidth * 0.4).clamp(140.0, 190.0);
    }
    final leftPanelWidth = constraints.maxWidth * 0.6;
    return (leftPanelWidth * 0.45).clamp(160.0, 200.0);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scenario = app.engine.session?.scenario;
    final joinUrl = app.joinUrl ?? '';
    final genre = scenario?.genre ?? '洋館';

    return Theme(
      data: AppTheme.forGenre(genre),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ロビー — 参加待ち'),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('ゲームを終了'),
                    content: const Text('サーバーを停止してホームに戻りますか？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('終了する')),
                    ],
                  ),
                );
                if (ok == true && context.mounted) app.stopHost();
              },
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('終了'),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compact = _isCompact(constraints);
            if (compact) {
              return _CompactLobby(
                app: app,
                scenario: scenario,
                joinUrl: joinUrl,
                constraints: constraints,
                lobbyStep: _lobbyStep(app),
                qrSize: _qrSize(constraints, compact: true),
              );
            }
            return _WideLobby(
              app: app,
              scenario: scenario,
              joinUrl: joinUrl,
              constraints: constraints,
              lobbyStep: _lobbyStep(app),
              qrSize: _qrSize(constraints, compact: false),
            );
          },
        ),
      ),
    );
  }
}

class _QrJoinCard extends StatelessWidget {
  const _QrJoinCard({
    required this.joinUrl,
    required this.qrSize,
    this.padding = 16,
  });

  final String joinUrl;
  final double qrSize;
  final double padding;

  @override
  Widget build(BuildContext context) {
    if (joinUrl.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '参加用QRコード',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'スマホのカメラで読み取ってください',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: QrImageView(
              data: joinUrl,
              version: QrVersions.auto,
              size: qrSize,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(
          joinUrl,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    required this.app,
    required this.scenario,
    this.dense = false,
  });

  final AppState app;
  final Scenario? scenario;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('参加者', style: Theme.of(context).textTheme.titleLarge),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${app.playerCount} / ${scenario?.playerCount ?? 4} 人',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '✓ 配役済み = キャラが自動割り当て済み',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 12),
        if (dense)
          PlayerList(
            players: app.engine.session?.players ?? [],
            characterNames: {
              for (final c in scenario?.characters ?? []) c.id: c.name,
            },
            shrinkWrap: true,
          )
        else
          Expanded(
            child: PlayerList(
              players: app.engine.session?.players ?? [],
              characterNames: {
                for (final c in scenario?.characters ?? []) c.id: c.name,
              },
            ),
          ),
        const SizedBox(height: 16),
        if (app.canStart)
          FilledButton.icon(
            onPressed: app.startGame,
            icon: const Icon(Icons.play_arrow),
            label: const Text('ゲーム開始'),
          )
        else
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.hourglass_empty),
            label: Text(
              app.playerCount < 2
                  ? 'あと${2 - app.playerCount}人必要'
                  : '全員の参加を待っています',
            ),
          ),
      ],
    );
  }
}

class _CompactLobby extends StatelessWidget {
  const _CompactLobby({
    required this.app,
    required this.scenario,
    required this.joinUrl,
    required this.constraints,
    required this.lobbyStep,
    required this.qrSize,
  });

  final AppState app;
  final Scenario? scenario;
  final String joinUrl;
  final BoxConstraints constraints;
  final int lobbyStep;
  final double qrSize;

  @override
  Widget build(BuildContext context) {
    final s = scenario;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s != null)
            ScenarioHeaderCard(
              title: s.title,
              genre: s.genre,
              playerCount: s.playerCount,
              isCooperative: s.gameMode == 'cooperative',
              subtitle: 'ルーム番号 ${app.roomId}',
            ),
          const SizedBox(height: 12),
          _QrJoinCard(joinUrl: joinUrl, qrSize: qrSize, padding: 12),
          const SizedBox(height: 16),
          ActionStepsCard(
            currentStep: lobbyStep,
            steps: const [
              'プレイヤーにQRコードを見せて参加してもらう',
              '参加と同時に配役が自動で割り当てられる',
              '「ゲーム開始」を押す',
            ],
          ),
          const SizedBox(height: 12),
          const HotspotInfoBanner(),
          const SizedBox(height: 16),
          _PlayerPanel(app: app, scenario: scenario, dense: true),
        ],
      ),
    );
  }
}

class _WideLobby extends StatelessWidget {
  const _WideLobby({
    required this.app,
    required this.scenario,
    required this.joinUrl,
    required this.constraints,
    required this.lobbyStep,
    required this.qrSize,
  });

  final AppState app;
  final Scenario? scenario;
  final String joinUrl;
  final BoxConstraints constraints;
  final int lobbyStep;
  final double qrSize;

  @override
  Widget build(BuildContext context) {
    final s = scenario;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s != null)
                  ScenarioHeaderCard(
                    title: s.title,
                    genre: s.genre,
                    playerCount: s.playerCount,
                    isCooperative: s.gameMode == 'cooperative',
                    subtitle: 'ルーム番号 ${app.roomId}',
                  ),
                const SizedBox(height: 12),
                ActionStepsCard(
                  currentStep: lobbyStep,
                  steps: const [
                    'プレイヤーにQRコードを見せて参加してもらう',
                    '参加と同時に配役が自動で割り当てられる',
                    '「ゲーム開始」を押す',
                  ],
                ),
                const SizedBox(height: 12),
                const HotspotInfoBanner(),
                const SizedBox(height: 16),
                _QrJoinCard(joinUrl: joinUrl, qrSize: qrSize),
              ],
            ),
          ),
        ),
        VerticalDivider(width: 1, color: Colors.white.withValues(alpha: 0.1)),
        Expanded(
          flex: 2,
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.all(20),
            child: _PlayerPanel(app: app, scenario: scenario),
          ),
        ),
      ],
    );
  }
}
