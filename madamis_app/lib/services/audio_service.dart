import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../models/game_phase.dart';
import 'settings_service.dart';

class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  final _bgmPlayer = AudioPlayer();
  final _sePlayer = AudioPlayer();
  GamePhase? _currentBgmPhase;

  Future<void> onPhaseChanged(GamePhase phase) async {
    if (!SettingsService.instance.soundEnabled) return;

    await _playSe('se_phase.mp3');

    if (_currentBgmPhase == phase) return;
    _currentBgmPhase = phase;

    final bgmFile = _bgmForPhase(phase);
    if (bgmFile == null) {
      await _bgmPlayer.stop();
      return;
    }

    try {
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.setVolume(SettingsService.instance.volume * 0.5);
      await _bgmPlayer.play(AssetSource('audio/bgm/$bgmFile'));
    } catch (_) {
      // BGM asset optional
    }
  }

  Future<void> onEvent(String type) async {
    if (!SettingsService.instance.soundEnabled) return;

    final se = switch (type) {
      'player_joined' => 'se_join.mp3',
      'clue_drawn' => 'se_clue.mp3',
      'clue_revealed' => 'se_clue.mp3',
      'vote_cast' => 'se_vote.mp3',
      'truth_revealed' => 'se_truth.mp3',
      'results' => 'se_correct.mp3',
      _ => null,
    };

    if (se != null) {
      await _playSe(se);
    } else {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  String? _bgmForPhase(GamePhase phase) {
    return switch (phase) {
      GamePhase.lobby => 'bgm_lobby.mp3',
      GamePhase.synopsis => 'bgm_tension.mp3',
      GamePhase.privateReading => 'bgm_mystery.mp3',
      GamePhase.investigation => 'bgm_investigation.mp3',
      GamePhase.discussion => 'bgm_discussion.mp3',
      GamePhase.voting => 'bgm_suspense.mp3',
      GamePhase.results => 'bgm_ending.mp3',
      _ => null,
    };
  }

  Future<void> _playSe(String file) async {
    try {
      await _sePlayer.setVolume(SettingsService.instance.volume);
      await _sePlayer.play(AssetSource('audio/se/$file'));
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> stopAll() async {
    await _bgmPlayer.stop();
    await _sePlayer.stop();
    _currentBgmPhase = null;
  }
}
