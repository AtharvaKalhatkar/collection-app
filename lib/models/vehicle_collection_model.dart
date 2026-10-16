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

class VehicleExpenseEntry {
  String type; // 'CNG', 'Petrol', 'Diesel', 'Toll / Other'
  double amount;

  VehicleExpenseEntry({
    required this.type,
    required this.amount,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'amount': amount,
    };
  }

  factory VehicleExpenseEntry.fromJson(Map<String, dynamic> json) {
    return VehicleExpenseEntry(
      type: json['type'] as String? ?? 'CNG',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class VehicleCollectionModel {
  final String id;
  final DateTime date;
  final String vehicleNo;
  final List<VehicleExpenseEntry> expenses;
  final List<VehicleBillEntry> bills;
  final String employeeName;
  final String receivedByName;
  final String? remarks;
  final Map<String, int>? denominations;
  final DateTime createdAt;

  VehicleCollectionModel({
    required this.id,
    required this.date,
    required this.vehicleNo,
    List<VehicleExpenseEntry>? expenses,
    String? expenseType,
    double? expenseAmount,
    required this.bills,
    required this.employeeName,
    this.receivedByName = 'Office / Owner',
    this.remarks,
    this.denominations,
    DateTime? createdAt,
  })  : expenses = expenses ??
            ((expenseAmount != null && expenseAmount > 0)
                ? [VehicleExpenseEntry(type: expenseType ?? 'CNG', amount: expenseAmount)]
                : (expenseType != null && expenseType != 'None' && (expenseAmount ?? 0.0) > 0
                    ? [VehicleExpenseEntry(type: expenseType, amount: expenseAmount ?? 0.0)]
                    : [])),
        createdAt = createdAt ?? DateTime.now();

  double get totalBillsAmount => bills.fold(0.0, (sum, b) => sum + b.amount);

  double get totalExpensesAmount => expenses.fold(0.0, (sum, e) => sum + e.amount);

  // Backward compatibility alias for legacy callers
  double get expenseAmount => totalExpensesAmount;

  // Backward compatibility alias for single expense type string
  String get expenseType {
    final active = expenses.where((e) => e.amount > 0).toList();
    if (active.isEmpty) return 'None';
    return active.map((e) => e.type).join(' + ');
  }

  double get netHandoverAmount => totalBillsAmount - totalExpensesAmount;

  int get billsCount => bills.where((b) => b.billNumber.trim().isNotEmpty || b.amount > 0).length;

  int get countedCashTotal {
    if (denominations == null) return 0;
    int sum = 0;
    sum += (denominations!['500'] ?? 0) * 500;
    sum += (denominations!['200'] ?? 0) * 200;
    sum += (denominations!['100'] ?? 0) * 100;
    sum += (denominations!['50'] ?? 0) * 50;
    sum += (denominations!['20'] ?? 0) * 20;
    sum += (denominations!['10'] ?? 0) * 10;
    sum += (denominations!['coins'] ?? 0);
    return sum;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'vehicleNo': vehicleNo,
      'expenses': expenses.map((e) => e.toJson()).toList(),
      'expenseType': expenseType,
      'expenseAmount': totalExpensesAmount,
      'bills': bills.map((b) => b.toJson()).toList(),
      'employeeName': employeeName,
      'receivedByName': receivedByName,
      'remarks': remarks,
      'denominations': denominations,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory VehicleCollectionModel.fromJson(Map<String, dynamic> json) {
    List<VehicleExpenseEntry> parsedExpenses = [];
    if (json['expenses'] != null) {
      parsedExpenses = (json['expenses'] as List<dynamic>)
          .map((e) => VehicleExpenseEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (json['expenseAmount'] != null && (json['expenseAmount'] as num) > 0) {
      parsedExpenses = [
        VehicleExpenseEntry(
          type: json['expenseType'] as String? ?? 'CNG',
          amount: (json['expenseAmount'] as num).toDouble(),
        ),
      ];
    }

    Map<String, int>? parsedDenominations;
    if (json['denominations'] != null) {
      parsedDenominations = (json['denominations'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toInt()));
    }

    return VehicleCollectionModel(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      vehicleNo: json['vehicleNo'] as String? ?? 'MH 14 HG 2426',
      expenses: parsedExpenses,
      expenseType: json['expenseType'] as String?,
      expenseAmount: (json['expenseAmount'] as num?)?.toDouble(),
      bills: (json['bills'] as List<dynamic>?)
              ?.map((e) => VehicleBillEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      employeeName: json['employeeName'] as String? ?? 'Akash',
      receivedByName: json['receivedByName'] as String? ?? 'Office / Owner',
      remarks: json['remarks'] as String?,
      denominations: parsedDenominations,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  String generateWhatsAppText() {
    final dateStr = DateFormat('dd MMM yyyy').format(date);
    final timeStr = DateFormat('hh:mm a').format(createdAt);
    final validBills = bills.where((b) => b.billNumber.trim().isNotEmpty || b.amount > 0).toList();
    final activeExpenses = expenses.where((e) => e.amount > 0).toList();

    final buffer = StringBuffer();
    buffer.writeln('🚚 *DAILY VEHICLE CASH COLLECTION & HANDOVER*');
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

    if (activeExpenses.isNotEmpty) {
      for (final exp in activeExpenses) {
        buffer.writeln('⛽ *${exp.type} Expense:* -${CurrencyFormatter.format(exp.amount)}');
      }
      if (activeExpenses.length > 1) {
        buffer.writeln('🔻 *Total Fuel/Expenses:* -${CurrencyFormatter.format(totalExpensesAmount)}');
      }
      buffer.writeln('----------------------------------');
    }

    buffer.writeln('💵 *NET CASH HANDOVER:* *${CurrencyFormatter.format(netHandoverAmount)}*');

    if (denominations != null && countedCashTotal > 0) {
      buffer.writeln('----------------------------------');
      buffer.writeln('🪙 *PHYSICAL CASH VERIFICATION*:');
      final noteKeys = ['500', '200', '100', '50', '20', '10'];
      for (final k in noteKeys) {
        final count = denominations![k] ?? 0;
        if (count > 0) {
          final val = count * int.parse(k);
          buffer.writeln('  ₹$k × $count = ${CurrencyFormatter.format(val.toDouble())}');
        }
      }
      final coins = denominations!['coins'] ?? 0;
      if (coins > 0) {
        buffer.writeln('  Coins = ${CurrencyFormatter.format(coins.toDouble())}');
      }
      final diff = countedCashTotal - netHandoverAmount.round();
      final statusMatch = (diff == 0) ? '✅ PERFECT MATCH' : (diff < 0 ? '⚠️ Short: ₹${diff.abs()}' : '⚠️ Excess: ₹$diff');
      buffer.writeln('  *Total Counted:* ${CurrencyFormatter.format(countedCashTotal.toDouble())} ($statusMatch)');
    }

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
