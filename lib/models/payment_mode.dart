import 'package:flutter/material.dart';

enum PaymentMode {
  cash('Cash', Icons.payments_outlined),
  upi('UPI', Icons.qr_code_2_rounded),
  cheque('Cheque', Icons.fact_check_outlined),
  netBanking('NEFT', Icons.account_balance_outlined);

  final String label;
  final IconData icon;
  const PaymentMode(this.label, this.icon);

  String get displayName => label;

  static PaymentMode fromString(String val) {
    final v = val.toLowerCase().trim();
    if (v.contains('cash')) return PaymentMode.cash;
    if (v.contains('upi')) return PaymentMode.upi;
    if (v.contains('cheque') || v.contains('check')) return PaymentMode.cheque;
    if (v.contains('net') || v.contains('bank') || v.contains('neft') || v.contains('rtgs') || v.contains('imps')) return PaymentMode.netBanking;
    return PaymentMode.values.firstWhere(
      (m) => m.name.toLowerCase() == v || m.label.toLowerCase() == v,
      orElse: () => PaymentMode.cash,
    );
  }
}
