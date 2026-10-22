import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/payment_mode.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';

class PaymentReceiptDialog extends StatefulWidget {
  final String customerName;
  final String customerMobile;
  final String firmName;
  final String billNo;
  final double billTotal;
  final double amountCollected;
  final double balanceRemaining;
  final PaymentMode paymentMode;
  final String salesmanName;
  final DateTime collectionDate;

  const PaymentReceiptDialog({
    super.key,
    required this.customerName,
    required this.customerMobile,
    required this.firmName,
    required this.billNo,
    required this.billTotal,
    required this.amountCollected,
    required this.balanceRemaining,
    required this.paymentMode,
    required this.salesmanName,
    required this.collectionDate,
  });

  static Future<void> show(
    BuildContext context, {
    required String customerName,
    required String customerMobile,
    required String firmName,
    required String billNo,
    required double billTotal,
    required double amountCollected,
    required double balanceRemaining,
    required PaymentMode paymentMode,
    required String salesmanName,
    required DateTime collectionDate,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentReceiptDialog(
        customerName: customerName,
        customerMobile: customerMobile,
        firmName: firmName,
        billNo: billNo,
        billTotal: billTotal,
        amountCollected: amountCollected,
        balanceRemaining: balanceRemaining,
        paymentMode: paymentMode,
        salesmanName: salesmanName,
        collectionDate: collectionDate,
      ),
    );
  }

  @override
  State<PaymentReceiptDialog> createState() => _PaymentReceiptDialogState();
}

class _PaymentReceiptDialogState extends State<PaymentReceiptDialog> {
  late TextEditingController _messageController;
  bool _isCopied = false;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(text: _generateReceiptText());
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  String _generateReceiptText() {
    final dateStr = DateFormat('dd/MM/yyyy, hh:mm a').format(widget.collectionDate);
    final isSettled = widget.balanceRemaining <= 0.01;
    final statusHeader = isSettled ? 'FULLY PAID' : 'PARTIAL PAYMENT';

    return '''*Payment Receipt ($statusHeader)*
Dear ${widget.customerName},
Payment received with thanks:
• Bill No: ${widget.billNo}
• Bill Amount: ${CurrencyFormatter.format(widget.billTotal)}
• Received: ${CurrencyFormatter.format(widget.amountCollected)} (${widget.paymentMode.label})
• Balance Remaining: ${CurrencyFormatter.format(widget.balanceRemaining <= 0 ? 0 : widget.balanceRemaining)}
• Collected By: ${widget.salesmanName}
• Date: $dateStr

Thank you!
-${widget.firmName}''';
  }

  Future<void> _sendWhatsApp() async {
    final cleanPhone = widget.customerMobile.replaceAll(RegExp(r'[^0-9]'), '');
    final formattedPhone = cleanPhone.length == 10 ? '91$cleanPhone' : cleanPhone;
    final text = Uri.encodeComponent(_messageController.text.trim());

    final webUrl = Uri.parse('https://api.whatsapp.com/send?phone=$formattedPhone&text=$text');
    final appUrl = Uri.parse('whatsapp://send?phone=$formattedPhone&text=$text');

    try {
      if (await canLaunchUrl(appUrl)) {
        await launchUrl(appUrl, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    try {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    } catch (_) {
      _copyMessage('Could not open WhatsApp. Message copied to clipboard!');
    }
  }

  Future<void> _sendSms() async {
    final cleanPhone = widget.customerMobile.replaceAll(RegExp(r'[^0-9]'), '');
    final text = _messageController.text.trim();
    final smsUri = Uri(
      scheme: 'sms',
      path: cleanPhone,
      queryParameters: {'body': text},
    );

    try {
      await launchUrl(smsUri);
    } catch (_) {
      _copyMessage('Could not open SMS. Message copied to clipboard!');
    }
  }

  void _copyMessage([String? feedback]) {
    Clipboard.setData(ClipboardData(text: _messageController.text.trim()));
    setState(() => _isCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(feedback ?? 'Receipt copied to clipboard!'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF0F172A),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFullyPaid = widget.balanceRemaining <= 0.01;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top grab handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, color: Color(0xFF059669), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Payment Recorded Successfully',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Send 2-way receipt confirmation to customer',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Payment Summary Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          widget.customerName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isFullyPaid ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isFullyPaid ? 'FULLY PAID' : 'PARTIAL',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isFullyPaid ? const Color(0xFF15803D) : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.customerMobile.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Phone: ${widget.customerMobile}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSummaryItem('Bill No', widget.billNo),
                      _buildSummaryItem('Bill Total', CurrencyFormatter.format(widget.billTotal)),
                      _buildSummaryItem('Received', CurrencyFormatter.format(widget.amountCollected), highlight: true),
                      _buildSummaryItem('Balance', CurrencyFormatter.format(widget.balanceRemaining <= 0 ? 0 : widget.balanceRemaining)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Message Preview Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Customer Confirmation Message',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700),
                      ),
                      InkWell(
                        onTap: () => _copyMessage(),
                        child: Row(
                          children: [
                            Icon(_isCopied ? Icons.check : Icons.copy, size: 13, color: AppTheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              _isCopied ? 'Copied' : 'Copy',
                              style: const TextStyle(fontSize: 11.5, color: AppTheme.primary, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _messageController,
                    maxLines: 6,
                    style: const TextStyle(fontSize: 12, height: 1.35, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Primary Send Actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text(
                      'WhatsApp Customer',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _sendWhatsApp,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.sms_outlined, size: 16),
                    label: const Text(
                      'SMS Customer',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _sendSms,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Done Button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done / Skip', style: TextStyle(color: Colors.blueGrey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, {bool highlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: highlight ? const Color(0xFF059669) : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}
