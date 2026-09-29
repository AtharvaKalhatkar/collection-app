import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Dual-Firm Entity Separation & Metrics (Purva Enterprises vs Manas Sales)', () {
    test('Accurately calculates per-firm collections, invoices, and pending balances', () async {
      final provider = CollectionProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify Purva Enterprises
      expect(provider.getTotalCollectionForBusiness('Purva Enterprises'), 65000.0);
      expect(provider.getBillsCountForBusiness('Purva Enterprises'), 3);
      expect(provider.getPendingBalanceForBusiness('Purva Enterprises'), 10000.0);
      expect(provider.getCashForBusiness('Purva Enterprises'), 60000.0); // 30k ATA + 30k Mahesh
      expect(provider.getDigitalForBusiness('Purva Enterprises'), 5000.0); // 5k Cheque Om Traders

      // Verify Manas Sales
      expect(provider.getTotalCollectionForBusiness('Manas Sales'), 47000.0);
      expect(provider.getBillsCountForBusiness('Manas Sales'), 3);
      expect(provider.getPendingBalanceForBusiness('Manas Sales'), 0.0); // All paid
      expect(provider.getCashForBusiness('Manas Sales'), 40000.0); // 40k Shree Ganesh
      expect(provider.getDigitalForBusiness('Manas Sales'), 7000.0); // 4k UPI Sai Krupa + 3k NetBanking ATA

      // Verify Combined Reconciled Totals
      final combinedTotal = provider.getTotalCollectionForBusiness('Purva Enterprises') +
          provider.getTotalCollectionForBusiness('Manas Sales');
      expect(combinedTotal, 112000.0);
      expect(provider.totalCollection, 112000.0);
      expect(provider.totalCash, 100000.0);
      expect(provider.totalUpi, 4000.0);
      expect(provider.totalCheque, 5000.0);
      expect(provider.totalNetBanking, 3000.0);
    });

    test('Filtering by firm isolates records and updates active collections', () async {
      final provider = CollectionProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      // Filter to Purva Enterprises
      provider.setFilterBusiness('Purva Enterprises');
      expect(provider.filterBusiness, 'Purva Enterprises');
      final purvaCollections = provider.getFilteredCollections();
      expect(purvaCollections.length, 3);
      expect(purvaCollections.every((c) => c.businessName == 'Purva Enterprises'), true);
      expect(provider.totalCollection, 65000.0);
      expect(provider.totalBalanceDue, 10000.0);

      // Filter to Manas Sales
      provider.setFilterBusiness('Manas Sales');
      expect(provider.filterBusiness, 'Manas Sales');
      final manasCollections = provider.getFilteredCollections();
      expect(manasCollections.length, 3);
      expect(manasCollections.every((c) => c.businessName == 'Manas Sales'), true);
      expect(provider.totalCollection, 47000.0);
      expect(provider.totalBalanceDue, 0.0);

      // Reset to All Firms
      provider.setFilterBusiness(null);
      expect(provider.filterBusiness, isNull);
      expect(provider.getFilteredCollections().length, 6);
      expect(provider.totalCollection, 112000.0);
    });
  });
}
