import 'package:flutter_test/flutter_test.dart';
import 'package:daily_collection_app/services/order_catalog_service.dart';
import 'package:daily_collection_app/models/order_model.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Order Catalog Structure Verification', () {
    test('Purva Enterprises companies match specifications', () {
      final purvaCompanies = OrderCatalogService.getCompanies('Purva Enterprises');
      expect(purvaCompanies, containsAll(['Wipro', 'Fena', 'Funfood', 'Imami']));
      expect(purvaCompanies.length, equals(4));
    });

    test('Manas Sales companies match specifications', () {
      final manasCompanies = OrderCatalogService.getCompanies('Manas Sales');
      expect(manasCompanies, containsAll(['Racket', 'Imami', 'Dabar', 'Cadbury', 'Gowardhan']));
      expect(manasCompanies.length, equals(5));
    });

    test('Wipro under Purva contains Soap category and Handwash products', () {
      final categories = OrderCatalogService.getCategories('Purva Enterprises', 'Wipro');
      expect(categories, contains('Soap'));

      final soapProducts = OrderCatalogService.getProducts(
        firm: 'Purva Enterprises',
        company: 'Wipro',
        category: 'Soap',
      );

      final hasHandwash = soapProducts.any((p) => p.name.toLowerCase().contains('handwash'));
      expect(hasHandwash, isTrue);
      expect(soapProducts.length, greaterThanOrEqualTo(2));
    });

    test('Racket under Manas contains Soap & Cleaners and Handwash products', () {
      final racketProducts = OrderCatalogService.getProducts(
        firm: 'Manas Sales',
        company: 'Racket',
      );
      final hasHandwash = racketProducts.any((p) => p.name.toLowerCase().contains('handwash'));
      expect(hasHandwash, isTrue);
    });
  });

  group('Sales Order Model & Calculation', () {
    test('OrderItem correctly computes subtotal and updates quantity', () {
      final item = OrderItem(
        productId: 'wip-soap-1',
        productName: 'Handwash (Santoor Pump)',
        company: 'Wipro',
        category: 'Soap',
        packing: '250ml Pump',
        rate: 75.0,
        quantity: 6,
      );

      expect(item.subtotal, equals(450.0));

      final updated = item.copyWith(quantity: 12);
      expect(updated.quantity, equals(12));
      expect(updated.subtotal, equals(900.0));
    });

    test('SalesOrderModel serializes and deserializes correctly', () {
      final order = SalesOrderModel(
        id: 'ord-test-1',
        orderNumber: 'ORD-261001-1001',
        firm: 'Purva Enterprises',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        shopId: 'shop-ata-kirana',
        shopName: 'ATA Kirana',
        shopMobile: '9822012345',
        salesmanName: 'Akash',
        orderDate: DateTime(2026, 10, 1, 10, 0),
        items: [
          OrderItem(
            productId: 'wip-soap-1',
            productName: 'Handwash (Santoor Pump)',
            company: 'Wipro',
            category: 'Soap',
            packing: '250ml Pump',
            rate: 75.0,
            quantity: 4,
          ),
        ],
        totalAmount: 300.0,
        totalQuantity: 4,
        notes: 'Deliver early morning',
      );

      final json = order.toJson();
      final fromJson = SalesOrderModel.fromJson(json);

      expect(fromJson.id, equals('ord-test-1'));
      expect(fromJson.orderNumber, equals('ORD-261001-1001'));
      expect(fromJson.firm, equals('Purva Enterprises'));
      expect(fromJson.items.length, equals(1));
      expect(fromJson.totalAmount, equals(300.0));
      expect(fromJson.notes, equals('Deliver early morning'));
    });
  });
}
