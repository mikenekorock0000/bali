import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/game_session.dart';

class SaveSummary {
  SaveSummary({
    required this.id,
    required this.title,
    required this.playerCount,
    required this.phase,
    required this.savedAt,
  });

  final String id;
  final String title;
  final int playerCount;
  final String phase;
  final DateTime savedAt;

  factory SaveSummary.fromMap(Map<String, dynamic> map) {
    return SaveSummary(
      id: map['id'] as String,
      title: map['title'] as String,
      playerCount: map['player_count'] as int,
      phase: map['phase'] as String,
      savedAt: DateTime.parse(map['saved_at'] as String),
    );
  }
}

class SaveService {
  SaveService._();
  static final SaveService instance = SaveService._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'madamis_saves.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE saves (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            player_count INTEGER NOT NULL,
            phase TEXT NOT NULL,
            saved_at TEXT NOT NULL,
            session_json TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<String> saveSession(GameSession session) async {
    final database = await db;
    final json = jsonEncode(session.toJson(includeTruth: true));
    final id = session.id;

    await database.insert(
      'saves',
      {
        'id': id,
        'title': session.scenario.title,
        'player_count': session.players.length,
        'phase': session.phase.label,
        'saved_at': DateTime.now().toIso8601String(),
        'session_json': json,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return id;
  }

  Future<List<SaveSummary>> listSaves() async {
    final database = await db;
    final rows = await database.query(
      'saves',
      orderBy: 'saved_at DESC',
      limit: 20,
    );
    return rows.map(SaveSummary.fromMap).toList();
  }

  Future<GameSession?> loadSession(String id) async {
    final database = await db;
    final rows = await database.query(
      'saves',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final json = jsonDecode(rows.first['session_json'] as String) as Map<String, dynamic>;
    return GameSession.fromJson(json);
  }

  Future<void> deleteSave(String id) async {
    final database = await db;
    await database.delete('saves', where: 'id = ?', whereArgs: [id]);
  }
}
