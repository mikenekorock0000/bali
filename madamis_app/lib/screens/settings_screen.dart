import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/settings_service.dart';

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
          Text('Gemini APIキー', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Google AI Studio でAPIキーを取得してください。\n'
            'https://aistudio.google.com/apikey',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          if (app.hasApiKey)
            Chip(
              avatar: const Icon(Icons.check, size: 16),
              label: const Text('APIキー設定済み'),
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
        ],
      ),
    );
  }
}
