import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/scenario_config.dart';
import '../services/app_state.dart';

class ScenarioConfigScreen extends StatefulWidget {
  const ScenarioConfigScreen({super.key});

  @override
  State<ScenarioConfigScreen> createState() => _ScenarioConfigScreenState();
}

class _ScenarioConfigScreenState extends State<ScenarioConfigScreen> {
  String _genre = ScenarioConfig.genres.first;
  String _difficulty = ScenarioConfig.difficulties[1];
  int _minutes = 60;
  int _playerCount = 4;
  final _themeController = TextEditingController(text: '密室の殺人事件');

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('シナリオ設定'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: app.goToHome,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (!app.hasApiKey)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning),
                title: const Text('Gemini APIキーが未設定'),
                subtitle: const Text('設定画面でAPIキーを入力してください'),
                trailing: TextButton(
                  onPressed: app.goToSettings,
                  child: const Text('設定'),
                ),
              ),
            ),
          const SizedBox(height: 8),
          _DropdownField(
            label: 'ジャンル',
            value: _genre,
            items: ScenarioConfig.genres,
            onChanged: (v) => setState(() => _genre = v!),
          ),
          const SizedBox(height: 16),
          _DropdownField(
            label: '難易度',
            value: _difficulty,
            items: ScenarioConfig.difficulties,
            onChanged: (v) => setState(() => _difficulty = v!),
          ),
          const SizedBox(height: 16),
          Text('プレイ時間: $_minutes 分', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _minutes.toDouble(),
            min: 30,
            max: 120,
            divisions: 3,
            label: '$_minutes',
            onChanged: (v) => setState(() => _minutes = v.round()),
          ),
          const SizedBox(height: 8),
          Text('参加人数: $_playerCount 人', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _playerCount.toDouble(),
            min: 2,
            max: 8,
            divisions: 6,
            label: '$_playerCount',
            onChanged: (v) => setState(() => _playerCount = v.round()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _themeController,
            decoration: const InputDecoration(
              labelText: 'テーマ・キーワード',
              hintText: '例: 雪山の別荘、結婚式の夜',
              border: OutlineInputBorder(),
            ),
            maxLength: 100,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: app.hasApiKey
                ? () {
                    final config = ScenarioConfig(
                      genre: _genre,
                      difficulty: _difficulty,
                      estimatedMinutes: _minutes,
                      playerCount: _playerCount,
                      theme: _themeController.text.trim(),
                    );
                    app.generateAndStartHost(config);
                  }
                : null,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('AIでシナリオを生成'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
      onChanged: onChanged,
    );
  }
}
