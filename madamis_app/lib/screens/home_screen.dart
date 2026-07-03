import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import 'game_dashboard_screen.dart';
import 'generating_screen.dart';
import 'lobby_screen.dart';
import 'scenario_config_screen.dart';
import 'settings_screen.dart';
import '../widgets/save_list_section.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return switch (app.screen) {
      AppScreen.scenarioConfig => const ScenarioConfigScreen(),
      AppScreen.generating => const GeneratingScreen(),
      AppScreen.settings => const SettingsScreen(),
      AppScreen.lobby => const LobbyScreen(),
      AppScreen.game => const GameDashboardScreen(),
      _ => _HomeBody(app: app),
    };
  }
}

class _HomeBody extends StatefulWidget {
  const _HomeBody({required this.app});

  final AppState app;

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  int _playerCount = 4;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: widget.app.goToSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
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
                const SizedBox(height: 24),
                const SaveListSection(),
                const SizedBox(height: 16),
                FilledButton.icon(
                onPressed: widget.app.goToScenarioConfig,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('AIでシナリオ生成'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => widget.app.startHostWithFixedScenario(maxPlayers: _playerCount),
                icon: const Icon(Icons.play_arrow),
                label: const Text('固定シナリオで遊ぶ（4人・対立）'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => widget.app.startHostWithCoopScenario(playerCount: 2),
                icon: const Icon(Icons.groups),
                label: const Text('協力推理デモ（2人）'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '対立デモ人数: $_playerCount 人',
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
