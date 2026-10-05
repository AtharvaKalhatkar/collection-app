import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/collection_provider.dart';
import '../utils/theme.dart';
import 'payment_qr_dialog.dart';

class FirmInfoDialog extends StatelessWidget {
  const FirmInfoDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const FirmInfoDialog(),
    );
  }

  void _copyFirmDetails(BuildContext context) {
    const text = '''
PURVA ENTERPRISES
• Companies: Wipro, Fena, Funfood, Imami
• Banks:
  - Union Bank of India (UPI, Net Banking, Cheque)
  - RSBL (Net Banking, Cheque)

MANAS SALES
• Companies: Racket, Imami, Dabar, Cadbury, Gowardhan
• Banks:
  - Central Bank of India (UPI, Net Banking, Cheque)
''';
    Clipboard.setData(const ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Firm & Bank info copied to clipboard!'),
          ],
        ),
        backgroundColor: Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Profile & Close Button
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF334155)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(Icons.person, color: Colors.white, size: 24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              provider.salesmanName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'OFFICER',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF059669),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${provider.routes.length} Routes • ${provider.shops.length} Outlets registered',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.blueGrey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Firm 1: Purva Enterprises Card
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.purvaLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.purvaBorder, width: 1.2),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.purvaPrimary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'PURVA',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Purva Enterprises',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.purvaText,
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            PaymentQrDialog.show(context, initialFirm: 'Purva Enterprises');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.purvaBorder),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.qr_code_2, size: 14, color: AppTheme.purvaPrimary),
                                SizedBox(width: 4),
                                Text(
                                  'QR Code',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.purvaPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'COMPANIES:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: const [
                        _FirmBadge(label: 'Wipro'),
                        _FirmBadge(label: 'Fena'),
                        _FirmBadge(label: 'Funfood'),
                        _FirmBadge(label: 'Imami'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'COLLECTION BANK ACCOUNTS:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildBankRow(
                      bank: 'Union Bank of India',
                      modes: 'UPI • Net Banking • Cheque',
                      color: AppTheme.purvaPrimary,
                    ),
                    const SizedBox(height: 4),
                    _buildBankRow(
                      bank: 'RSBL',
                      modes: 'Net Banking • Cheque',
                      color: Colors.blueGrey.shade700,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Firm 2: Manas Sales Card
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.manasLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.manasBorder, width: 1.2),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.manasPrimary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'MANAS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Manas Sales',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.manasText,
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            PaymentQrDialog.show(context, initialFirm: 'Manas Sales');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.manasBorder),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.qr_code_2, size: 14, color: AppTheme.manasPrimary),
                                SizedBox(width: 4),
                                Text(
                                  'QR Code',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.manasPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'COMPANIES:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: const [
                        _FirmBadge(label: 'Racket'),
                        _FirmBadge(label: 'Imami'),
                        _FirmBadge(label: 'Dabar'),
                        _FirmBadge(label: 'Cadbury'),
                        _FirmBadge(label: 'Gowardhan'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'COLLECTION BANK ACCOUNTS:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildBankRow(
                      bank: 'Central Bank of India',
                      modes: 'UPI • Net Banking • Cheque',
                      color: AppTheme.manasPrimary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Bottom Actions: Copy Details and Close
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy Details'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _copyFirmDetails(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildBankRow({
    required String bank,
    required String modes,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance, size: 15, color: color),
              const SizedBox(width: 8),
              Text(
                bank,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          Text(
            modes,
            style: TextStyle(fontSize: 10.5, color: Colors.blueGrey.shade600, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _FirmBadge extends StatelessWidget {
  final String label;
  const _FirmBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
      ),
    );
  }
}
