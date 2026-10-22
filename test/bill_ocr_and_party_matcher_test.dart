import 'package:flutter_test/flutter_test.dart';
import 'package:daily_collection_app/models/shop_model.dart';
import 'package:daily_collection_app/services/bill_text_parser.dart';
import 'package:daily_collection_app/services/party_name_matcher.dart';

void main() {
  group('BillTextParser Unit Tests', () {
    test('extracts invoice number, date, amount, and customer name', () {
      const sampleBillText = '''
PURVA ENTERPRISES
TAX INVOICE
Invoice No: PE-2024-0891
Date: 15/10/2026
M/S: SHREE GANESH TRADERS
Near Station Road, Pune
Item 1: 500.00
Item 2: 750.50
Total Bill Amount: ₹1,250.50
Authorized Signatory
''';

      final parsed = BillTextParser.parse(sampleBillText);

      expect(parsed.billNumber, equals('PE-2024-0891'));
      expect(parsed.billDate, isNotNull);
      expect(parsed.billDate!.day, equals(15));
      expect(parsed.billDate!.month, equals(10));
      expect(parsed.billDate!.year, equals(2026));
      expect(parsed.amount, equals(1250.50));
      expect(parsed.partyName, contains('SHREE GANESH TRADERS'));
    });

    test('extracts bill amount with Net Payable and Inv No', () {
      const sampleText = '''
MAHALAXMI SALES
INV NO: MS/8421
Dated: 2026-10-12
Billed To: MAHALAXMI KIRANA STORES
Subtotal: 3500.00
Tax: 630.00
Net Payable: 4,130.00
Thank you for your business!
''';

      final parsed = BillTextParser.parse(sampleText);
      expect(parsed.billNumber, equals('MS/8421'));
      expect(parsed.amount, equals(4130.0));
      expect(parsed.partyName, contains('MAHALAXMI KIRANA'));
    });

    test('extracts date with text month format e.g. 19-Oct-2026', () {
      const sampleText = '''
PURVA ENTERPRISES
Bill No: 90214
Date: 19-Oct-2026
Customer: OM SAI TRADERS
Total: 7,850.00
''';
      final parsed = BillTextParser.parse(sampleText);
      expect(parsed.billNumber, equals('90214'));
      expect(parsed.billDate, isNotNull);
      expect(parsed.billDate!.day, equals(19));
      expect(parsed.billDate!.month, equals(10));
      expect(parsed.billDate!.year, equals(2026));
      expect(parsed.amount, equals(7850.0));
    });

    test('extracts multi-line layout where label and value are on separate lines', () {
      const sampleText = '''
PURVA ENTERPRISES
TAX INVOICE
Invoice No:
PE-2024-5082
Date:
22/10/2026
Billed To:
SHREE GANESH TRADERS
Near Market
Item 1 ................... 400.00
Item 2 ................... 600.00
Grand Total
1,000.00
''';
      final parsed = BillTextParser.parse(sampleText);
      expect(parsed.billNumber, equals('PE-2024-5082'));
      expect(parsed.billDate, isNotNull);
      expect(parsed.billDate!.day, equals(22));
      expect(parsed.billDate!.month, equals(10));
      expect(parsed.billDate!.year, equals(2026));
      expect(parsed.amount, equals(1000.0));
      expect(parsed.partyName, equals('SHREE GANESH TRADERS'));
    });

    test('recovers from OCR noise like letter O in dates (e.g. 18/1O/2026)', () {
      const sampleText = '''
PURVA ENTERPRISES
Invoice No: PE-402
Date: 18/1O/2026
M/S SAI SUPER MARKET
Total: 500
''';
      final parsed = BillTextParser.parse(sampleText);
      expect(parsed.billDate, isNotNull);
      expect(parsed.billDate!.day, equals(18));
      expect(parsed.billDate!.month, equals(10));
      expect(parsed.billDate!.year, equals(2026));
    });

    test('spatial multi-slice parsing with headerText and footerText', () {
      const header = '''
PURVA ENTERPRISES
Invoice No: PE-9912
Date: 14/10/2026
Customer: MAHALAXMI KIRANA STORES
''';

      const footer = '''
Subtotal: 8000.00
CGST 2.5%: 200.00
SGST 2.5%: 200.00
Round Off: -0.00
Grand Total: ₹ 8,400.00
''';

      const full = '$header\nItem 1 4000\nItem 2 4000\n$footer';

      final parsed = BillTextParser.parse(
        full,
        headerText: header,
        footerText: footer,
      );

      expect(parsed.billNumber, equals('PE-9912'));
      expect(parsed.billDate!.day, equals(14));
      expect(parsed.amount, equals(8400.0));
      expect(parsed.partyName, contains('MAHALAXMI KIRANA'));
    });
  });

  group('PartyNameMatcher English-to-Marathi Tests', () {
    final candidateShops = [
      ShopModel(
        id: 'shop_1',
        name: 'श्री गणेश ट्रेडर्स', // Shree Ganesh Traders
        routeId: 'route_1',
        routeName: 'Route 1',
        mobileNumber: '9876543210',
        address: 'Main Market',
      ),
      ShopModel(
        id: 'shop_2',
        name: 'महालक्ष्मी किराणा स्टोअर्स', // Mahalaxmi Kirana Stores
        routeId: 'route_1',
        routeName: 'Route 1',
        mobileNumber: '9876543211',
        address: 'Station Road',
      ),
      ShopModel(
        id: 'shop_3',
        name: 'साई सुपर मार्केट', // Sai Super Market
        routeId: 'route_1',
        routeName: 'Route 1',
        mobileNumber: '9876543212',
        address: 'Bypass Road',
      ),
    ];

    test('matches English "SHREE GANESH TRADERS" to Marathi "श्री गणेश ट्रेडर्स"', () {
      final match = PartyNameMatcher.findBestMatch(
        rawExtractedName: 'M/S SHREE GANESH TRADERS',
        candidateShops: candidateShops,
      );

      expect(match, isNotNull);
      expect(match!.shop.id, equals('shop_1'));
      expect(match.shop.name, equals('श्री गणेश ट्रेडर्स'));
      expect(match.score, greaterThan(0.5));
    });

    test('matches English "MAHALAXMI KIRANA STORE" to Marathi "महालक्ष्मी किराणा स्टोअर्स"', () {
      final match = PartyNameMatcher.findBestMatch(
        rawExtractedName: 'MAHALAXMI KIRANA STORE',
        candidateShops: candidateShops,
      );

      expect(match, isNotNull);
      expect(match!.shop.id, equals('shop_2'));
      expect(match.shop.name, equals('महालक्ष्मी किराणा स्टोअर्स'));
      expect(match.score, greaterThan(0.4));
    });

    test('matches "SAI SUPER MARKET" to "साई सुपर मार्केट"', () {
      final match = PartyNameMatcher.findBestMatch(
        rawExtractedName: 'TO: SAI SUPER MARKET',
        candidateShops: candidateShops,
      );

      expect(match, isNotNull);
      expect(match!.shop.id, equals('shop_3'));
      expect(match.shop.name, equals('साई सुपर मार्केट'));
    });

    test('returns null when candidates list is empty', () {
      final match = PartyNameMatcher.findBestMatch(
        rawExtractedName: 'SHREE GANESH TRADERS',
        candidateShops: [],
      );

      expect(match, isNull);
    });
  });
}
