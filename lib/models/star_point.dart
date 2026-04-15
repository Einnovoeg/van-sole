import 'package:flutter/material.dart';

class StarPoint {
  const StarPoint({
    required this.position,
    required this.radius,
    required this.alpha,
    required this.tint,
  });

  final Offset position;
  final double radius;
  final double alpha;
  final int tint;
}
