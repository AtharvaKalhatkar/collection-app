import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_collection_app/models/shop_model.dart';
import 'package:daily_collection_app/models/route_model.dart';
import 'package:daily_collection_app/models/pending_bill_model.dart';
import 'package:daily_collection_app/models/collection_model.dart';
import 'package:daily_collection_app/models/payment_mode.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'forced_clean_transactions_v5': true,
    });
  });

  test('Outlet Name update synchronizes across shops, collections, and pending bills', () async {
    final provider = CollectionProvider();
    await Future.delayed(const Duration(milliseconds: 100));

    final route = await provider.addRoute(name: 'Chakan Market', description: 'Chakan Route');
    final shop = await provider.addShop(
      name: 'Original Store Name',
      routeId: route.id,
      routeName: route.name,
      mobileNumber: '9876543210',
      address: 'Shop 1, Main Road',
    );

    final bill = PendingBillModel(
      id: 'test_pb_001',
      billNumber: 'INV-101',
      shopId: shop.id,
      shopName: shop.name,
      routeId: route.id,
      routeName: route.name,
      businessName: 'Purva Enterprises',
      totalAmount: 5000.0,
      collectedAmount: 0.0,
      invoiceDate: DateTime(2026, 10, 1),
      deliveryDate: DateTime(2026, 10, 1),
    );
    await provider.addPendingBill(bill);

    final coll = CollectionModel(
      id: 'test_col_001',
      shopId: shop.id,
      shopName: shop.name,
      routeId: route.id,
      routeName: route.name,
      businessName: 'Purva Enterprises',
      billNumber: 'INV-101',
      billAmount: 5000.0,
      collectedAmount: 2000.0,
      paymentMode: PaymentMode.cash,
      salesmanName: 'Akash',
      collectedAt: DateTime(2026, 10, 1),
      billDate: DateTime(2026, 10, 1),
    );
    await provider.addCollection(coll);

    expect(provider.getShopById(shop.id)?.name, 'Original Store Name');
    expect(provider.collections.firstWhere((c) => c.id == coll.id).shopName, 'Original Store Name');
    expect(provider.pendingBills.firstWhere((b) => b.id == bill.id).shopName, 'Original Store Name');

    // Rename outlet
    final updatedShop = shop.copyWith(name: 'Updated Shree Ram Supermarket');
    await provider.updateShop(updatedShop);

    // Verify all instances reflect the new name immediately
    expect(provider.getShopById(shop.id)?.name, 'Updated Shree Ram Supermarket');
    expect(provider.collections.firstWhere((c) => c.id == coll.id).shopName, 'Updated Shree Ram Supermarket');
    expect(provider.pendingBills.firstWhere((b) => b.id == bill.id).shopName, 'Updated Shree Ram Supermarket');
  });

  test('Shop deletion tracks deleted ID and removes shop from provider list', () async {
    final provider = CollectionProvider();
    await Future.delayed(const Duration(milliseconds: 100));

    final route = await provider.addRoute(name: 'Bhosari Route', description: 'Bhosari');
    final shop = await provider.addShop(
      name: 'Temp Shop To Delete',
      routeId: route.id,
      routeName: route.name,
      mobileNumber: '9123456780',
      address: 'MIDC',
    );

    expect(provider.getShopById(shop.id), isNotNull);
    await provider.deleteShop(shop.id);
    expect(provider.getShopById(shop.id), isNull);
  });
}
