import 'package:flutter/material.dart';
import '../utils/theme.dart';
import '../utils/firm_details.dart';
import '../utils/qr_data.dart';

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
  int _manasQrIndex = 1; // 1 = QR 1, 2 = QR 2

  @override
  void initState() {
    super.initState();
    _isPurva = widget.initialFirm == null || widget.initialFirm == 'Purva Enterprises' || widget.initialFirm == 'Purva';
  }

  @override
  Widget build(BuildContext context) {
    final firmInfo = _isPurva ? FirmDetailsHelper.purva : FirmDetailsHelper.manas;
    final firmName = firmInfo.firmName;
    final assetPath = _isPurva
        ? 'assets/images/qr_purva.png'
        : (_manasQrIndex == 1
            ? 'assets/images/qr_manas_sales.png'
            : 'assets/images/qr_manas.png');
    final firmPrimaryColor = firmInfo.primaryColor;
    final firmLightColor = firmInfo.lightColor;

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
                                      'PURVA ENTERPRISES',
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
                                      'MANAS SALES',
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

                    // Firm Info Badge (Clean without phone number)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: firmLightColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: firmPrimaryColor.withValues(alpha: 0.3)),
                      ),
                      child: Center(
                        child: Text(
                          firmName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: firmPrimaryColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // QR Switcher: Clean QR 1 and QR 2
                    if (!_isPurva) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ChoiceChip(
                            label: const Text('QR 1', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            selected: _manasQrIndex == 1,
                            selectedColor: AppTheme.manasPrimary.withValues(alpha: 0.15),
                            checkmarkColor: AppTheme.manasPrimary,
                            onSelected: (_) => setState(() => _manasQrIndex = 1),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('QR 2', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            selected: _manasQrIndex == 2,
                            selectedColor: AppTheme.manasPrimary.withValues(alpha: 0.15),
                            checkmarkColor: AppTheme.manasPrimary,
                            onSelected: (_) => setState(() => _manasQrIndex = 2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
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
                        child: (_isPurva || _manasQrIndex == 2)
                            ? Image.memory(
                                _isPurva ? QrData.purvaBytes : QrData.manasBytes,
                                width: 250,
                                height: 330,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Image.asset(
                                    assetPath,
                                    width: 250,
                                    height: 330,
                                    fit: BoxFit.contain,
                                  );
                                },
                              )
                            : Image.asset(
                                assetPath,
                                width: 250,
                                height: 330,
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'Scan using Google Pay, PhonePe, Paytm or any UPI App',
                      style: TextStyle(fontSize: 11.5, color: Colors.blueGrey, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),

                    // Quick Action Button: WhatsApp
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text('Share via WhatsApp', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        onPressed: () => FirmDetailsHelper.shareViaWhatsApp(
                          context: context,
                          firm: firmInfo,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Close button
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close', style: TextStyle(color: Colors.grey)),
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
