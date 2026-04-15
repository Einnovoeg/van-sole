import 'package:flutter/material.dart';

class PirateShip {
  PirateShip({
    required this.trackingId,
    required this.position,
    required this.velocity,
    required this.angle,
    required this.hull,
    required this.shield,
    required this.bias,
  });

  final int trackingId;
  Offset position;
  Offset velocity;
  double angle;
  double hull;
  double shield;
  double fireCooldown = 0;
  double bias;
}
