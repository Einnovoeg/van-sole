import 'package:flutter/material.dart';
import 'models/station.dart';
import 'models/portal_gate.dart';
import 'models/resource_node.dart';

class SectorLayout {
  const SectorLayout({
    required this.name,
    required this.starSeed,
    required this.stations,
    required this.portals,
    required this.resources,
  });

  final String name;
  final int starSeed;
  final List<Station> stations;
  final List<PortalGate> portals;
  final List<ResourceNode> resources;
}
