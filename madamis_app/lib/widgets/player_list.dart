import 'package:flutter/material.dart';

import '../models/game_session.dart';

class PlayerList extends StatelessWidget {
  const PlayerList({
    super.key,
    required this.players,
    this.showDetails = false,
  });

  final List<Player> players;
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
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: p.connectionStatus == 'connected'
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
              child: Text(p.nickname[0].toUpperCase()),
            ),
            title: Text(p.nickname),
            subtitle: showDetails
                ? Text('トークン: ${p.tokensRemaining} / 手がかり: ${p.handClues.length}')
                : Text(p.characterId != null ? '配役済み ✓' : '配役選択中...'),
            trailing: Icon(
              p.connectionStatus == 'connected' ? Icons.wifi : Icons.wifi_off,
              color: p.connectionStatus == 'connected' ? Colors.green : Colors.grey,
              size: 18,
            ),
          ),
        );
      },
    );
  }
}
