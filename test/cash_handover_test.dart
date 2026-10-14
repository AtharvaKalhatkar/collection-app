import 'package:flutter_test/flutter_test.dart';
import 'package:daily_collection_app/models/cash_handover_model.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CashHandoverModel Unit Tests', () {
    test('Calculates totalCounted, variance, and match status correctly', () {
      final handover = CashHandoverModel(
        id: 'test-1',
        date: DateTime(2026, 10, 14),
        createdAt: DateTime(2026, 10, 14, 19, 0),
        salesmanName: 'Akash',
        receivedByName: 'Office Cashier',
        businessName: 'All',
        count500: 2, // 1000
        count200: 1, // 200
        count100: 3, // 300
        count50: 1,  // 50
        count20: 2,  // 40
        count10: 1,  // 10
        coinsAmount: 15.0, // 15
        totalCounted: 1615.0,
        totalExpected: 1615.0,
        variance: 0.0,
        remarks: 'All good',
      );

      expect(handover.totalCounted, 1615.0);
      expect(handover.totalExpected, 1615.0);
      expect(handover.variance, 0.0);
      expect(handover.isMatched, isTrue);
      expect(handover.hasShortage, isFalse);
      expect(handover.hasSurplus, isFalse);
    });

    test('Detects cash shortage and surplus accurately', () {
      final shortageHandover = CashHandoverModel(
        id: 'test-2',
        date: DateTime(2026, 10, 14),
        createdAt: DateTime.now(),
        salesmanName: 'Akash',
        receivedByName: 'Cashier',
        businessName: 'Purva Enterprises',
        count500: 1,
        count200: 0,
        count100: 0,
        count50: 0,
        count20: 0,
        count10: 0,
        coinsAmount: 0.0,
        totalCounted: 500.0,
        totalExpected: 700.0,
        variance: -200.0,
      );

      expect(shortageHandover.isMatched, isFalse);
      expect(shortageHandover.hasShortage, isTrue);
      expect(shortageHandover.hasSurplus, isFalse);

      final surplusHandover = CashHandoverModel(
        id: 'test-3',
        date: DateTime(2026, 10, 14),
        createdAt: DateTime.now(),
        salesmanName: 'Akash',
        receivedByName: 'Cashier',
        businessName: 'Manas Sales',
        count500: 2,
        count200: 0,
        count100: 0,
        count50: 0,
        count20: 0,
        count10: 0,
        coinsAmount: 0.0,
        totalCounted: 1000.0,
        totalExpected: 900.0,
        variance: 100.0,
      );

      expect(surplusHandover.isMatched, isFalse);
      expect(surplusHandover.hasShortage, isFalse);
      expect(surplusHandover.hasSurplus, isTrue);
    });

    test('Serialization to and from JSON preserves all fields', () {
      final original = CashHandoverModel(
        id: 'json-roundtrip',
        date: DateTime(2026, 10, 14),
        createdAt: DateTime(2026, 10, 14, 19, 15),
        salesmanName: 'Akash Shinde',
        receivedByName: 'Owner - Sahil',
        businessName: 'Purva Enterprises',
        count500: 5,
        count200: 4,
        count100: 10,
        count50: 2,
        count20: 5,
        count10: 10,
        coinsAmount: 25.5,
        totalCounted: 4525.5,
        totalExpected: 4525.5,
        variance: 0.0,
        remarks: 'Handed over in office',
      );

      final json = original.toJson();
      final restored = CashHandoverModel.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.salesmanName, 'Akash Shinde');
      expect(restored.receivedByName, 'Owner - Sahil');
      expect(restored.businessName, 'Purva Enterprises');
      expect(restored.count500, 5);
      expect(restored.count200, 4);
      expect(restored.count100, 10);
      expect(restored.count50, 2);
      expect(restored.count20, 5);
      expect(restored.count10, 10);
      expect(restored.coinsAmount, 25.5);
      expect(restored.totalCounted, 4525.5);
      expect(restored.variance, 0.0);
      expect(restored.remarks, 'Handed over in office');
    });

    test('WhatsApp report text generation formats properly', () {
      final provider = CollectionProvider();
      final handover = CashHandoverModel(
        id: 'wa-test',
        date: DateTime(2026, 10, 14),
        createdAt: DateTime(2026, 10, 14, 19, 0),
        salesmanName: 'Akash',
        receivedByName: 'Mr. Ramesh (Owner)',
        businessName: 'Both Firms',
        count500: 4,
        count200: 2,
        count100: 5,
        count50: 0,
        count20: 0,
        count10: 0,
        coinsAmount: 0.0,
        totalCounted: 2900.0,
        totalExpected: 2900.0,
        variance: 0.0,
        remarks: 'Evening cash closing',
      );

      final text = provider.generateCashHandoverWhatsAppText(handover);

      expect(text, contains('CASH HANDOVER REPORT'));
      expect(text, contains('Akash'));
      expect(text, contains('Mr. Ramesh (Owner)'));
      expect(text, contains('₹500 × 4 = ₹2000'));
      expect(text, contains('₹200 × 2 = ₹400'));
      expect(text, contains('₹100 × 5 = ₹500'));
      expect(text, contains('2,900'));
      expect(text, contains('PERFECT MATCH'));
    });
  });
}
