import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import 'game_dashboard_screen.dart';
import 'generating_screen.dart';
import 'lobby_screen.dart';
import 'scenario_config_screen.dart';
import 'settings_screen.dart';
import '../widgets/save_list_section.dart';
import '../widgets/saved_scenario_section.dart';
import '../widgets/ui_helpers.dart';

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
  bool _showDemo = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('マダミス GM'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: widget.app.goToSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const StepGuideCard(),
              const SizedBox(height: 20),
              const SaveListSection(),
              const SizedBox(height: 20),
              const SectionHeader(
                title: '保存シナリオ',
                subtitle: '生成済みのシナリオをタップしてすぐ開始',
                icon: Icons.auto_stories,
              ),
              const SavedScenarioSection(),
              if (widget.app.savedScenarioError != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.app.savedScenarioError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              const SectionHeader(
                title: '新しく始める',
                subtitle: 'AIがシナリオを自動生成します（要APIキー）',
                icon: Icons.auto_awesome,
              ),
              FilledButton.icon(
                onPressed: widget.app.goToScenarioConfig,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('AIでシナリオを作る'),
              ),
              const SizedBox(height: 24),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('お試しデモ', style: Theme.of(context).textTheme.titleLarge),
                subtitle: const Text('ネット不要・すぐ遊べる固定シナリオ'),
                leading: Icon(Icons.science_outlined, color: Theme.of(context).colorScheme.secondary),
                initiallyExpanded: _showDemo,
                onExpansionChanged: (v) => setState(() => _showDemo = v),
                children: [
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => widget.app.startHostWithFixedScenario(maxPlayers: _playerCount),
                    icon: const Icon(Icons.castle_outlined),
                    label: Text('洋館デモ（対立・$_playerCount人）'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => widget.app.startHostWithCoopScenario(playerCount: 2),
                    icon: const Icon(Icons.groups),
                    label: const Text('協力推理デモ（2人）'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => widget.app.startHostWithCoopScenario(playerCount: 3),
                    icon: const Icon(Icons.groups_3),
                    label: const Text('協力推理デモ（3人）'),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('対立デモの人数', style: Theme.of(context).textTheme.titleSmall),
                          Slider(
                            value: _playerCount.toDouble(),
                            min: 2,
                            max: 4,
                            divisions: 2,
                            label: '$_playerCount人',
                            onChanged: (v) => setState(() => _playerCount = v.round()),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
