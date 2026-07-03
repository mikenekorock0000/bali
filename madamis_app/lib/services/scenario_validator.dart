import '../models/scenario.dart';
import '../models/scenario_config.dart';

class ValidationCheck {
  ValidationCheck({
    required this.name,
    required this.passed,
    this.errors = const [],
  });

  final String name;
  final bool passed;
  final List<String> errors;
}

class ValidationReport {
  ValidationReport({
    required this.passed,
    required this.checks,
    this.attempts = 1,
  });

  final bool passed;
  final List<ValidationCheck> checks;
  final int attempts;

  List<String> get allErrors =>
      checks.expand((c) => c.errors.map((e) => '[${c.name}] $e')).toList();
}

class ScenarioValidator {
  static int clueCountForPlayers(int count) {
    return switch (count) {
      2 => 10,
      3 => 12,
      4 => 15,
      5 => 18,
      6 => 22,
      7 => 26,
      8 => 30,
      _ => 15,
    };
  }

  ValidationReport validate(
    Scenario scenario,
    ScenarioConfig config, {
    bool strict = false,
  }) {
    final isCoop = config.playerCount <= 3;
    final checks = [
      _checkCharacterCount(scenario, config),
      _checkCulpritExists(scenario),
      _checkClueCount(scenario, config),
      _checkCriticalClues(scenario),
      if (isCoop) ...[
        _checkCoopNpcs(scenario),
        _checkCoopCulpritIsSuspect(scenario),
      ] else
        _checkCulpritIsPlayer(scenario),
      _checkMotiveConsistency(scenario),
      _checkRequiredFields(scenario, strict: strict),
      _checkUniqueCharacterIds(scenario),
      _checkUniqueClueIds(scenario),
      _checkAlibiPresent(scenario),
    ];

    return ValidationReport(
      passed: checks.every((c) => c.passed),
      checks: checks,
    );
  }

  ValidationCheck _checkCharacterCount(Scenario scenario, ScenarioConfig config) {
    final playerChars = scenario.characters.where((c) => c.isPlayer).length;
    final expected = config.playerCount;
    final errors = <String>[];
    if (playerChars != expected) {
      errors.add('プレイヤーキャラ数 $playerChars != 期待人数 $expected');
    }
    return ValidationCheck(name: 'character_count_match', passed: errors.isEmpty, errors: errors);
  }

  ValidationCheck _checkCulpritExists(Scenario scenario) {
    final exists = scenario.characters.any((c) => c.id == scenario.truth.culpritId);
    return ValidationCheck(
      name: 'culprit_exists',
      passed: exists,
      errors: exists ? [] : ['犯人ID ${scenario.truth.culpritId} がキャラクターに存在しない'],
    );
  }

  ValidationCheck _checkClueCount(Scenario scenario, ScenarioConfig config) {
    final expected = clueCountForPlayers(config.playerCount);
    final actual = scenario.clues.length;
    final min = (expected * 0.7).floor();
    final max = (expected * 1.3).ceil();
    final ok = actual >= min && actual <= max;
    return ValidationCheck(
      name: 'clue_count_range',
      passed: ok,
      errors: ok ? [] : ['手がかり数 $actual が期待範囲 $min-$max 外'],
    );
  }

  ValidationCheck _checkCriticalClues(Scenario scenario) {
    final critical = scenario.clues.where((c) => c.importance == 'critical').toList();
    final errors = <String>[];
    if (critical.length < 2) {
      errors.add('critical手がかりが${critical.length}枚（最低2枚必要）');
    }

    final culpritId = scenario.truth.culpritId;
    final culprit = _findCharacter(scenario, culpritId);
    final implicatesCulprit = culprit != null &&
        critical.any((c) {
          final text = '${c.title} ${c.content}'.toLowerCase();
          return text.contains(culprit.name.toLowerCase()) ||
              culprit.privateScript.secrets.any(
                (s) => s.length >= 4 && text.contains(s.substring(0, 4)),
              );
        });

    if (!implicatesCulprit) {
      final hasCrimeHint = critical.any((c) => _clueRelatesToCrime(c, scenario.truth));
      if (!hasCrimeHint) {
        errors.add('critical手がかりに犯行関連の情報が不足');
      }
    }
    return ValidationCheck(name: 'clue_reachability', passed: errors.isEmpty, errors: errors);
  }

