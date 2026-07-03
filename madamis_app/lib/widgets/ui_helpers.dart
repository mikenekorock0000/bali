import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// セクション見出し（タイトル + 説明）
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade500,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ホーム画面の3ステップガイド
class StepGuideCard extends StatelessWidget {
  const StepGuideCard({super.key});

  static const _steps = [
    (icon: Icons.library_books_outlined, title: 'シナリオを選ぶ', desc: '保存済み・AI生成・デモ'),
    (icon: Icons.qr_code_scanner, title: 'プレイヤーが参加', desc: 'QRコードを読み取る'),
    (icon: Icons.smart_toy_outlined, title: '自動で進行', desc: 'GM不要・タブレットが進行'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('はじめかた', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ...List.generate(_steps.length, (i) {
              final step = _steps[i];
              return Padding(
                padding: EdgeInsets.only(bottom: i < _steps.length - 1 ? 14 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(step.icon, size: 18, color: primary),
                              const SizedBox(width: 6),
                              Text(step.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            step.desc,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// モード・人数バッジ
class ModeBadge extends StatelessWidget {
  const ModeBadge({
    super.key,
    required this.playerCount,
    required this.isCooperative,
    this.genre,
  });

  final int playerCount;
  final bool isCooperative;
  final String? genre;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(
          context,
          icon: isCooperative ? Icons.groups : Icons.person_search,
          label: isCooperative ? '協力推理' : '対立推理',
          color: isCooperative
              ? Theme.of(context).colorScheme.tertiary
              : Theme.of(context).colorScheme.primary,
        ),
        _chip(context, icon: Icons.people, label: '$playerCount人'),
        if (genre != null) _chip(context, icon: Icons.category, label: genre!),
      ],
    );
  }

  Widget _chip(BuildContext context, {required IconData icon, required String label, Color? color}) {
    final c = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
        ],
      ),
    );
  }
}

/// やることリスト（ロビー等）
class ActionStepsCard extends StatelessWidget {
  const ActionStepsCard({
    super.key,
    required this.steps,
    this.currentStep,
  });

  final List<String> steps;
  final int? currentStep;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('いまやること', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            ...List.generate(steps.length, (i) {
              final isCurrent = currentStep == i;
              final isDone = currentStep != null && i < currentStep!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      isDone ? Icons.check_circle : isCurrent ? Icons.arrow_forward : Icons.circle_outlined,
                      size: 18,
                      color: isDone ? Colors.green : isCurrent ? primary : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        steps[i],
                        style: TextStyle(
                          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                          color: isCurrent ? null : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// シナリオ情報ヘッダー（ジャンル色付き）
class ScenarioHeaderCard extends StatelessWidget {
  const ScenarioHeaderCard({
    super.key,
    required this.title,
    required this.genre,
    required this.playerCount,
    required this.isCooperative,
    this.subtitle,
  });

  final String title;
  final String genre;
  final int playerCount;
  final bool isCooperative;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = GenrePalette.forGenre(genre);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.gradientStart, palette.gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(palette.icon, color: palette.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          ],
          const SizedBox(height: 12),
          ModeBadge(playerCount: playerCount, isCooperative: isCooperative, genre: genre),
        ],
      ),
    );
  }
}
