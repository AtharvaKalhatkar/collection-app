import 'package:flutter_test/flutter_test.dart';
import 'package:daily_collection_app/models/vehicle_collection_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VehicleCollectionModel Unit Tests', () {
    test('Calculates totalBillsAmount and netHandoverAmount with expenses correctly', () {
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

    test('JSON serialization and deserialization preserves all fields', () {
      final bills = [
        VehicleBillEntry(billNumber: '301', amount: 1500.0, shopName: 'Om Sai'),
        VehicleBillEntry(billNumber: '302', amount: 2500.0, shopName: 'Ganesh Kirana'),
      ];

      final original = VehicleCollectionModel(
        id: 'vc-test-3',
        date: DateTime(2026, 10, 16),
        vehicleNo: 'MH 14 KA 2059',
        expenseType: 'Diesel',
        expenseAmount: 600.0,
        bills: bills,
        employeeName: 'Akash',
        receivedByName: 'Owner',
        remarks: 'Route 3 full coverage',
      );

      final json = original.toJson();
      final revived = VehicleCollectionModel.fromJson(json);

      expect(revived.id, original.id);
      expect(revived.vehicleNo, 'MH 14 KA 2059');
      expect(revived.expenseType, 'Diesel');
      expect(revived.expenseAmount, 600.0);
      expect(revived.totalBillsAmount, 4000.0);
      expect(revived.netHandoverAmount, 3400.0);
      expect(revived.bills.length, 2);
      expect(revived.bills[0].billNumber, '301');
      expect(revived.bills[1].amount, 2500.0);
      expect(revived.employeeName, 'Akash');
      expect(revived.remarks, 'Route 3 full coverage');
    });

    test('WhatsApp text generation formats correctly with vehicle, bills, expense and net amount', () {
      final bills = [
        VehicleBillEntry(billNumber: '1042', amount: 1500.0),
        VehicleBillEntry(billNumber: '1043', amount: 2500.0),
      ];

      final model = VehicleCollectionModel(
        id: 'vc-test-4',
        date: DateTime(2026, 10, 16),
        vehicleNo: 'MH 14 HG 2426',
        expenseType: 'CNG',
        expenseAmount: 500.0,
        bills: bills,
        employeeName: 'Akash',
      );

      final text = model.generateWhatsAppText();
      expect(text, contains('MH 14 HG 2426'));
      expect(text, contains('Akash'));
      expect(text, contains('Bill #1042'));
      expect(text, contains('Total Bills Collection'));
      expect(text, contains('CNG'));
      expect(text, contains('NET CASH HANDOVER'));
    });
  });
}
