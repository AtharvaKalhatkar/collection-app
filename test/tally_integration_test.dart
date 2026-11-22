import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart' as xml;
import 'package:daily_collection_app/models/collection_model.dart';
import 'package:daily_collection_app/models/order_model.dart';
import 'package:daily_collection_app/models/route_model.dart';
import 'package:daily_collection_app/models/shop_model.dart';
import 'package:daily_collection_app/services/tally_integration_service.dart';

void main() {
  group('TallyIntegrationService Tests', () {
    test('generateReceiptsXml generates valid Tally XML with debit and credit ledgers', () {
      final collections = [
        CollectionModel(
          id: 'col_123',
          businessName: 'Purva Enterprises',
          shopId: 's1',
          shopName: 'G R Mart',
          routeId: 'r1',
          routeName: 'Kharabwadi Mahalunge',
          billNumber: 'INV-550',
          billAmount: 3000.0,
          collectedAmount: 2500.0,
          paymentMode: PaymentMode.cash,
          salesmanName: 'Akash',
          collectedAt: DateTime(2026, 11, 22, 10, 30),
        ),
      ];

      final xmlString = TallyIntegrationService.generateReceiptsXml(
        collections: collections,
        companyName: 'Purva Enterprises',
      );

      // Verify valid XML structure
      final doc = xml.XmlDocument.parse(xmlString);
      expect(doc.findAllElements('ENVELOPE').length, 1);
      expect(doc.findAllElements('TALLYREQUEST').first.innerText, 'Import Data');

      final voucher = doc.findAllElements('VOUCHER').first;
      expect(voucher.getAttribute('VCHTYPE'), 'Receipt');
      expect(voucher.findElements('DATE').first.innerText, '20261122');
      expect(voucher.findElements('PARTYLEDGERNAME').first.innerText, 'G R Mart');

      // Verify Ledger entries: Party (Credit, 2500.00) & Cash (Debit, -2500.00)
      final ledgerEntries = voucher.findElements('ALLLEDGERENTRIES.LIST').toList();
      expect(ledgerEntries.length, 2);

      final partyEntry = ledgerEntries.first;
      expect(partyEntry.findElements('LEDGERNAME').first.innerText, 'G R Mart');
      expect(partyEntry.findElements('AMOUNT').first.innerText, '2500.00');
      expect(partyEntry.findElements('ISDEEMEDPOSITIVE').first.innerText, 'No');

      final billAllocation = partyEntry.findElements('BILLALLOCATIONS.LIST').first;
      expect(billAllocation.findElements('NAME').first.innerText, 'INV-550');
      expect(billAllocation.findElements('BILLTYPE').first.innerText, 'Agst Ref');
      expect(billAllocation.findElements('AMOUNT').first.innerText, '2500.00');

      final cashEntry = ledgerEntries.last;
      expect(cashEntry.findElements('LEDGERNAME').first.innerText, 'Cash');
      expect(cashEntry.findElements('AMOUNT').first.innerText, '-2500.00');
      expect(cashEntry.findElements('ISDEEMEDPOSITIVE').first.innerText, 'Yes');
    });

    test('generateSalesOrdersXml generates valid Tally Sales Order XML with stock items', () {
      final orders = <SalesOrderModel>[
        SalesOrderModel(
          id: 'ord-101',
          orderNumber: 'SO-101',
          shopId: 's1',
          shopName: 'G R Mart',
          shopMobile: '9876543210',
          routeId: 'r1',
          routeName: 'Kharabwadi Mahalunge',
          salesmanName: 'Akash',
          firm: 'Purva Enterprises',
          orderDate: DateTime(2026, 11, 22),
          totalAmount: 337.5,
          totalQuantity: 54,
          items: [
            OrderItem(
              productId: 'p1',
              productName: 'Good Day Butter',
              category: 'Biscuits',
              subcategory: 'Britannia',
              company: 'Britannia',
              packing: '24 Pcs',
              quantity: 54,
              cases: 2,
              units: 6,
              unitsPerCase: 24,
              rate: 150.0,
              weightKg: 2.5,
            ),
          ],
        ),
      ];

      final xmlString = TallyIntegrationService.generateSalesOrdersXml(
        orders: orders,
        companyName: 'Purva Enterprises',
      );

      final doc = xml.XmlDocument.parse(xmlString);
      final voucher = doc.findAllElements('VOUCHER').first;
      expect(voucher.getAttribute('VCHTYPE'), 'Sales Order');
      expect(voucher.findElements('VOUCHERNUMBER').first.innerText, 'SO-101');
      expect(voucher.findElements('PARTYLEDGERNAME').first.innerText, 'G R Mart');

      final inventory = voucher.findElements('ALLINVENTORYENTRIES.LIST').first;
      expect(inventory.findElements('STOCKITEMNAME').first.innerText, 'Good Day Butter');
      expect(inventory.findElements('RATE').first.innerText, '150.00/Cs');
    });

    test('generateOutletsLedgerXml generates standard Sundry Debtors masters', () {
      final shops = [
        ShopModel(
          id: 's1',
          name: 'G R Mart',
          routeId: 'r1',
          routeName: 'Kharabwadi Mahalunge',
          mobileNumber: '9876543210',
          address: 'Near Bus Stop',
        ),
      ];

      final xmlString = TallyIntegrationService.generateOutletsLedgerXml(shops: shops);
      final doc = xml.XmlDocument.parse(xmlString);
      final ledger = doc.findAllElements('LEDGER').first;

      expect(ledger.getAttribute('NAME'), 'G R Mart');
      expect(ledger.findElements('PARENT').first.innerText, 'Sundry Debtors');
      expect(ledger.findElements('LEDGERPHONE').first.innerText, '9876543210');
      expect(ledger.findElements('STATENAME').first.innerText, 'Maharashtra');
    });

    test('parsePendingBillsFromTallyXml parses Tally XML vouchers into PendingBillModel', () {
      const tallySalesXml = '''<?xml version="1.0" encoding="utf-8"?>
<ENVELOPE>
  <HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER>
  <BODY>
    <DATA>
      <TALLYMESSAGE xmlns:UDF="TallyUDF">
        <VOUCHER VCHTYPE="Sales" ACTION="Create">
          <DATE>20261122</DATE>
          <VOUCHERNUMBER>INV-9901</VOUCHERNUMBER>
          <PARTYLEDGERNAME>Mahalaxmi Stores</PARTYLEDGERNAME>
          <ALLLEDGERENTRIES.LIST>
            <LEDGERNAME>Mahalaxmi Stores</LEDGERNAME>
            <AMOUNT>-3400.00</AMOUNT>
          </ALLLEDGERENTRIES.LIST>
        </VOUCHER>
      </TALLYMESSAGE>
    </DATA>
  </BODY>
</ENVELOPE>''';

      final routes = [RouteModel(id: 'r_main', name: 'Main Road')];
      final shops = <ShopModel>[];

      final result = TallyIntegrationService.parsePendingBillsFromTallyXml(
        xmlContent: tallySalesXml,
        existingRoutes: routes,
        existingShops: shops,
        defaultFirm: 'Purva Enterprises',
      );

      expect(result.success, true);
      expect(result.importedBills.length, 1);
      expect(result.importedBills.first.billNumber, 'INV-9901');
      expect(result.importedBills.first.shopName, 'Mahalaxmi Stores');
      expect(result.importedBills.first.totalAmount, 3400.0);
      expect(result.newShops.length, 1);
      expect(result.newShops.first.name, 'Mahalaxmi Stores');
    });
  });
}
