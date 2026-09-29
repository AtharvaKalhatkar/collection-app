import 'package:flutter/material.dart';

enum PaymentMode {
  cash('Cash', Icons.payments_outlined),
  upi('UPI / QR', Icons.qr_code_2_rounded),
  cheque('Cheque', Icons.fact_check_outlined),
  netBanking('Net Banking', Icons.account_balance_outlined);

  final String label;
  final IconData icon;
  const PaymentMode(this.label, this.icon);

  static PaymentMode fromString(String val) {
    return PaymentMode.values.firstWhere(
      (m) => m.name.toLowerCase() == val.toLowerCase() || m.label.toLowerCase() == val.toLowerCase(),
      orElse: () => PaymentMode.cash,
    );
  }
}
