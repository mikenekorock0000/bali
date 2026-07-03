import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_phase.dart';
import '../services/app_state.dart';

class PhaseOverlay extends StatelessWidget {
  const PhaseOverlay({super.key});

  static IconData _iconForPhase(GamePhase phase) {
    return switch (phase) {
      GamePhase.synopsis => Icons.menu_book,
      GamePhase.privateReading => Icons.lock,
      GamePhase.investigation => Icons.search,
      GamePhase.discussion => Icons.forum,
      GamePhase.accusation => Icons.record_voice_over,
      GamePhase.voting => Icons.how_to_vote,
      GamePhase.truthReveal => Icons.flash_on,
      GamePhase.epilogue => Icons.auto_stories,
      GamePhase.results => Icons.emoji_events,
      _ => Icons.theater_comedy,
    };
  }

  @override
  Widget build(BuildContext context) {
    final overlay = context.watch<AppState>().phaseOverlay;
    if (overlay == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: 1,
          duration: const Duration(milliseconds: 300),
          child: Container(
            color: Colors.black.withValues(alpha: 0.85),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconForPhase(overlay),
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    overlay.label,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
