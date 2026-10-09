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
  final List<String> photosBase64;
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
    String? photoBase64,
    List<String>? photosBase64,
    this.photoPath,
    this.status = 'pending',
    DateTime? createdAt,
  })  : photosBase64 = (photosBase64 != null && photosBase64.isNotEmpty)
            ? List.unmodifiable(photosBase64)
            : (photoBase64 != null && photoBase64.isNotEmpty ? List.unmodifiable([photoBase64]) : const []),
        photoBase64 = (photosBase64 != null && photosBase64.isNotEmpty)
            ? photosBase64.first
            : photoBase64,
        createdAt = createdAt ?? DateTime.now();

  double get balanceDue =>
      (totalAmount - collectedAmount) > 0 ? (totalAmount - collectedAmount) : 0.0;

  String get firmName => businessName;
  DateTime get billDate => invoiceDate;
  double get billAmount => totalAmount;

  bool get isPaid => balanceDue <= 0.001;

  bool get isPartial => collectedAmount > 0 && balanceDue > 0.001;

  List<String> get allPhotos => photosBase64.isNotEmpty
      ? photosBase64
      : (photoBase64 != null && photoBase64!.isNotEmpty ? [photoBase64!] : const []);

  bool get hasPhoto => allPhotos.isNotEmpty;
  int get photosCount => allPhotos.length;

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
      'photoBase64': null, // Avoid duplicating large base64 strings in Firestore and local storage
      'photosBase64': allPhotos,
      'photoPath': photoPath,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PendingBillModel.fromJson(Map<String, dynamic> json) {
    final rawList = json['photosBase64'] as List<dynamic>?;
    final parsedPhotos = rawList?.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    final singlePhoto = json['photoBase64'] as String?;

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
      photoBase64: singlePhoto,
      photosBase64: parsedPhotos,
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
    List<String>? photosBase64,
    String? photoPath,
    String? status,
    DateTime? createdAt,
    bool clearPhoto = false,
  }) {
    final newPhotos = clearPhoto
        ? const <String>[]
        : (photosBase64 ?? (photoBase64 != null ? [photoBase64] : this.photosBase64));

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
      photoBase64: clearPhoto ? null : (newPhotos.isNotEmpty ? newPhotos.first : (photoBase64 ?? this.photoBase64)),
      photosBase64: newPhotos,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
