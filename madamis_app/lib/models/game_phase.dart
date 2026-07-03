enum GamePhase {
  lobby,
  synopsis,
  privateReading,
  investigation,
  discussion,
  accusation,
  voting,
  truthReveal,
  epilogue,
  results,
  end;

  String get id {
    switch (this) {
      case GamePhase.lobby:
        return 'lobby';
      case GamePhase.synopsis:
        return 'synopsis';
      case GamePhase.privateReading:
        return 'private_reading';
      case GamePhase.investigation:
        return 'investigation';
      case GamePhase.discussion:
        return 'discussion';
      case GamePhase.accusation:
        return 'accusation';
      case GamePhase.voting:
        return 'voting';
      case GamePhase.truthReveal:
        return 'truth_reveal';
      case GamePhase.epilogue:
        return 'epilogue';
      case GamePhase.results:
        return 'results';
      case GamePhase.end:
        return 'end';
    }
  }

  String get label {
    switch (this) {
      case GamePhase.lobby:
        return 'ロビー';
      case GamePhase.synopsis:
        return 'あらすじ';
      case GamePhase.privateReading:
        return '個人台本';
      case GamePhase.investigation:
        return '調査';
      case GamePhase.discussion:
        return '議論';
      case GamePhase.accusation:
        return '推理発表';
      case GamePhase.voting:
        return '投票';
      case GamePhase.truthReveal:
        return '真相解説';
      case GamePhase.epilogue:
        return '後日談';
      case GamePhase.results:
        return '結果発表';
      case GamePhase.end:
        return '終了';
    }
  }

  static GamePhase fromId(String id) {
    return GamePhase.values.firstWhere(
      (p) => p.id == id,
      orElse: () => GamePhase.lobby,
    );
  }
}
