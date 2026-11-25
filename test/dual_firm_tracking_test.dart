import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_collection_app/models/collection_model.dart';
import 'package:daily_collection_app/models/pending_bill_model.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';

Future<CollectionProvider> createSeededDualFirmProvider() async {
  final provider = CollectionProvider(autoInitialize: false);
  await provider.initialize();
  final now = DateTime.now();

  await provider.addPendingBill(PendingBillModel(
    id: 'test-pb-purva-1',
    businessName: 'Purva Enterprises',
    shopId: 'ata-kirana',
    shopName: 'ATA Kirana',
    routeId: 'r-chakan',
    routeName: 'Chakan',
    invoiceDate: now,
    deliveryDate: now,
    billNumber: 'PE-101',
    totalAmount: 40000.0,
    collectedAmount: 30000.0,
    status: 'partial',
  ));

  // Purva Enterprises (Total: 65000 = 60000 Cash + 5000 Digital, Due: 10000, 3 bills)
  await provider.addCollection(CollectionModel(
    id: 'purva-1',
    businessName: 'Purva Enterprises',
    shopId: 'ata-kirana',
    shopName: 'ATA Kirana',
    routeId: 'r-chakan',
    routeName: 'Chakan',
    billNumber: 'PE-101',
    billAmount: 40000.0,
    collectedAmount: 30000.0,
    balanceRemaining: 10000.0,
    paymentMode: PaymentMode.cash,
    salesmanName: 'Akash',
    collectedAt: now,
  ));
  await provider.addCollection(CollectionModel(
    id: 'purva-2',
    businessName: 'Purva Enterprises',
    shopId: 'mahesh-store',
    shopName: 'Mahesh Provision',
    routeId: 'r-chakan',
    routeName: 'Chakan',
    billNumber: 'PE-102',
    billAmount: 30000.0,
    collectedAmount: 30000.0,
    balanceRemaining: 0.0,
    paymentMode: PaymentMode.cash,
    salesmanName: 'Akash',
    collectedAt: now,
  ));
  await provider.addCollection(CollectionModel(
    id: 'purva-3',
    businessName: 'Purva Enterprises',
    shopId: 'om-traders',
    shopName: 'Om Traders',
    routeId: 'r-chakan',
    routeName: 'Chakan',
    billNumber: 'PE-103',
    billAmount: 5000.0,
    collectedAmount: 5000.0,
    balanceRemaining: 0.0,
    paymentMode: PaymentMode.cheque,
    chequeNumber: '123456',
    bankName: 'HDFC Bank',
    salesmanName: 'Akash',
    collectedAt: now,
  ));

  // Manas Sales (Total: 47000 = 40000 Cash + 7000 Digital, Due: 0, 3 bills)
  await provider.addCollection(CollectionModel(
    id: 'manas-1',
    businessName: 'Manas Sales',
    shopId: 'shree-ganesh',
    shopName: 'Shree Ganesh',
    routeId: 'r-shikrapur',
    routeName: 'Shikrapur',
    billNumber: 'MS-201',
    billAmount: 40000.0,
    collectedAmount: 40000.0,
    balanceRemaining: 0.0,
    paymentMode: PaymentMode.cash,
    salesmanName: 'Akash',
    collectedAt: now,
  ));
  await provider.addCollection(CollectionModel(
    id: 'manas-2',
    businessName: 'Manas Sales',
    shopId: 'sai-krupa',
    shopName: 'Sai Krupa',
    routeId: 'r-shikrapur',
    routeName: 'Shikrapur',
    billNumber: 'MS-202',
    billAmount: 4000.0,
    collectedAmount: 4000.0,
    balanceRemaining: 0.0,
    paymentMode: PaymentMode.upi,
    referenceNumber: 'UPI1',
    bankName: 'Central Bank',
    salesmanName: 'Akash',
    collectedAt: now,
  ));
  await provider.addCollection(CollectionModel(
    id: 'manas-3',
    businessName: 'Manas Sales',
    shopId: 'ata-kirana',
    shopName: 'ATA Kirana',
    routeId: 'r-chakan',
    routeName: 'Chakan',
    billNumber: 'MS-203',
    billAmount: 3000.0,
    collectedAmount: 3000.0,
    balanceRemaining: 0.0,
    paymentMode: PaymentMode.netBanking,
    referenceNumber: 'NEFT1',
    bankName: 'State Bank of India',
    salesmanName: 'Akash',
    collectedAt: now,
  ));

  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Dual-Firm Entity Separation & Metrics (Purva Enterprises vs Manas Sales)', () {
    test('Accurately calculates per-firm collections, invoices, and pending balances', () async {
      final provider = await createSeededDualFirmProvider();

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
      final provider = await createSeededDualFirmProvider();

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
