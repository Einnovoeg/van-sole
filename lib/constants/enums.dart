import 'package:flutter/material.dart';

enum SessionMode { title, playing, paused }

enum VirtualAction { up, down, left, right, fire, boost }

enum GameAudioCue { fire, hit, dock, contract, jump, comms, warning }

enum PowerChannel { engines, weapons, shields }

extension on PowerChannel {
  String get label => switch (this) {
    PowerChannel.engines => 'Engines',
    PowerChannel.weapons => 'Weapons',
    PowerChannel.shields => 'Shields',
  };

  Color get color => switch (this) {
    PowerChannel.engines => const Color(0xFF2DD4BF),
    PowerChannel.weapons => const Color(0xFFF87171),
    PowerChannel.shields => const Color(0xFF60A5FA),
  };
}
