class Scenario {
  Scenario({
    required this.id,
    required this.title,
    required this.genre,
    required this.synopsis,
    required this.epilogue,
    required this.truth,
    required this.characters,
    required this.clues,
    required this.playerCount,
    this.gameMode = 'competitive',
  });

  final String id;
  final String title;
  final String genre;
  final String synopsis;
  final String epilogue;
  final ScenarioTruth truth;
  final List<ScenarioCharacter> characters;
  final List<ScenarioClue> clues;
  final int playerCount;
  final String gameMode;

  List<ScenarioCharacter> get playerCharacters =>
      characters.where((c) => c.isPlayer).toList();

  Map<String, dynamic> toJson({bool includeTruth = true}) {
    return {
      'id': id,
      'title': title,
      'genre': genre,
      'synopsis': synopsis,
      'epilogue': epilogue,
      if (includeTruth) 'truth': truth.toJson(),
      'characters': characters.map((c) => c.toJson()).toList(),
      'clues': clues.map((c) => c.toJson()).toList(),
      'playerCount': playerCount,
      'gameMode': gameMode,
    };
  }

  factory Scenario.fromJson(Map<String, dynamic> json) {
    return Scenario(
      id: json['id'] as String,
      title: json['title'] as String,
      genre: json['genre'] as String,
      synopsis: json['synopsis'] as String,
      epilogue: json['epilogue'] as String,
      truth: ScenarioTruth.fromJson(json['truth'] as Map<String, dynamic>),
      characters: (json['characters'] as List)
          .map((e) => ScenarioCharacter.fromJson(e as Map<String, dynamic>))
          .toList(),
      clues: (json['clues'] as List)
          .map((e) => ScenarioClue.fromJson(e as Map<String, dynamic>))
          .toList(),
      playerCount: json['playerCount'] as int,
      gameMode: json['gameMode'] as String? ?? 'competitive',
    );
  }
}

class ScenarioTruth {
  ScenarioTruth({
    required this.culpritId,
    required this.crimeDescription,
    required this.method,
    required this.motive,
    required this.timeOfCrime,
    required this.location,
    required this.explanation,
  });

  final String culpritId;
  final String crimeDescription;
  final String method;
  final String motive;
  final String timeOfCrime;
  final String location;
  final String explanation;

  Map<String, dynamic> toJson() => {
        'culpritId': culpritId,
        'crimeDescription': crimeDescription,
        'method': method,
        'motive': motive,
        'timeOfCrime': timeOfCrime,
        'location': location,
        'explanation': explanation,
      };

  factory ScenarioTruth.fromJson(Map<String, dynamic> json) {
    return ScenarioTruth(
      culpritId: json['culpritId'] as String,
      crimeDescription: json['crimeDescription'] as String,
      method: json['method'] as String,
      motive: json['motive'] as String,
      timeOfCrime: json['timeOfCrime'] as String,
      location: json['location'] as String,
      explanation: json['explanation'] as String,
    );
  }
}

class ScenarioCharacter {
  ScenarioCharacter({
    required this.id,
    required this.name,
    required this.age,
    required this.occupation,
    required this.publicProfile,
    required this.isPlayer,
    required this.privateScript,
  });

  final String id;
  final String name;
  final int age;
  final String occupation;
  final String publicProfile;
  final bool isPlayer;
  final PrivateScript privateScript;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'occupation': occupation,
        'publicProfile': publicProfile,
        'isPlayer': isPlayer,
        'privateScript': privateScript.toJson(),
      };

  factory ScenarioCharacter.fromJson(Map<String, dynamic> json) {
    return ScenarioCharacter(
      id: json['id'] as String,
      name: json['name'] as String,
      age: json['age'] as int,
      occupation: json['occupation'] as String,
      publicProfile: json['publicProfile'] as String,
      isPlayer: json['isPlayer'] as bool,
      privateScript: PrivateScript.fromJson(
        json['privateScript'] as Map<String, dynamic>,
      ),
    );
  }
}

class PrivateScript {
  PrivateScript({
    required this.role,
    required this.relationship,
    required this.secrets,
    required this.allowedLies,
    required this.motive,
    required this.alibi,
    required this.objectives,
  });

  final String role;
  final String relationship;
  final List<String> secrets;
  final List<String> allowedLies;
  final String motive;
  final String alibi;
  final List<String> objectives;

  Map<String, dynamic> toJson() => {
        'role': role,
        'relationship': relationship,
        'secrets': secrets,
        'allowedLies': allowedLies,
        'motive': motive,
        'alibi': alibi,
        'objectives': objectives,
      };

  factory PrivateScript.fromJson(Map<String, dynamic> json) {
    return PrivateScript(
      role: json['role'] as String,
      relationship: json['relationship'] as String,
      secrets: (json['secrets'] as List).cast<String>(),
      allowedLies: (json['allowedLies'] as List).cast<String>(),
      motive: json['motive'] as String,
      alibi: json['alibi'] as String,
      objectives: (json['objectives'] as List).cast<String>(),
    );
  }
}

class ScenarioClue {
  ScenarioClue({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.importance,
  });

  final String id;
  final String title;
  final String content;
  final String type;
  final String importance;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'type': type,
        'importance': importance,
      };

  factory ScenarioClue.fromJson(Map<String, dynamic> json) {
    return ScenarioClue(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      type: json['type'] as String,
      importance: json['importance'] as String,
    );
  }
}
