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
      // Small & Concise message requested by user
      if (widget.billNumber != null && widget.billNumber!.isNotEmpty) {
        return 'Dear ${widget.shopName},\n'
            'Payment reminder: Bill ${widget.billNumber} has a pending balance of $balanceStr with ${widget.businessName}. Kindly arrange payment.\n'
            '- ${widget.salesmanName}';
      } else {
        return 'Dear ${widget.shopName},\n'
            'Payment reminder: Outstanding balance of $balanceStr is pending with ${widget.businessName}. Kindly clear at your earliest convenience.\n'
            '- ${widget.salesmanName}';
      }
    } else {
      // Detailed Bill Template
      final billTotalStr = widget.billTotal != null ? CurrencyFormatter.format(widget.billTotal!) : '';
      final billLine = widget.billNumber != null ? 'Bill No: ${widget.billNumber}\n' : '';
      final totalLine = billTotalStr.isNotEmpty ? 'Bill Total: $billTotalStr\n' : '';

      return 'Payment Reminder\n'
          'To: ${widget.shopName}\n'
          'From: ${widget.businessName}\n'
          '----------------------------------\n'
          '$billLine$totalLine'
          'Balance Due: $balanceStr\n'
          '----------------------------------\n'
          'Kindly clear the pending balance at your earliest convenience.\n'
          'Thank you,\n'
          '${widget.salesmanName} | ${widget.businessName}';
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
        _copyAndNotify('Could not launch WhatsApp directly. Message copied to clipboard!');
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
          content: Text(customMessage),
          backgroundColor: AppTheme.secondary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.chequeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.notifications_active_outlined, color: AppTheme.chequeColor, size: 18),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Payment Reminder',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Recipient & Outstanding summary box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.shopName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Mobile: ${widget.mobileNumber.isNotEmpty ? widget.mobileNumber : 'N/A'}',
                            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Balance Due',
                            style: TextStyle(fontSize: 11, color: Colors.blueGrey),
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

                // Template Style Selector
                Row(
                  children: [
                    const Text(
                      'Message Format:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Short Message'),
                      selected: _selectedTemplate == 0,
                      selectedColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: _selectedTemplate == 0 ? FontWeight.bold : FontWeight.normal,
                        color: _selectedTemplate == 0 ? Colors.white : Colors.black87,
                      ),
                      onSelected: (val) {
                        if (val) _onTemplateChanged(0);
                      },
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('Detailed Bill'),
                      selected: _selectedTemplate == 1,
                      selectedColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: _selectedTemplate == 1 ? FontWeight.bold : FontWeight.normal,
                        color: _selectedTemplate == 1 ? Colors.white : Colors.black87,
                      ),
                      onSelected: (val) {
                        if (val) _onTemplateChanged(1);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Editable Message Box
                TextField(
                  controller: _messageController,
                  maxLines: 5,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                  decoration: InputDecoration(
                    labelText: 'Message Content (Editable)',
                    alignLabelWithHint: true,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),

                // Direct Send Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.chat_outlined, size: 16),
                        label: const Text('WhatsApp'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366), // WhatsApp Green
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _launchWhatsApp,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.sms_outlined, size: 16),
                        label: const Text('SMS'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _launchSms,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: const Text('Copy'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        side: const BorderSide(color: AppTheme.border),
                      ),
                      onPressed: () {
                        _copyAndNotify('Reminder message copied to clipboard!');
                      },
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
