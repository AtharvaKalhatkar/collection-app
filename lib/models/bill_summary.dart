import 'collection_model.dart';

class BillSummary {
  final String billNumber;
  final String shopId;
  final String shopName;
  final String? routeId;
  final String routeName;
  final String businessName;
  final double billTotal;
  final double totalCollected;
  final List<CollectionModel> collections;
  final DateTime lastPaymentDate;

  BillSummary({
    required this.billNumber,
    required this.shopId,
    required this.shopName,
    this.routeId,
    required this.routeName,
    required this.businessName,
    required this.billTotal,
    required this.totalCollected,
    required this.collections,
    required this.lastPaymentDate,
  });

  double get balanceDue => (billTotal - totalCollected) > 0 ? (billTotal - totalCollected) : 0.0;

  DateTime get billDate => collections.isNotEmpty ? collections.first.billDate : lastPaymentDate;

  bool get isPaid => balanceDue <= 0.0;

  bool get isPending => !isPaid;

  double get percentPaid => billTotal > 0 ? ((totalCollected / billTotal) * 100).clamp(0.0, 100.0) : 100.0;
}
