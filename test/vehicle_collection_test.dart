import 'package:flutter_test/flutter_test.dart';
import 'package:daily_collection_app/models/vehicle_collection_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VehicleCollectionModel Unit Tests', () {
    test('Calculates totalBillsAmount and netHandoverAmount with single expense correctly', () {
      final bills = [
        VehicleBillEntry(billNumber: '101', amount: 1200.0, shopName: 'Shop A'),
        VehicleBillEntry(billNumber: '102', amount: 800.0, shopName: 'Shop B'),
        VehicleBillEntry(billNumber: '103', amount: 500.0, shopName: 'Shop C'),
      ];

      final vehicleCol = VehicleCollectionModel(
        id: 'vc-test-1',
        date: DateTime(2026, 10, 16),
        vehicleNo: 'MH 14 HG 2426',
        expenseType: 'CNG',
        expenseAmount: 450.0,
        bills: bills,
        employeeName: 'Akash',
        receivedByName: 'Office / Owner',
      );

      expect(vehicleCol.totalBillsAmount, 2500.0);
      expect(vehicleCol.expenseAmount, 450.0);
      expect(vehicleCol.netHandoverAmount, 2050.0);
      expect(vehicleCol.billsCount, 3);
      expect(vehicleCol.vehicleNo, 'MH 14 HG 2426');
      expect(vehicleCol.expenseType, 'CNG');
    });

    test('Calculates multi-fuel expenses (both CNG and Petrol filled on same day)', () {
      final bills = [
        VehicleBillEntry(billNumber: '501', amount: 4000.0),
        VehicleBillEntry(billNumber: '502', amount: 2000.0),
      ];

      final expenses = [
        VehicleExpenseEntry(type: 'CNG', amount: 1200.0),
        VehicleExpenseEntry(type: 'Petrol', amount: 500.0),
      ];

      final vehicleCol = VehicleCollectionModel(
        id: 'vc-test-multi',
        date: DateTime(2026, 10, 16),
        vehicleNo: 'MH 14 GD 6212',
        expenses: expenses,
        bills: bills,
        employeeName: 'Akash',
        denominations: {
          '500': 8, // 4000
          '200': 1, // 200
          '100': 1, // 100
          'coins': 0, // Total = 4300
        },
      );

      expect(vehicleCol.totalBillsAmount, 6000.0);
      expect(vehicleCol.totalExpensesAmount, 1700.0);
      expect(vehicleCol.netHandoverAmount, 4300.0);
      expect(vehicleCol.expenseType, 'CNG + Petrol');
      expect(vehicleCol.countedCashTotal, 4300);
    });

    test('Correctly handles zero expenses and multiple vehicles (MH14GD6212, MH14KA2059)', () {
      final bills = [
        VehicleBillEntry(billNumber: '201', amount: 3000.0),
      ];

      final vehicleCol = VehicleCollectionModel(
        id: 'vc-test-2',
        date: DateTime(2026, 10, 16),
        vehicleNo: 'MH 14 GD 6212',
        expenseType: 'Petrol',
        expenseAmount: 0.0,
        bills: bills,
        employeeName: 'Akash',
      );

      expect(vehicleCol.totalBillsAmount, 3000.0);
      expect(vehicleCol.netHandoverAmount, 3000.0);
      expect(vehicleCol.vehicleNo, 'MH 14 GD 6212');
    });

    test('JSON serialization and deserialization preserves multi-expenses and denominations', () {
      final bills = [
        VehicleBillEntry(billNumber: '301', amount: 1500.0, shopName: 'Om Sai'),
        VehicleBillEntry(billNumber: '302', amount: 2500.0, shopName: 'Ganesh Kirana'),
      ];

      final expenses = [
        VehicleExpenseEntry(type: 'CNG', amount: 800.0),
        VehicleExpenseEntry(type: 'Petrol', amount: 200.0),
      ];

      final original = VehicleCollectionModel(
        id: 'vc-test-3',
        date: DateTime(2026, 10, 16),
        vehicleNo: 'MH 14 KA 2059',
        expenses: expenses,
        bills: bills,
        employeeName: 'Akash',
        receivedByName: 'Owner',
        remarks: 'Route 3 full coverage',
        denominations: {
          '500': 6,
          'coins': 0,
        },
      );

      final json = original.toJson();
      final revived = VehicleCollectionModel.fromJson(json);

      expect(revived.id, original.id);
      expect(revived.vehicleNo, 'MH 14 KA 2059');
      expect(revived.totalExpensesAmount, 1000.0);
      expect(revived.expenses.length, 2);
      expect(revived.expenses[0].type, 'CNG');
      expect(revived.expenses[1].type, 'Petrol');
      expect(revived.totalBillsAmount, 4000.0);
      expect(revived.netHandoverAmount, 3000.0);
      expect(revived.bills.length, 2);
      expect(revived.bills[0].billNumber, '301');
      expect(revived.bills[1].amount, 2500.0);
      expect(revived.employeeName, 'Akash');
      expect(revived.remarks, 'Route 3 full coverage');
      expect(revived.countedCashTotal, 3000);
    });

    test('WhatsApp text generation formats correctly with multi-expenses and denominations', () {
      final bills = [
        VehicleBillEntry(billNumber: '1042', amount: 1500.0),
        VehicleBillEntry(billNumber: '1043', amount: 2500.0),
      ];

      final expenses = [
        VehicleExpenseEntry(type: 'CNG', amount: 500.0),
        VehicleExpenseEntry(type: 'Petrol', amount: 300.0),
      ];

      final model = VehicleCollectionModel(
        id: 'vc-test-4',
        date: DateTime(2026, 10, 16),
        vehicleNo: 'MH 14 HG 2426',
        expenses: expenses,
        bills: bills,
        employeeName: 'Akash',
        denominations: {
          '500': 6,
          '200': 1,
          'coins': 0,
        },
      );

      final text = model.generateWhatsAppText();
      expect(text, contains('MH 14 HG 2426'));
      expect(text, contains('Akash'));
      expect(text, contains('Bill #1042'));
      expect(text, contains('Total Bills Collection'));
      expect(text, contains('CNG Expense'));
      expect(text, contains('Petrol Expense'));
      expect(text, contains('Total Fuel/Expenses'));
      expect(text, contains('NET CASH HANDOVER'));
      expect(text, contains('PHYSICAL CASH VERIFICATION'));
    });
  });
}
