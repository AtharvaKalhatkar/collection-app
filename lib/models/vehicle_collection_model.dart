import '../utils/currency_formatter.dart';
import 'package:intl/intl.dart';

class VehicleBillEntry {
  String billNumber;
  double amount;
  String? shopName;

  VehicleBillEntry({
    required this.billNumber,
    required this.amount,
    this.shopName,
  });

  Map<String, dynamic> toJson() {
    return {
      'billNumber': billNumber,
      'amount': amount,
      'shopName': shopName,
    };
  }

  factory VehicleBillEntry.fromJson(Map<String, dynamic> json) {
    return VehicleBillEntry(
      billNumber: json['billNumber'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      shopName: json['shopName'] as String?,
    );
  }
}

class VehicleCollectionModel {
  final String id;
  final DateTime date;
  final String vehicleNo;
  final String expenseType; // 'CNG', 'Petrol', 'Diesel', 'None'
  final double expenseAmount;
  final List<VehicleBillEntry> bills;
  final String employeeName;
  final String receivedByName;
  final String? remarks;
  final DateTime createdAt;

  VehicleCollectionModel({
    required this.id,
    required this.date,
    required this.vehicleNo,
    required this.expenseType,
    required this.expenseAmount,
    required this.bills,
    required this.employeeName,
    this.receivedByName = 'Office / Owner',
    this.remarks,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get totalBillsAmount => bills.fold(0.0, (sum, b) => sum + b.amount);

  double get netHandoverAmount => totalBillsAmount - expenseAmount;

  int get billsCount => bills.where((b) => b.billNumber.trim().isNotEmpty || b.amount > 0).length;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'vehicleNo': vehicleNo,
      'expenseType': expenseType,
      'expenseAmount': expenseAmount,
      'bills': bills.map((b) => b.toJson()).toList(),
      'employeeName': employeeName,
      'receivedByName': receivedByName,
      'remarks': remarks,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory VehicleCollectionModel.fromJson(Map<String, dynamic> json) {
    return VehicleCollectionModel(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      vehicleNo: json['vehicleNo'] as String? ?? 'MH 14 HG 2426',
      expenseType: json['expenseType'] as String? ?? 'CNG',
      expenseAmount: (json['expenseAmount'] as num?)?.toDouble() ?? 0.0,
      bills: (json['bills'] as List<dynamic>?)
              ?.map((e) => VehicleBillEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      employeeName: json['employeeName'] as String? ?? 'Akash',
      receivedByName: json['receivedByName'] as String? ?? 'Office / Owner',
      remarks: json['remarks'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  String generateWhatsAppText() {
    final dateStr = DateFormat('dd MMM yyyy').format(date);
    final timeStr = DateFormat('hh:mm a').format(createdAt);
    final validBills = bills.where((b) => b.billNumber.trim().isNotEmpty || b.amount > 0).toList();

    final buffer = StringBuffer();
    buffer.writeln('🚚 *VEHICLE CASH COLLECTION & HANDOVER*');
    buffer.writeln('📅 Date: $dateStr ($timeStr)');
    buffer.writeln('🚛 Vehicle No: $vehicleNo');
    buffer.writeln('👤 Employee: $employeeName');
    buffer.writeln('----------------------------------');
    buffer.writeln('🧾 *BILLS COLLECTED (${validBills.length} Invoices)*:');

    if (validBills.isEmpty) {
      buffer.writeln('  (No individual bills listed)');
    } else {
      for (int i = 0; i < validBills.length; i++) {
        final b = validBills[i];
        final shopInfo = (b.shopName != null && b.shopName!.trim().isNotEmpty) ? ' (${b.shopName!.trim()})' : '';
        buffer.writeln('  ${i + 1}. Bill #${b.billNumber}$shopInfo: ${CurrencyFormatter.format(b.amount)}');
      }
    }

    buffer.writeln('----------------------------------');
    buffer.writeln('💰 *Total Bills Collection:* ${CurrencyFormatter.format(totalBillsAmount)}');

    if (expenseAmount > 0) {
      buffer.writeln('⛽ *Fuel / Expense ($expenseType):* -${CurrencyFormatter.format(expenseAmount)}');
      buffer.writeln('----------------------------------');
    }

    buffer.writeln('💵 *NET CASH HANDOVER:* *${CurrencyFormatter.format(netHandoverAmount)}*');
    buffer.writeln('----------------------------------');
    buffer.writeln('Handed over by: $employeeName');
    buffer.writeln('Received by: $receivedByName');
    if (remarks != null && remarks!.trim().isNotEmpty) {
      buffer.writeln('📝 Remarks: ${remarks!.trim()}');
    }
    buffer.writeln('----------------------------------');
    buffer.writeln('_Generated via Daily Collection Pro_');

    return buffer.toString().trim();
  }
}