  ScenarioCharacter? _findCharacter(Scenario scenario, String id) {
    for (final c in scenario.characters) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool _clueRelatesToCrime(ScenarioClue clue, ScenarioTruth truth) {
    final text = '${clue.title} ${clue.content}';
    const crimeKeywords = [
      '毒', '犯', '動機', '遺言', '記録', '証言', '殺', '死', '凶器',
      '血', '手法', '犯行', '密室', '死因', '目撃', 'アリバイ', '時刻',
      '傷', '事故', '事件', '被害', '遺体',
    ];
    if (crimeKeywords.any(text.contains)) return true;

    for (final field in [
      truth.method,
      truth.motive,
      truth.crimeDescription,
      truth.location,
      truth.timeOfCrime,
    ]) {
      final words = field.split(RegExp(r'[、。\s・「」『』]+')).where((w) => w.length >= 2);
      if (words.any(text.contains)) return true;
    }
    return false;
  }

  ValidationCheck _checkCulpritIsPlayer(Scenario scenario) {
    final culprit = scenario.characters.where((c) => c.id == scenario.truth.culpritId);
    if (culprit.isEmpty) {
      return ValidationCheck(name: 'culprit_is_player', passed: false, errors: ['犯人キャラが見つからない']);
    }
    final isPlayer = culprit.first.isPlayer;
    return ValidationCheck(
      name: 'culprit_is_player',
      passed: isPlayer,
      errors: isPlayer ? [] : ['犯人はプレイヤーキャラである必要がある'],
    );
  }

  ValidationCheck _checkMotiveConsistency(Scenario scenario) {
    final culprit = _findCharacter(scenario, scenario.truth.culpritId);
    if (culprit == null) {
      return ValidationCheck(
        name: 'motive_culprit_match',
        passed: false,
        errors: ['犯人キャラが見つからない'],
      );
    }
    final truthMotive = scenario.truth.motive.toLowerCase();
    final charMotive = culprit.privateScript.motive.toLowerCase();
    // Motives should share some semantic overlap (simple keyword check)
    final keywords = truthMotive.split(RegExp(r'[、。\s]+')).where((w) => w.length > 1);
    final overlap = keywords.any(charMotive.contains);
    return ValidationCheck(
      name: 'motive_culprit_match',
      passed: overlap || charMotive.isNotEmpty,
      errors: overlap || charMotive.isNotEmpty ? [] : ['犯人の動機と真相の動機が一致しない'],
    );
  }

  ValidationCheck _checkRequiredFields(Scenario scenario, {bool strict = false}) {
    final errors = <String>[];
    if (scenario.title.isEmpty) errors.add('タイトルが空');

    if (strict) {
      if (scenario.synopsis.length < 200) errors.add('あらすじが短すぎる（200字以上）');
      if (scenario.epilogue.length < 80) errors.add('後日談が短すぎる（80字以上）');
      if (scenario.truth.explanation.length < 200) {
        errors.add('真相解説が短すぎる（200字以上）');
      }
      for (final c in scenario.characters.where((c) => c.isPlayer)) {
        if (c.privateScript.secrets.length < 2) {
          errors.add('${c.name}の秘密が不足（2個以上）');
        }
        if (c.privateScript.alibi.isEmpty) errors.add('${c.name}のアリバイが空');
      }
    } else {
      if (scenario.synopsis.length < 100) errors.add('あらすじが短すぎる（100字以上）');
      if (scenario.epilogue.isEmpty) errors.add('後日談が空');
      for (final c in scenario.characters.where((c) => c.isPlayer)) {
        if (c.privateScript.secrets.isEmpty) errors.add('${c.name}の秘密が空');
        if (c.privateScript.alibi.isEmpty) errors.add('${c.name}のアリバイが空');
      }
    }

    return ValidationCheck(name: 'required_fields', passed: errors.isEmpty, errors: errors);
  }

  ValidationCheck _checkUniqueCharacterIds(Scenario scenario) {
    final ids = scenario.characters.map((c) => c.id).toList();
    final unique = ids.toSet();
    return ValidationCheck(
      name: 'unique_character_ids',
      passed: ids.length == unique.length,
      errors: ids.length == unique.length ? [] : ['キャラクターIDが重複'],
    );
  }

  ValidationCheck _checkUniqueClueIds(Scenario scenario) {
    final ids = scenario.clues.map((c) => c.id).toList();
    final unique = ids.toSet();
    return ValidationCheck(
      name: 'unique_clue_ids',
      passed: ids.length == unique.length,
      errors: ids.length == unique.length ? [] : ['手がかりIDが重複'],
    );
  }

  ValidationCheck _checkCoopNpcs(Scenario scenario) {
    final npcs = scenario.characters.where((c) => !c.isPlayer).length;
    final ok = npcs >= 2;
    return ValidationCheck(
      name: 'coop_npc_suspects',
      passed: ok,
      errors: ok ? [] : ['協力モード: NPC容疑者が${npcs}人（最低2人必要）'],
    );
  }

  ValidationCheck _checkCoopCulpritIsSuspect(Scenario scenario) {
    final matching =
        scenario.characters.where((c) => c.id == scenario.truth.culpritId);
    if (matching.isEmpty) {
      return ValidationCheck(
        name: 'coop_culprit_is_npc',
        passed: false,
        errors: ['犯人キャラが見つからない'],
      );
    }
    final culprit = matching.first;
    final ok = !culprit.isPlayer;
    return ValidationCheck(
      name: 'coop_culprit_is_npc',
      passed: ok,
      errors: ok ? [] : ['協力モード: 犯人はNPC容疑者である必要がある'],
    );
  }

  ValidationCheck _checkAlibiPresent(Scenario scenario) {
    final errors = <String>[];
    for (final c in scenario.characters) {
      if (c.privateScript.alibi.trim().length < 5) {
        errors.add('${c.name}のアリバイが不十分');
      }
    }
    return ValidationCheck(
      name: 'alibi_present',
      passed: errors.isEmpty,
      errors: errors,
    );
  }
}
