import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';

class PaymentQrDialog extends StatefulWidget {
  final String? initialFirm;

  const PaymentQrDialog({super.key, this.initialFirm});

  static Future<void> show(BuildContext context, {String? initialFirm}) {
    return showDialog(
      context: context,
      builder: (_) => PaymentQrDialog(initialFirm: initialFirm),
    );
  }

  @override
  State<PaymentQrDialog> createState() => _PaymentQrDialogState();
}

class _PaymentQrDialogState extends State<PaymentQrDialog> {
  late bool _isPurva;

  @override
  void initState() {
    super.initState();
    _isPurva = widget.initialFirm == null || widget.initialFirm == 'Purva Enterprises' || widget.initialFirm == 'Purva';
  }

  void _copyUpiId(String upiId) {
    Clipboard.setData(ClipboardData(text: upiId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Copied UPI ID: $upiId')),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firmName = _isPurva ? 'Purva Enterprises' : 'Manas Sales';
    final firmShort = _isPurva ? 'Purva' : 'Manas';
    final firmPhone = _isPurva ? '+91 84596 71694' : '+91 93098 62465';
    final upiId = _isPurva ? '8459671694@okbizaxis' : '9309862465@okbizaxis';
    final bankName = _isPurva ? 'Union Bank' : 'Central Bank';
    final assetPath = _isPurva ? 'assets/images/qr_purva.png' : 'assets/images/qr_manas.png';
    final firmPrimaryColor = _isPurva ? AppTheme.purvaPrimary : AppTheme.manasPrimary;
    final firmLightColor = _isPurva ? AppTheme.purvaLight : AppTheme.manasLight;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with firm selector and close button
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      _isPurva ? 'Purva - UPI QR' : 'Manas - UPI QR',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Firm Switcher Bar (only shown when not locked to a specific firm)
                    if (widget.initialFirm == null || widget.initialFirm == 'All') ...[
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _isPurva = true),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _isPurva ? AppTheme.purvaPrimary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'PURVA (Union Bank)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: _isPurva ? Colors.white : AppTheme.purvaText,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _isPurva = false),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: !_isPurva ? AppTheme.manasPrimary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'MANAS (Central Bank)',
                                      style: TextStyle(
                                        fontSize: 11,
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
                      const SizedBox(height: 14),
                    ],

                    // Firm Info Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: firmLightColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: firmPrimaryColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                firmName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: firmPrimaryColor,
                                ),
                              ),
                              Text(
                                firmPhone,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blueGrey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: firmPrimaryColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              bankName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // High-Resolution QR Code Image
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          assetPath,
                          width: 250,
                          height: 330,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return SizedBox(
                              width: 250,
                              height: 250,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.qr_code, size: 60, color: Colors.blueGrey),
                                    const SizedBox(height: 8),
                                    Text(
                                      '$firmShort QR Code',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      upiId,
                                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // UPI ID Box with Tap-to-Copy
                    InkWell(
                      onTap: () => _copyUpiId(upiId),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'UPI ID: $upiId',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.copy_rounded, size: 15, color: AppTheme.primary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Done / Close button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: firmPrimaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Close',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
