import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/sim_test_step.dart';
import '../services/player_simulator_service.dart';

class PlayerSimulatorScreen extends StatefulWidget {
  const PlayerSimulatorScreen({super.key});

  @override
  State<PlayerSimulatorScreen> createState() => _PlayerSimulatorScreenState();
}

class _PlayerSimulatorScreenState extends State<PlayerSimulatorScreen> {
  late final WebViewController _webViewController;
  final _service = PlayerSimulatorService();
  final _steps = <SimTestStep>[];
  bool _running = false;
  SimTestReport? _report;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F0F1A));
  }

  Future<void> _runFullTest() async {
    if (_running) return;
    setState(() {
      _running = true;
      _steps.clear();
      _report = null;
    });

    try {
      final report = await _service.runFullSuite(
        webViewController: _webViewController,
        onStep: (step) {
          if (mounted) {
            setState(() => _steps.add(step));
          }
        },
      );
      if (mounted) {
        setState(() => _report = report);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('テストエラー: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pass = _steps.where((s) => s.passed).length;
    final fail = _steps.where((s) => !s.passed).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('プレイヤーシミュレーター'),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'タブレット内で仮想スマホを動かし、全ボタンを自動テストします。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _running ? null : _runFullTest,
                        icon: _running
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(_running ? 'テスト実行中...' : '全ボタン自動テストを実行'),
                      ),
                      if (_steps.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('結果: $pass 成功 / $fail 失敗'),
                      ],
                      if (_report != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _report!.allPassed
                              ? '✅ すべてのテストに合格しました'
                              : '❌ 失敗した項目があります。下の一覧を確認してください',
                          style: TextStyle(
                            color: _report!.allPassed ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _steps.length,
                    itemBuilder: (context, index) {
                      final step = _steps[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          step.passed ? Icons.check_circle : Icons.error,
                          color: step.passed ? Colors.green : Colors.red,
                        ),
                        title: Text(step.label),
                        subtitle: step.detail != null ? Text(step.detail!) : null,
                        trailing: step.durationMs != null
                            ? Text('${step.durationMs}ms')
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '仮想スマホ (WebView)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: WebViewWidget(controller: _webViewController),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
