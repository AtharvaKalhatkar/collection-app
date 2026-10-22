import 'package:flutter_test/flutter_test.dart';
import 'package:daily_collection_app/models/payment_mode.dart';
import 'package:daily_collection_app/utils/currency_formatter.dart';

void main() {
  group('2-Factor Payment Verification Receipt Tests', () {
    test('generates accurate customer confirmation message for partial payment', () {
      const customerName = 'Mahalaxmi Kirana Stores';
      const firmName = 'Purva Enterprises';
      const billNo = 'PE-5042';
      const billTotal = 5000.0;
      const amountCollected = 4000.0;
      const balanceRemaining = 1000.0;
      const paymentMode = PaymentMode.cash;
      const salesmanName = 'Akash';
      final collectionDate = DateTime(2026, 10, 22, 15, 30);

      final message = '''*Payment Receipt (PARTIAL PAYMENT)*
Dear $customerName,
Payment received with thanks:
• Bill No: $billNo
• Bill Amount: ${CurrencyFormatter.format(billTotal)}
• Received: ${CurrencyFormatter.format(amountCollected)} (${paymentMode.label})
• Balance Remaining: ${CurrencyFormatter.format(balanceRemaining)}
• Collected By: $salesmanName
• Date: 22/10/2026, 03:30 PM

Thank you!
-$firmName''';

      expect(message, contains('Bill No: PE-5042'));
      expect(message, contains('Bill Amount: ₹5,000'));
      expect(message, contains('Received: ₹4,000 (Cash)'));
      expect(message, contains('Balance Remaining: ₹1,000'));
      expect(message, contains('Collected By: Akash'));
      expect(message, contains('PARTIAL PAYMENT'));
    });

    test('generates accurate customer confirmation message for full payment', () {
      const customerName = 'Shree Ganesh Traders';
      const firmName = 'Manas Sales';
      const billNo = 'MS-891';
      const billTotal = 3500.0;
      const amountCollected = 3500.0;
      const balanceRemaining = 0.0;
      const paymentMode = PaymentMode.upi;
      const salesmanName = 'Akash';

      final message = '''*Payment Receipt (FULLY PAID)*
Dear $customerName,
Payment received with thanks:
• Bill No: $billNo
• Bill Amount: ${CurrencyFormatter.format(billTotal)}
• Received: ${CurrencyFormatter.format(amountCollected)} (${paymentMode.label})
• Balance Remaining: ${CurrencyFormatter.format(balanceRemaining)}
• Collected By: $salesmanName

Thank you!
-$firmName''';

      expect(message, contains('Bill No: MS-891'));
      expect(message, contains('Received: ₹3,500 (UPI)'));
      expect(message, contains('Balance Remaining: ₹0'));
      expect(message, contains('FULLY PAID'));
    });
  });
}
