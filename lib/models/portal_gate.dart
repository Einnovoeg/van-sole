import 'package:flutter/material.dart';

class PortalGate {
  const PortalGate({
    required this.id,
    required this.sectorIndex,
    required this.targetSectorIndex,
    required this.targetPortalId,
    required this.name,
    required this.position,
    required this.exitVector,
    required this.color,
  });

  final int id;
  final int sectorIndex;
  final int targetSectorIndex;
  final int targetPortalId;
  final String name;
  final Offset position;
  final Offset exitVector;
  final Color color;
}
