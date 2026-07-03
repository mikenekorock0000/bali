import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import 'game_dashboard_screen.dart';
import 'lobby_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return switch (app.screen) {
      AppScreen.lobby => const LobbyScreen(),
      AppScreen.game => const GameDashboardScreen(),
      _ => _HomeBody(app: app),
    };
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.theater_comedy,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'マダミス GM',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '準備いらず、その場で始まる\nマーダーミステリー',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const Spacer(),
              _PlayerCountSelector(),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => app.startHost(maxPlayers: _playerCount),
                icon: const Icon(Icons.play_arrow),
                label: const Text('新しいゲームを始める'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

int _playerCount = 4;

class _PlayerCountSelector extends StatefulWidget {
  @override
  State<_PlayerCountSelector> createState() => _PlayerCountSelectorState();
}

class _PlayerCountSelectorState extends State<_PlayerCountSelector> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'プレイ人数: $_playerCount 人',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: _playerCount.toDouble(),
              min: 2,
              max: 4,
              divisions: 2,
              label: '$_playerCount',
              onChanged: (v) => setState(() => _playerCount = v.round()),
            ),
            Text(
              'MVP: 固定シナリオ（4人）',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
