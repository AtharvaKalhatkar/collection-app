import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_collection_app/models/payment_mode.dart';
import 'package:daily_collection_app/models/collection_model.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Bill Pending vs Paid & Follow-up Payment Verification', () {
    test('ATA Kirana: Bill 40000 with 30000 collected is marked PENDING with 10000 due', () async {
      final provider = CollectionProvider();
      // Wait for async sample data initialization
      await Future.delayed(const Duration(milliseconds: 100));

      // ATA Kirana has initial bill PE-4081: 40000 total, 30000 collected
      final pendingBills = provider.getPendingBills(forShopId: 'shop-ata-kirana');
      expect(pendingBills.length, 1);

      final bill = pendingBills.first;
      expect(bill.billNumber, 'PE-4081');
      expect(bill.billTotal, 40000.0);
      expect(bill.totalCollected, 30000.0);
      expect(bill.balanceDue, 10000.0);
      expect(bill.isPending, true);
      expect(bill.isPaid, false);
      expect(bill.percentPaid, 75.0);

      // Total balance for ATA Kirana store is 10,000
      expect(provider.getTotalBalanceForShop('shop-ata-kirana'), 10000.0);
    });

    test('Recording subsequent payment of 10000 clears the bill and marks it PAID (100%)', () async {
      final provider = CollectionProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      final initialBill = provider.getBillSummary('shop-ata-kirana', 'PE-4081');
      expect(initialBill, isNotNull);
      expect(initialBill!.balanceDue, 10000.0);
      expect(initialBill.isPending, true);

      // Akash visits later and collects the remaining balance of 10,000 via UPI
      final followUpCollection = CollectionModel(
        id: 'col-follow-up-1',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'ATA Kirana',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'PE-4081',
        billAmount: 40000.0,
        collectedAmount: 10000.0,
        balanceRemaining: 0.0,
        paymentMode: PaymentMode.upi,
        referenceNumber: 'UPI/9812401823/GPAY',
        remarks: 'Cleared final balance for PE-4081',
        salesmanName: 'Akash',
        collectedAt: DateTime.now(),
      );

      await provider.addCollection(followUpCollection);

      // Verify bill PE-4081 is now 100% PAID
      final updatedBill = provider.getBillSummary('shop-ata-kirana', 'PE-4081');
      expect(updatedBill, isNotNull);
      expect(updatedBill!.billTotal, 40000.0);
      expect(updatedBill.totalCollected, 40000.0);
      expect(updatedBill.balanceDue, 0.0);
      expect(updatedBill.isPaid, true);
      expect(updatedBill.isPending, false);
      expect(updatedBill.percentPaid, 100.0);
      expect(updatedBill.collections.length, 2);

      // It should no longer appear in pending bills
      final pendingAfter = provider.getPendingBills(forShopId: 'shop-ata-kirana');
      expect(pendingAfter.isEmpty, true);

      // ATA Kirana outstanding balance is now 0.0
      expect(provider.getTotalBalanceForShop('shop-ata-kirana'), 0.0);
    });
  });
}
