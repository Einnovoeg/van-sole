import 'package:flutter/material.dart';

class DialogueEncounter {
  const DialogueEncounter({
    required this.title,
    required this.body,
    required this.options,
  });

  final String title;
  final String body;
  final List<DialogueOption> options;
}

class DialogueOption {
  const DialogueOption({
    required this.label,
    required this.resultLog,
    this.creditsDelta = 0,
    this.fuelDelta = 0,
    this.energyDelta = 0,
    this.hullDelta = 0,
    this.shieldDelta = 0,
    this.spawnPirates = 0,
  });

  final String label;
  final String resultLog;
  final int creditsDelta;
  final double fuelDelta;
  final double energyDelta;
  final double hullDelta;
  final double shieldDelta;
  final int spawnPirates;
}
