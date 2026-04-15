import 'package:flutter/material.dart';

class Projectile {
  Projectile({
    required this.position,
    required this.velocity,
    required this.ttl,
    required this.damage,
    required this.friendly,
  });

  Offset position;
  Offset velocity;
  double ttl;
  double damage;
  bool friendly;
}
