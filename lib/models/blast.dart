import 'package:flutter/material.dart';

class Blast {
  Blast({required this.position, required this.ttl, required this.radius});

  final Offset position;
  double ttl;
  final double radius;
}
