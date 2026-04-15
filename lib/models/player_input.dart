class PlayerInput {
  const PlayerInput({
    required this.up,
    required this.down,
    required this.left,
    required this.right,
    required this.fire,
    required this.boost,
  });

  final bool up;
  final bool down;
  final bool left;
  final bool right;
  final bool fire;
  final bool boost;
}
