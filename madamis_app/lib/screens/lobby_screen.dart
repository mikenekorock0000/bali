import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/app_state.dart';
import '../widgets/player_list.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final joinUrl = app.joinUrl ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ロビー'),
        actions: [
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('ゲームを終了'),
                  content: const Text('サーバーを停止しますか？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('停止')),
                  ],
                ),
              );
              if (ok == true && context.mounted) app.stopHost();
            },
            child: const Text('終了'),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    app.engine.session?.scenario.title ?? 'ルーム ${app.roomId}',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ルーム ${app.roomId}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'スマホでQRコードを読み取って参加',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  if (joinUrl.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: joinUrl,
                        version: QrVersions.auto,
                        size: 240,
                      ),
                    ),
                  const SizedBox(height: 16),
                  SelectableText(
                    joinUrl,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '参加者 (${app.playerCount}/${app.engine.session?.scenario.playerCount ?? 4})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: PlayerList(players: app.engine.session?.players ?? [])),
                  const SizedBox(height: 16),
                  if (app.canStart)
                    FilledButton.icon(
                      onPressed: app.startGame,
                      icon: const Icon(Icons.flag),
                      label: const Text('ゲーム開始'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    )
                  else
                    OutlinedButton(
                      onPressed: null,
                      child: Text(
                        app.playerCount < 2
                            ? '2人以上必要'
                            : '全員配役選択待ち',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
