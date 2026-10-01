import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';

class SendReminderDialog extends StatefulWidget {
  final String shopName;
  final String mobileNumber;
  final String businessName;
  final String salesmanName;
  final double balanceAmount;
  final String? billNumber;
  final double? billTotal;

  const SendReminderDialog({
    super.key,
    required this.shopName,
    required this.mobileNumber,
    required this.businessName,
    required this.salesmanName,
    required this.balanceAmount,
    this.billNumber,
    this.billTotal,
  });

  @override
  State<SendReminderDialog> createState() => _SendReminderDialogState();
}

class _SendReminderDialogState extends State<SendReminderDialog> {
  late TextEditingController _messageController;
  int _selectedTemplate = 0; // 0: Short message, 1: Bill details

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(text: _generateMessage(0));
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  String _generateMessage(int templateIndex) {
    final balanceStr = CurrencyFormatter.format(widget.balanceAmount);

    if (templateIndex == 0) {
      if (widget.billNumber != null && widget.billNumber!.isNotEmpty) {
        return 'Dear ${widget.shopName},\n'
            'Payment reminder: Bill #${widget.billNumber} has a pending balance of $balanceStr with ${widget.businessName}. Kindly arrange payment.\n'
            '- ${widget.salesmanName}';
      } else {
        return 'Dear ${widget.shopName},\n'
            'Payment reminder: Outstanding balance of $balanceStr is pending with ${widget.businessName}. Kindly arrange payment.\n'
            '- ${widget.salesmanName}';
      }
    } else {
      final billTotalStr = widget.billTotal != null ? CurrencyFormatter.format(widget.billTotal!) : '';
      final billLine = widget.billNumber != null ? 'Bill No: #${widget.billNumber}\n' : '';
      final totalLine = billTotalStr.isNotEmpty ? 'Total: $billTotalStr\n' : '';

      return 'Payment Reminder\n'
          'To: ${widget.shopName}\n'
          'Firm: ${widget.businessName}\n'
          '----------------------------------\n'
          '$billLine$totalLine'
          'Due: $balanceStr\n'
          '----------------------------------\n'
          'Kindly clear the pending balance.\n'
          'Thank you,\n'
          '${widget.salesmanName} (${widget.businessName})';
    }
  }

  void _onTemplateChanged(int index) {
    setState(() {
      _selectedTemplate = index;
      _messageController.text = _generateMessage(index);
    });
  }

  Future<void> _launchWhatsApp() async {
    final cleanPhone = widget.mobileNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final formattedPhone = cleanPhone.length == 10 ? '91$cleanPhone' : cleanPhone;
    final text = _messageController.text.trim();

    final whatsappUrl = Uri.parse(
      'https://api.whatsapp.com/send?phone=$formattedPhone&text=${Uri.encodeComponent(text)}',
    );

    try {
      final launched = await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _copyAndNotify('Could not launch WhatsApp. Message copied to clipboard!');
      }
    } catch (_) {
      if (mounted) {
        _copyAndNotify('Message copied to clipboard! You can paste it into WhatsApp.');
      }
    }
  }

  Future<void> _launchSms() async {
    final cleanPhone = widget.mobileNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final text = _messageController.text.trim();
    final smsUri = Uri(
      scheme: 'sms',
      path: cleanPhone,
      queryParameters: {'body': text},
    );

    try {
      final launched = await launchUrl(smsUri);
      if (!launched && mounted) {
        _copyAndNotify('Could not open SMS app. Message copied to clipboard!');
      }
    } catch (_) {
      if (mounted) {
        _copyAndNotify('Message copied to clipboard! You can paste it into Messages.');
      }
    }
  }

  void _copyAndNotify(String customMessage) {
    Clipboard.setData(ClipboardData(text: _messageController.text.trim()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(customMessage)),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.notifications_active_outlined,
                        color: Color(0xFFD97706),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Payment Reminder',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Shop & Outstanding Balance Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.shopName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Mobile: ${widget.mobileNumber.isNotEmpty ? widget.mobileNumber : 'N/A'}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.blueGrey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Balance Due',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.blueGrey,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            CurrencyFormatter.format(widget.balanceAmount),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.balanceDueColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Full-width Segmented Format Switcher
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _onTemplateChanged(0),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: _selectedTemplate == 0 ? AppTheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                'Short Message',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTemplate == 0 ? Colors.white : Colors.blueGrey.shade800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => _onTemplateChanged(1),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: _selectedTemplate == 1 ? AppTheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                'Detailed Bill',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTemplate == 1 ? Colors.white : Colors.blueGrey.shade800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Editable Message Box
                TextField(
                  controller: _messageController,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: 'Message (Editable)',
                    labelStyle: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                    alignLabelWithHint: true,
                    contentPadding: const EdgeInsets.all(12),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Primary WhatsApp Action Button (Full Width, No Wrap!)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text(
                      'Send on WhatsApp',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366), // WhatsApp Green
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 1,
                    ),
                    onPressed: _launchWhatsApp,
                  ),
                ),
                const SizedBox(height: 8),

                // Secondary Row: SMS & Copy
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.sms_outlined, size: 15),
                        label: const Text(
                          'Send SMS',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.secondary,
                          side: const BorderSide(color: AppTheme.secondary),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _launchSms,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy_outlined, size: 15),
                        label: const Text(
                          'Copy Text',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blueGrey.shade700,
                          side: const BorderSide(color: AppTheme.border),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _copyAndNotify('Reminder copied!'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
