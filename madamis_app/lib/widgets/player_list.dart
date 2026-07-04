import 'package:flutter/material.dart';

import '../models/game_session.dart';

class PlayerList extends StatelessWidget {
  const PlayerList({
    super.key,
    required this.players,
    this.characterNames = const {},
    this.showDetails = false,
  });

  final List<Player> players;
  final Map<String, String> characterNames;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return Center(
        child: Text(
          '参加者を待っています...',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.builder(
      itemCount: players.length,
      itemBuilder: (context, i) {
        final p = players[i];
        final charName = p.characterId != null ? characterNames[p.characterId] : null;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: p.characterId != null
                  ? Colors.green.withValues(alpha: 0.2)
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              child: Icon(
                p.characterId != null ? Icons.check : Icons.person,
                color: p.characterId != null ? Colors.green : Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
            title: Text(p.nickname),
            subtitle: showDetails
                ? Text('トークン ${p.tokensRemaining} · 手がかり ${p.handClues.length}枚')
                : Text(
                    charName != null ? '配役: $charName' : '配役待ち...',
                    style: TextStyle(
                      color: charName != null ? Colors.green : Colors.orange.shade300,
                    ),
                  ),
            trailing: Tooltip(
              message: p.connectionStatus == 'connected' ? '接続中' : '切断',
              child: Icon(
                p.connectionStatus == 'connected' ? Icons.wifi : Icons.wifi_off,
                color: p.connectionStatus == 'connected' ? Colors.green : Colors.grey,
                size: 18,
              ),
            ),
          ),
        );
      },
    );
  }
}
