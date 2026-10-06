import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';

class FirmBankInfo {
  final String firmName;
  final String shortName;
  final String bankName;
  final String branch;
  final String accountNumber;
  final String accountType;
  final String ifscCode;
  final String upiId;
  final String mobileNumber;
  final List<String> companies;
  final Color primaryColor;
  final Color lightColor;

  const FirmBankInfo({
    required this.firmName,
    required this.shortName,
    required this.bankName,
    required this.branch,
    required this.accountNumber,
    required this.accountType,
    required this.ifscCode,
    required this.upiId,
    required this.mobileNumber,
    required this.companies,
    required this.primaryColor,
    required this.lightColor,
  });

  String get formattedShareText {
    return '''
PAYMENT DETAILS
$firmName
Bank: $bankName
Branch: $branch
A/c No: $accountNumber
A/c Type: $accountType
IFSC Code: $ifscCode
'''.trim();
  }
}

class FirmDetailsHelper {
  static const purva = FirmBankInfo(
    firmName: 'PURVA ENTERPRISES',
    shortName: 'Purva',
    bankName: 'Union Bank of India',
    branch: 'Chakan',
    accountNumber: '115925080000004',
    accountType: 'C C',
    ifscCode: 'UBIN0570575',
    upiId: '8459671694@okbizaxis',
    mobileNumber: '+91 84596 71694',
    companies: ['Wipro', 'Fena', 'Funfood', 'Imami'],
    primaryColor: AppTheme.purvaPrimary,
    lightColor: AppTheme.purvaLight,
  );

  static const manas = FirmBankInfo(
    firmName: 'MANAS SALES',
    shortName: 'Manas',
    bankName: 'Central Bank of India',
    branch: 'Rajgurunagar',
    accountNumber: '5251719817',
    accountType: 'CC A/c',
    ifscCode: 'CBIN0284624',
    upiId: '9309862465@okbizaxis',
    mobileNumber: '+91 93098 62465',
    companies: ['Racket', 'Imami', 'Dabar', 'Cadbury', 'Gowardhan'],
    primaryColor: AppTheme.manasPrimary,
    lightColor: AppTheme.manasLight,
  );

  static FirmBankInfo getInfo(String firmName) {
    if (firmName.toLowerCase().contains('manas')) {
      return manas;
    }
    return purva;
  }

  static Future<void> shareViaWhatsApp({
    required BuildContext context,
    required FirmBankInfo firm,
    String? recipientMobile,
  }) async {
    final text = Uri.encodeComponent(firm.formattedShareText);
    Uri uri;
    if (recipientMobile != null && recipientMobile.trim().isNotEmpty) {
      String cleanPhone = recipientMobile.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanPhone.length == 10) {
        cleanPhone = '91$cleanPhone';
      }
      uri = Uri.parse('https://wa.me/$cleanPhone?text=$text');
    } else {
      uri = Uri.parse('https://wa.me/?text=$text');
    }

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        // Fallback to clipboard
        await copyToClipboard(context, firm);
      }
    } catch (_) {
      if (context.mounted) {
        await copyToClipboard(context, firm);
      }
    }
  }

  static Future<void> copyToClipboard(BuildContext context, FirmBankInfo firm) async {
    await Clipboard.setData(ClipboardData(text: firm.formattedShareText));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('${firm.firmName} bank details copied to clipboard!')),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  static void showQuickShareModal(
    BuildContext context, {
    String? defaultFirm,
    String? recipientMobile,
    String? recipientName,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuickSharePaymentSheet(
        defaultFirm: defaultFirm,
        recipientMobile: recipientMobile,
        recipientName: recipientName,
      ),
    );
  }
}

class _QuickSharePaymentSheet extends StatefulWidget {
  final String? defaultFirm;
  final String? recipientMobile;
  final String? recipientName;

  const _QuickSharePaymentSheet({
    this.defaultFirm,
    this.recipientMobile,
    this.recipientName,
  });

  @override
  State<_QuickSharePaymentSheet> createState() => _QuickSharePaymentSheetState();
}

class _QuickSharePaymentSheetState extends State<_QuickSharePaymentSheet> {
  late bool _isPurva;

  @override
  void initState() {
    super.initState();
    _isPurva = widget.defaultFirm == null ||
        !widget.defaultFirm!.toLowerCase().contains('manas');
  }

  @override
  Widget build(BuildContext context) {
    final firm = _isPurva ? FirmDetailsHelper.purva : FirmDetailsHelper.manas;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.send_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Send Payment Info',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (widget.recipientName != null)
                      Text(
                        'To: ${widget.recipientName}${widget.recipientMobile != null ? ' (${widget.recipientMobile})' : ''}',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Firm Switcher
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isPurva = true),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _isPurva ? AppTheme.purvaPrimary : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Center(
                        child: Text(
                          'PURVA ENTERPRISES',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _isPurva ? Colors.white : AppTheme.purvaText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isPurva = false),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_isPurva ? AppTheme.manasPrimary : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Center(
                        child: Text(
                          'MANAS SALES',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: !_isPurva ? Colors.white : AppTheme.manasText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bank Info Preview Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: firm.lightColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: firm.primaryColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      firm.firmName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: firm.primaryColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: firm.primaryColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        firm.accountType,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildInfoRow('Bank', firm.bankName),
                _buildInfoRow('Branch', firm.branch),
                _buildInfoRow('Account No', firm.accountNumber, isBold: true),
                _buildInfoRow('IFSC Code', firm.ifscCode, isBold: true),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    FirmDetailsHelper.copyToClipboard(context, firm);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy Details', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    FirmDetailsHelper.shareViaWhatsApp(
                      context: context,
                      firm: firm,
                      recipientMobile: widget.recipientMobile,
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.blueGrey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: const Color(0xFF0F172A),
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                fontFamily: isBold ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
