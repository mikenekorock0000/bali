import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../services/app_state.dart';
import '../services/settings_service.dart';
import 'player_simulator_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyController = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _keyController.text = ''; // never show stored key
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: app.goToHome,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ListTile(
            title: const Text('アプリバージョン'),
            subtitle: Text(AppConstants.appVersion),
            leading: const Icon(Icons.info_outline),
          ),
          const Divider(),
          Text('Gemini APIキー', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Google AI Studio でAPIキーを取得してください。\n'
            'https://aistudio.google.com/apikey\n\n'
            'Cloud Agent / CI では環境変数 GEMINI_API_KEY でも読み込めます。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          if (app.hasApiKey)
            Chip(
              avatar: Icon(
                SettingsService.instance.isApiKeyFromEnvironment
                    ? Icons.cloud
                    : Icons.check,
                size: 16,
              ),
              label: Text(
                SettingsService.instance.isApiKeyFromEnvironment
                    ? 'APIキー: 環境変数 GEMINI_API_KEY'
                    : 'APIキー設定済み',
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'APIキー',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final key = _keyController.text.trim();
              if (key.isEmpty) return;
              await app.saveApiKey(key);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('APIキーを保存しました')),
                );
                _keyController.clear();
              }
            },
            child: const Text('保存'),
          ),
          const Divider(height: 48),
          Text('サウンド', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('効果音・BGM'),
            subtitle: const Text('フェーズ遷移やイベント時に再生'),
            value: app.soundEnabled,
            onChanged: app.setSoundEnabled,
          ),
          ListTile(
            title: Text('音量: ${(SettingsService.instance.volume * 100).round()}%'),
            subtitle: Slider(
              value: SettingsService.instance.volume,
              onChanged: app.soundEnabled ? app.setVolume : null,
            ),
          ),
          const Divider(height: 48),
          Text('開発・テスト', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'タブレット内に仮想スマホを表示し、参加〜投票まで全ボタンを自動検証します。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PlayerSimulatorScreen(),
                ),
              );
            },
            icon: const Icon(Icons.phone_android),
            label: const Text('プレイヤーシミュレーター / 全自動テスト'),
          ),
        ],
      ),
    );
  }
}
