class CommoditySpec {
  const CommoditySpec({
    required this.id,
    required this.name,
    required this.basePrice,
    required this.volatility,
  });

  final String id;
  final String name;
  final int basePrice;
  final double volatility;
}
