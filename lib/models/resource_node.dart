import 'package:flutter/material.dart';

enum ResourceKind { ore, crystal, salvage, relic }

class ResourceNode {
  const ResourceNode({
    required this.id,
    required this.sectorIndex,
    required this.name,
    required this.kind,
    required this.position,
    required this.color,
    required this.commodityId,
    required this.yieldUnits,
    required this.loreId,
    required this.scanSummary,
  });

  final int id;
  final int sectorIndex;
  final String name;
  final ResourceKind kind;
  final Offset position;
  final Color color;
  final String commodityId;
  final int yieldUnits;
  final String loreId;
  final String scanSummary;
}
