class PendingBillModel {
  final String id;
  final String businessName;
  final String routeId;
  final String routeName;
  final String shopId;
  final String shopName;
  final DateTime invoiceDate;
  final DateTime deliveryDate;
  final String billNumber;
  final double totalAmount;
  final double collectedAmount;
  final String? photoBase64;
  final String? photoPath;
  final String status; // 'pending', 'partial', 'paid'
  final DateTime createdAt;

  PendingBillModel({
    required this.id,
    required this.businessName,
    required this.routeId,
    required this.routeName,
    required this.shopId,
    required this.shopName,
    required this.invoiceDate,
    required this.deliveryDate,
    required this.billNumber,
    required this.totalAmount,
    this.collectedAmount = 0.0,
    this.photoBase64,
    this.photoPath,
    this.status = 'pending',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get balanceDue =>
      (totalAmount - collectedAmount) > 0 ? (totalAmount - collectedAmount) : 0.0;

  String get firmName => businessName;

  bool get isPaid => balanceDue <= 0.001;

  bool get isPartial => collectedAmount > 0 && balanceDue > 0.001;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'businessName': businessName,
      'routeId': routeId,
      'routeName': routeName,
      'shopId': shopId,
      'shopName': shopName,
      'invoiceDate': invoiceDate.toIso8601String(),
      'deliveryDate': deliveryDate.toIso8601String(),
      'billNumber': billNumber,
      'totalAmount': totalAmount,
      'collectedAmount': collectedAmount,
      'photoBase64': photoBase64,
      'photoPath': photoPath,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PendingBillModel.fromJson(Map<String, dynamic> json) {
    return PendingBillModel(
      id: json['id'] as String,
      businessName: json['businessName'] as String? ?? 'Purva Enterprises',
      routeId: json['routeId'] as String? ?? '',
      routeName: json['routeName'] as String? ?? '',
      shopId: json['shopId'] as String? ?? '',
      shopName: json['shopName'] as String? ?? '',
      invoiceDate: json['invoiceDate'] != null
          ? DateTime.tryParse(json['invoiceDate'] as String) ?? DateTime.now()
          : DateTime.now(),
      deliveryDate: json['deliveryDate'] != null
          ? DateTime.tryParse(json['deliveryDate'] as String) ?? DateTime.now()
          : DateTime.now(),
      billNumber: json['billNumber'] as String? ?? '',
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      collectedAmount: (json['collectedAmount'] as num?)?.toDouble() ?? 0.0,
      photoBase64: json['photoBase64'] as String?,
      photoPath: json['photoPath'] as String?,
      status: json['status'] as String? ?? 'pending',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  PendingBillModel copyWith({
    String? id,
    String? businessName,
    String? routeId,
    String? routeName,
    String? shopId,
    String? shopName,
    DateTime? invoiceDate,
    DateTime? deliveryDate,
    String? billNumber,
    double? totalAmount,
    double? collectedAmount,
    String? photoBase64,
    String? photoPath,
    String? status,
    DateTime? createdAt,
  }) {
    return PendingBillModel(
      id: id ?? this.id,
      businessName: businessName ?? this.businessName,
      routeId: routeId ?? this.routeId,
      routeName: routeName ?? this.routeName,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      billNumber: billNumber ?? this.billNumber,
      totalAmount: totalAmount ?? this.totalAmount,
      collectedAmount: collectedAmount ?? this.collectedAmount,
      photoBase64: photoBase64 ?? this.photoBase64,
      photoPath: photoPath ?? this.photoPath,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
