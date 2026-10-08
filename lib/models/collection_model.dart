import 'payment_mode.dart';

class CollectionModel {
  final String id;
  final String businessName;
  final String shopId;
  final String shopName;
  final String routeId;
  final String routeName;
  final String billNumber;
  final double billAmount;
  final double collectedAmount;
  final double? balanceRemaining;
  final PaymentMode paymentMode;
  final String? photoBase64;
  final String? photoPath;
  final String? photoUrl;
  final String? chequeNumber;
  final String? bankName;
  final String? referenceNumber;
  final String? remarks;
  final String salesmanName;
  final DateTime collectedAt;
  final DateTime billDate;

  CollectionModel({
    required this.id,
    required this.businessName,
    required this.shopId,
    required this.shopName,
    required this.routeId,
    required this.routeName,
    required this.billNumber,
    required this.billAmount,
    required this.collectedAmount,
    this.balanceRemaining,
    required this.paymentMode,
    this.photoBase64,
    this.photoPath,
    this.photoUrl,
    this.chequeNumber,
    this.bankName,
    this.referenceNumber,
    this.remarks,
    this.salesmanName = 'Akash',
    DateTime? collectedAt,
    DateTime? billDate,
  })  : collectedAt = collectedAt ?? DateTime.now(),
        billDate = billDate ?? (collectedAt ?? DateTime.now());

  // Alias for backward compatibility
  double get amount => collectedAmount;

  double get balanceAmount => balanceRemaining ?? ((billAmount - collectedAmount) > 0 ? (billAmount - collectedAmount) : 0.0);

  bool get isPartial => balanceAmount > 0;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'businessName': businessName,
      'shopId': shopId,
      'shopName': shopName,
      'routeId': routeId,
      'routeName': routeName,
      'billNumber': billNumber,
      'billAmount': billAmount,
      'collectedAmount': collectedAmount,
      'balanceRemaining': balanceRemaining,
      'amount': collectedAmount,
      'paymentMode': paymentMode.name,
      'photoBase64': photoBase64,
      'photoPath': photoPath,
      'photoUrl': photoUrl,
      'chequeNumber': chequeNumber,
      'bankName': bankName,
      'referenceNumber': referenceNumber,
      'remarks': remarks,
      'salesmanName': salesmanName,
      'collectedAt': collectedAt.toIso8601String(),
      'billDate': billDate.toIso8601String(),
    };
  }

  factory CollectionModel.fromJson(Map<String, dynamic> json) {
    final collected = (json['collectedAmount'] ?? json['amount'] ?? 0.0) as num;
    final bill = (json['billAmount'] ?? collected) as num;

    final collDate = json['collectedAt'] != null
        ? DateTime.tryParse(json['collectedAt'] as String) ?? DateTime.now()
        : DateTime.now();

    final bDate = json['billDate'] != null
        ? DateTime.tryParse(json['billDate'] as String) ?? collDate
        : collDate;

    return CollectionModel(
      id: json['id'] as String,
      businessName: json['businessName'] as String? ?? 'Purva Enterprises',
      shopId: json['shopId'] as String,
      shopName: json['shopName'] as String,
      routeId: json['routeId'] as String? ?? '',
      routeName: json['routeName'] as String? ?? '',
      billNumber: json['billNumber'] as String? ?? '',
      billAmount: bill.toDouble(),
      collectedAmount: collected.toDouble(),
      balanceRemaining: (json['balanceRemaining'] as num?)?.toDouble(),
      paymentMode: PaymentMode.fromString(json['paymentMode'] as String? ?? 'cash'),
      photoBase64: json['photoBase64'] as String?,
      photoPath: json['photoPath'] as String?,
      photoUrl: json['photoUrl'] as String?,
      chequeNumber: json['chequeNumber'] as String?,
      bankName: json['bankName'] as String?,
      referenceNumber: json['referenceNumber'] as String?,
      remarks: json['remarks'] as String?,
      salesmanName: json['salesmanName'] as String? ?? 'Akash',
      collectedAt: collDate,
      billDate: bDate,
    );
  }

  CollectionModel copyWith({
    String? id,
    String? businessName,
    String? shopId,
    String? shopName,
    String? routeId,
    String? routeName,
    String? billNumber,
    double? billAmount,
    double? collectedAmount,
    double? balanceRemaining,
    PaymentMode? paymentMode,
    String? photoBase64,
    bool clearPhoto = false,
    String? photoPath,
    String? photoUrl,
    String? chequeNumber,
    String? bankName,
    String? referenceNumber,
    String? remarks,
    String? salesmanName,
    DateTime? collectedAt,
    DateTime? billDate,
  }) {
    return CollectionModel(
      id: id ?? this.id,
      businessName: businessName ?? this.businessName,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      routeId: routeId ?? this.routeId,
      routeName: routeName ?? this.routeName,
      billNumber: billNumber ?? this.billNumber,
      billAmount: billAmount ?? this.billAmount,
      collectedAmount: collectedAmount ?? this.collectedAmount,
      balanceRemaining: balanceRemaining ?? this.balanceRemaining,
      paymentMode: paymentMode ?? this.paymentMode,
      photoBase64: clearPhoto ? null : (photoBase64 ?? this.photoBase64),
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
      chequeNumber: chequeNumber ?? this.chequeNumber,
      bankName: bankName ?? this.bankName,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      remarks: remarks ?? this.remarks,
      salesmanName: salesmanName ?? this.salesmanName,
      collectedAt: collectedAt ?? this.collectedAt,
      billDate: billDate ?? this.billDate,
    );
  }
}
