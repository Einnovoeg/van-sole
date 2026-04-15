import 'package:flutter/material.dart';

enum CampaignGoalType {
  dockStation,
  deliverContracts,
  killPirates,
  visitSector,
  buyUpgrades,
  crossSectorDeliveries,
}

class CampaignMission {
  const CampaignMission({
    required this.title,
    required this.description,
    required this.goalType,
    required this.target,
    required this.rewardCredits,
    this.stationId,
    this.sectorIndex,
  });

  final String title;
  final String description;
  final CampaignGoalType goalType;
  final int target;
  final int rewardCredits;
  final int? stationId;
  final int? sectorIndex;
}
