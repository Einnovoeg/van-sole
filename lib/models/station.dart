import 'package:flutter/material.dart';

class Station {
  const Station({
    required this.id,
    required this.sectorIndex,
    required this.name,
    required this.position,
    required this.color,
    required this.blurb,
  });

  final int id;
  final int sectorIndex;
  final String name;
  final Offset position;
  final Color color;
  final String blurb;
}
