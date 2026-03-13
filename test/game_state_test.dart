import 'package:flutter_test/flutter_test.dart';

import 'package:van_sole/main.dart';

const _idleInput = PlayerInput(
  up: false,
  down: false,
  left: false,
  right: false,
  fire: false,
  boost: false,
);

void main() {
  test('jump transit and save/load roundtrip preserve key state', () {
    final game = VanSoleGame();

    game.credits = 777;
    game.engineUpgradeTier = 2;
    game.weaponUpgradeTier = 1;
    game.shieldUpgradeTier = 1;
    game.cargoUpgradeTier = 2;
    game.playerShield = game.shieldCapacity;

    final gate = game.portals.first;
    game.playerPosition = gate.position + const Offset(8, 0);
    game.playerVelocity = Offset.zero;
    game.update(0.016, _idleInput);

    expect(game.jumpCandidate, isNotNull);
    final startSector = game.sectorIndex;
    game.attemptJump();
    expect(game.sectorIndex, isNot(equals(startSector)));

    final save = game.exportSaveCode();

    final restored = VanSoleGame();
    restored.importSaveCode(save);

    expect(restored.credits, equals(game.credits));
    expect(restored.sectorIndex, equals(game.sectorIndex));
    expect(restored.engineUpgradeTier, equals(2));
    expect(restored.weaponUpgradeTier, equals(1));
    expect(restored.shieldUpgradeTier, equals(1));
    expect(restored.cargoUpgradeTier, equals(2));
    expect(restored.cargoCapacity, equals(14));
    expect(restored.playerShield, lessThanOrEqualTo(restored.shieldCapacity));
  });

  test('docked outfitting upgrades consume credits and improve stats', () {
    final game = VanSoleGame();
    game.credits = 5000;

    final station = game.stations.first;
    game.playerPosition = station.position + const Offset(10, 0);
    game.playerVelocity = Offset.zero;
    game.update(0.016, _idleInput);
    game.toggleDocking();

    expect(game.isDocked, isTrue);

    final creditsBefore = game.credits;
    game.buyCargoUpgrade();
    game.buyShieldUpgrade();
    game.buyEngineUpgrade();
    game.buyWeaponUpgrade();

    expect(game.cargoUpgradeTier, equals(1));
    expect(game.cargoCapacity, equals(12));
    expect(game.shieldUpgradeTier, equals(1));
    expect(game.shieldCapacity, equals(120));
    expect(game.engineUpgradeTier, equals(1));
    expect(game.weaponUpgradeTier, equals(1));
    expect(game.credits, lessThan(creditsBefore));
  });

  test(
    'dockside commodity market trades and save/load persist market state',
    () {
      final game = VanSoleGame();
      game.credits = 9999;

      final station = game.stations.first;
      game.playerPosition = station.position + const Offset(10, 0);
      game.playerVelocity = Offset.zero;
      game.update(0.016, _idleInput);
      game.toggleDocking();

      final commodity = game.commodityCatalog.first;
      final buyPrice = game.currentBuyPrice(commodity.id);
      final sellPrice = game.currentSellPrice(commodity.id);
      expect(buyPrice, isNotNull);
      expect(sellPrice, isNotNull);

      game.buyCommodity(commodity.id);
      expect(game.tradeUnitsForCommodity(commodity.id), equals(1));
      expect(game.tradeCargoUsed, equals(1));
      expect(game.totalCargoUsed, equals(game.cargoUsed + 1));

      final save = game.exportSaveCode();
      final restored = VanSoleGame();
      restored.importSaveCode(save);

      expect(restored.tradeUnitsForCommodity(commodity.id), equals(1));
      expect(restored.currentBuyPrice(commodity.id), equals(buyPrice));
      expect(restored.currentSellPrice(commodity.id), equals(sellPrice));

      final creditsBeforeSell = restored.credits;
      restored.sellCommodity(commodity.id);
      expect(restored.tradeUnitsForCommodity(commodity.id), equals(0));
      expect(restored.credits, equals(creditsBeforeSell + sellPrice!));
    },
  );

  test('resource harvest unlocks lore and persists through save/load', () {
    final game = VanSoleGame();
    final node = game.resources.first;

    game.playerPosition = node.position + const Offset(8, 0);
    game.playerVelocity = Offset.zero;
    game.update(0.016, _idleInput);

    expect(game.harvestCandidate, isNotNull);
    expect(game.tradeCargoUsed, equals(0));

    game.harvestResource();

    expect(
      game.tradeUnitsForCommodity(node.commodityId),
      equals(node.yieldUnits),
    );
    expect(game.resources.any((resource) => resource.id == node.id), isFalse);
    expect(
      game.unlockedLoreEntries.any((entry) => entry.id == node.loreId),
      isTrue,
    );

    final save = game.exportSaveCode();
    final restored = VanSoleGame();
    restored.importSaveCode(save);

    expect(
      restored.tradeUnitsForCommodity(node.commodityId),
      equals(node.yieldUnits),
    );
    expect(
      restored.resources.any((resource) => resource.id == node.id),
      isFalse,
    );
    expect(
      restored.unlockedLoreEntries.any((entry) => entry.id == node.loreId),
      isTrue,
    );
  });

  test('station reputation affects prices, contracts, and save/load', () {
    final game = VanSoleGame();
    game.credits = 99999;

    final station = game.stations.first;
    game.playerPosition = station.position + const Offset(10, 0);
    game.playerVelocity = Offset.zero;
    game.update(0.016, _idleInput);
    game.toggleDocking();

    final commodity = game.commodityCatalog.first;
    final baselineBuy = game.currentBuyPrice(commodity.id)!;
    final baselineSell = game.currentSellPrice(commodity.id)!;
    final offer = game.currentDockOffer!;

    game.shiftStationReputation(station.id, 30);
    expect(game.currentBuyPrice(commodity.id), lessThan(baselineBuy));
    expect(game.currentSellPrice(commodity.id), greaterThan(baselineSell));

    game.shiftStationReputation(offer.destination.id, 30);
    expect(
      game.projectedContractReward(offer),
      greaterThan(offer.rewardCredits),
    );

    game.shiftStationReputation(station.id, -90);
    expect(game.currentDockContractsLocked, isTrue);
    expect(game.canAcceptDockContract, isFalse);

    final save = game.exportSaveCode();
    final restored = VanSoleGame();
    restored.importSaveCode(save);
    expect(
      restored.reputationForStation(station.id),
      equals(game.reputationForStation(station.id)),
    );
    expect(restored.currentDockContractsLocked, isTrue);
    expect(restored.currentBuyPrice(commodity.id), isNotNull);
    expect(restored.currentSellPrice(commodity.id), isNotNull);
  });

  test('contract acceptance is blocked when trade cargo fills the hold', () {
    final game = VanSoleGame();
    game.credits = 99999;

    final station = game.stations.first;
    game.playerPosition = station.position + const Offset(10, 0);
    game.playerVelocity = Offset.zero;
    game.update(0.016, _idleInput);
    game.toggleDocking();

    final commodityId = game.commodityCatalog.first.id;
    var guard = 0;
    while (game.freeCargoSpace > 0) {
      game.buyCommodity(commodityId);
      guard += 1;
      expect(guard, lessThanOrEqualTo(32));
    }

    expect(game.freeCargoSpace, equals(0));
    game.tryAcceptDockContract();
    expect(game.activeContract, isNull);
  });

  test('campaign chain progresses through core milestone actions', () {
    final game = VanSoleGame();
    game.credits = 9999;

    expect(game.campaignCompletedMissions, equals(0));
    expect(game.campaignComplete, isFalse);

    final station = game.stations.first;
    game.playerPosition = station.position + const Offset(10, 0);
    game.playerVelocity = Offset.zero;
    game.update(0.016, _idleInput);
    game.toggleDocking();
    expect(game.campaignCompletedMissions, equals(1));

    game.contractsDelivered = 1;
    game.reevaluateCampaignProgress();
    expect(game.campaignCompletedMissions, equals(2));

    game.kills = 3;
    game.reevaluateCampaignProgress();
    expect(game.campaignCompletedMissions, equals(3));

    game.toggleDocking();
    final firstJumpGate = game.portals.first;
    game.playerPosition = firstJumpGate.position + const Offset(8, 0);
    game.playerVelocity = Offset.zero;
    game.update(0.016, _idleInput);
    game.attemptJump();
    expect(game.sectorIndex, equals(1));
    expect(game.campaignCompletedMissions, greaterThanOrEqualTo(4));

    game.upgradesPurchased = 2;
    game.reevaluateCampaignProgress();
    expect(game.campaignCompletedMissions, greaterThanOrEqualTo(5));

    game.crossSectorContractsDelivered = 1;
    game.reevaluateCampaignProgress();
    expect(game.campaignCompletedMissions, greaterThanOrEqualTo(6));

    final secondJumpGate = game.portals.firstWhere(
      (p) => p.targetSectorIndex == 2,
    );
    game.playerPosition = secondJumpGate.position + const Offset(8, 0);
    game.playerVelocity = Offset.zero;
    game.update(0.016, _idleInput);
    game.attemptJump();
    expect(game.sectorIndex, equals(2));

    final finalDock = game.stations.firstWhere((s) => s.id == 24);
    game.playerPosition = finalDock.position + const Offset(10, 0);
    game.playerVelocity = Offset.zero;
    game.update(0.016, _idleInput);
    game.toggleDocking();

    expect(game.campaignComplete, isTrue);
    expect(game.campaignCompletedMissions, equals(game.campaignTotalMissions));
  });
}
