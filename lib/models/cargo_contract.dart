import 'package:flutter/material.dart';
import 'models/station.dart';
import '../main.dart'; // Temporary import for VanSoleGame

class CargoContract {
  CargoContract({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.cargoUnits,
    required this.rewardCredits,
    required this.cargoName,
    this.pickedUp = false,
  });

  final int id;
  final Station pickup;
  final Station destination;
  final int cargoUnits;
  final int rewardCredits;
  final String cargoName;
  bool pickedUp;

  CargoContract copyForAcceptance() => CargoContract(
    id: id,
    pickup: pickup,
    destination: destination,
    cargoUnits: cargoUnits,
    rewardCredits: rewardCredits,
    cargoName: cargoName,
    pickedUp: pickedUp,
  );

  String statusDescription(VanSoleGame game) {
    if (!pickedUp) {
      if (game.isDocked && game.dockedStation?.id == pickup.id) {
        return 'Cargo can be loaded here (Deliver button / R).';
      }
      return 'Return to ${pickup.name} to load the cargo.';
    }
    if (game.isDocked && game.dockedStation?.id == destination.id) {
      return 'Ready to unload at destination.';
    }
    return 'En route to ${destination.name}.';
  }
}
