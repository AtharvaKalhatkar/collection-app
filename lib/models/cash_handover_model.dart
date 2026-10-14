class CashHandoverModel {
  final String id;
  final DateTime date;
  final String businessName;
  final String salesmanName;
  final String receivedByName;
  final int count500;
  final int count200;
  final int count100;
  final int count50;
  final int count20;
  final int count10;
  final double coinsAmount;
  final double totalCounted;
  final double totalExpected;
  final double variance;
  final String? remarks;
  final DateTime createdAt;

  CashHandoverModel({
    required this.id,
    required this.date,
    required this.businessName,
    required this.salesmanName,
    this.receivedByName = 'Office / Owner',
    this.count500 = 0,
    this.count200 = 0,
    this.count100 = 0,
    this.count50 = 0,
    this.count20 = 0,
    this.count10 = 0,
    this.coinsAmount = 0.0,
    required this.totalCounted,
    required this.totalExpected,
    required this.variance,
    this.remarks,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isMatched => variance.abs() <= 0.01;
  bool get hasShortage => variance < -0.01;
  bool get hasSurplus => variance > 0.01;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'businessName': businessName,
      'salesmanName': salesmanName,
      'receivedByName': receivedByName,
      'count500': count500,
      'count200': count200,
      'count100': count100,
      'count50': count50,
      'count20': count20,
      'count10': count10,
      'coinsAmount': coinsAmount,
      'totalCounted': totalCounted,
      'totalExpected': totalExpected,
      'variance': variance,
      'remarks': remarks,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CashHandoverModel.fromJson(Map<String, dynamic> json) {
    return CashHandoverModel(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      businessName: json['businessName'] as String? ?? 'All',
      salesmanName: json['salesmanName'] as String? ?? 'Akash',
      receivedByName: json['receivedByName'] as String? ?? 'Office / Owner',
      count500: (json['count500'] as num?)?.toInt() ?? 0,
      count200: (json['count200'] as num?)?.toInt() ?? 0,
      count100: (json['count100'] as num?)?.toInt() ?? 0,
      count50: (json['count50'] as num?)?.toInt() ?? 0,
      count20: (json['count20'] as num?)?.toInt() ?? 0,
      count10: (json['count10'] as num?)?.toInt() ?? 0,
      coinsAmount: (json['coinsAmount'] as num?)?.toDouble() ?? 0.0,
      totalCounted: (json['totalCounted'] as num?)?.toDouble() ?? 0.0,
      totalExpected: (json['totalExpected'] as num?)?.toDouble() ?? 0.0,
      variance: (json['variance'] as num?)?.toDouble() ?? 0.0,
      remarks: json['remarks'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }
}
