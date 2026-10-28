import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/pending_bill_model.dart';
import '../models/shop_model.dart';
import '../models/collection_model.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import '../utils/marathi_search_helper.dart';
import '../widgets/payment_receipt_dialog.dart';
import '../widgets/payment_qr_dialog.dart';
import '../utils/firm_details.dart';
import '../utils/qr_data.dart';
import '../services/location_tracking_service.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  int _currentTab = 0;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final auth = context.read<AuthProvider>();
        final provider = context.read<CollectionProvider>();
        LocationTrackingService().startTracking(
          auth: auth,
          collectionProvider: provider,
        );
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openGoogleMaps(ShopModel shop) async {
    final auth = context.read<AuthProvider>();
    if (auth.currentUser != null) {
      LocationTrackingService().recordCustomEvent(
        user: auth.currentUser!,
        eventType: 'deliveryVisit',
        details: 'Driver delivery stop at ${shop.name}',
        latitude: shop.latitude,
        longitude: shop.longitude,
        landmark: '${shop.name} (${shop.address})',
        shopName: shop.name,
        routeName: shop.routeName,
      );
    }
    final url = shop.mapsUrl ??
        'https://maps.google.com/?q=${Uri.encodeComponent('${shop.name}, ${shop.address}')}';
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open Maps: $e')),
        );
      }
    }
  }

  void _callPhone(String phone) async {
    if (phone.trim().isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showCollectPaymentDialog(BuildContext context, PendingBillModel bill) {
    final provider = context.read<CollectionProvider>();
    final auth = context.read<AuthProvider>();
    final currentUser = auth.currentUser;

    final shop = provider.shops.firstWhere(
      (s) => s.id == bill.shopId,
      orElse: () => ShopModel(
        id: bill.shopId,
        name: bill.shopName,
        routeId: bill.routeId,
        routeName: bill.routeName,
        mobileNumber: '',
        address: '',
      ),
    );

    final amountCtrl = TextEditingController(
      text: bill.balanceDue.toStringAsFixed(0),
    );
    final chequeNoCtrl = TextEditingController();
    final refNoCtrl = TextEditingController();

    PaymentMode selectedMode = PaymentMode.cash;

    List<String> getBanksForSelection(String firm, PaymentMode mode) {
      final isPurva = firm == 'Purva Enterprises';
      switch (mode) {
        case PaymentMode.upi:
          return isPurva ? ['Union Bank'] : ['Central Bank'];
        case PaymentMode.netBanking:
          return isPurva ? ['Union Bank', 'RSBL'] : ['Central Bank'];
        case PaymentMode.cheque:
          return isPurva ? ['RSBL', 'Union Bank'] : ['Central Bank'];
        case PaymentMode.cash:
          return [];
      }
    }

    String? selectedBank;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isPurva = bill.businessName == 'Purva Enterprises';
          final availableBanks = getBanksForSelection(bill.businessName, selectedMode);
          if (availableBanks.isNotEmpty && (selectedBank == null || !availableBanks.contains(selectedBank))) {
            selectedBank = availableBanks.first;
          } else if (availableBanks.isEmpty) {
            selectedBank = null;
          }

          final enteredAmount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
          final balanceRemaining = (bill.balanceDue - enteredAmount);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 4),
                  ],
                ),
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Grab Handle
                      Center(
                        child: Container(
                          width: 44,
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
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.payments_rounded, color: Color(0xFF059669), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Collect Payment',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  bill.shopName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueGrey.shade700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 22, color: Colors.blueGrey),
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(bottomSheetCtx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Invoice & Balance Due Summary Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.getBusinessLightColor(bill.businessName),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppTheme.getBusinessBorderColor(bill.businessName)),
                                  ),
                                  child: Text(
                                    bill.businessName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.getBusinessTextColor(bill.businessName),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    const Text('Bill No: ', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                    Text(
                                      bill.billNumber,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 16, thickness: 0.8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Total Bill Amount', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                                    const SizedBox(height: 2),
                                    Text(
                                      CurrencyFormatter.format(bill.totalAmount),
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text('Balance Due', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                                    const SizedBox(height: 2),
                                    Text(
                                      CurrencyFormatter.format(bill.balanceDue),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Quick Action Buttons: Send Bank Details & Show QR
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                FirmDetailsHelper.showQuickShareModal(
                                  context,
                                  defaultFirm: bill.businessName,
                                  recipientMobile: shop.mobileNumber,
                                  recipientName: bill.shopName,
                                );
                              },
                              icon: const Icon(Icons.chat_bubble_outline, size: 15, color: Color(0xFF15803D)),
                              label: const Text(
                                'WhatsApp Bank Details',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF86EFAC)),
                                backgroundColor: const Color(0xFFF0FDF4),
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => PaymentQrDialog.show(context, initialFirm: bill.businessName),
                              icon: const Icon(Icons.qr_code_2_rounded, size: 16, color: Color(0xFF1D4ED8)),
                              label: const Text(
                                'Show UPI QR',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8)),
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFBFDBFE)),
                                backgroundColor: const Color(0xFFEFF6FF),
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Collected Amount Field
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Collected Amount (₹)',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                              ),
                              // Quick shortcut chip: Full Due
                              InkWell(
                                onTap: () {
                                  setDlgState(() {
                                    amountCtrl.text = bill.balanceDue.toStringAsFixed(0);
                                  });
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check, size: 12, color: Color(0xFF0F172A)),
                                      SizedBox(width: 4),
                                      Text('Full Due', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            onChanged: (_) => setDlgState(() {}),
                            decoration: InputDecoration(
                              prefixIcon: const Padding(
                                padding: EdgeInsets.only(left: 14, right: 8),
                                child: Text('₹', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                              ),
                              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                              ),
                              suffixIcon: amountCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18, color: Colors.blueGrey),
                                      onPressed: () {
                                        setDlgState(() {
                                          amountCtrl.clear();
                                        });
                                      },
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Live balance status feedback
                          if (enteredAmount > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    balanceRemaining <= 0 ? Icons.check_circle : Icons.info_outline,
                                    size: 13,
                                    color: balanceRemaining <= 0 ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    balanceRemaining <= 0
                                        ? 'Full Payment • Remaining: ₹0'
                                        : 'Partial Payment • Remaining: ${CurrencyFormatter.format(balanceRemaining)}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: balanceRemaining <= 0 ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Payment Mode Grid (4 Equal Symmetrical Columns)
                      const Text(
                        'Payment Mode:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          PaymentMode.cash,
                          PaymentMode.upi,
                          PaymentMode.netBanking,
                          PaymentMode.cheque,
                        ].map((mode) {
                          final isSel = selectedMode == mode;
                          Color modeColor;
                          switch (mode) {
                            case PaymentMode.cash:
                              modeColor = AppTheme.cashColor;
                              break;
                            case PaymentMode.upi:
                              modeColor = AppTheme.upiColor;
                              break;
                            case PaymentMode.cheque:
                              modeColor = AppTheme.chequeColor;
                              break;
                            case PaymentMode.netBanking:
                              modeColor = AppTheme.netBankingColor;
                              break;
                          }

                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: InkWell(
                                onTap: () {
                                  setDlgState(() {
                                    selectedMode = mode;
                                    final banks = getBanksForSelection(bill.businessName, mode);
                                    selectedBank = banks.isNotEmpty ? banks.first : null;
                                  });
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSel ? modeColor : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSel ? modeColor : const Color(0xFFE2E8F0),
                                      width: isSel ? 1.6 : 1.0,
                                    ),
                                    boxShadow: isSel
                                        ? [
                                            BoxShadow(
                                              color: modeColor.withValues(alpha: 0.25),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        mode.icon,
                                        size: 20,
                                        color: isSel ? Colors.white : modeColor,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        mode.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: isSel ? Colors.white : const Color(0xFF334155),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      // Deposit Bank Selector (Union Bank / RSBL / Central Bank)
                      if (availableBanks.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Deposit To Bank:',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                            ),
                            Text(
                              bill.businessName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isPurva ? AppTheme.purvaPrimary : AppTheme.manasPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: availableBanks.map((b) {
                            final isSel = selectedBank == b;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: InkWell(
                                  onTap: () => setDlgState(() => selectedBank = b),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? (isPurva ? AppTheme.purvaPrimary : AppTheme.manasPrimary)
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSel
                                            ? (isPurva ? AppTheme.purvaPrimary : AppTheme.manasPrimary)
                                            : AppTheme.border,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        b,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: isSel ? Colors.white : Colors.blueGrey.shade800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      // UPI Quick Card
                      if (selectedMode == PaymentMode.upi) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.memory(
                                      isPurva ? QrData.purvaBytes : QrData.manasBytes,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.qr_code, size: 44),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${isPurva ? "Purva" : "Manas"} UPI QR',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                                        ),
                                        Text(
                                          isPurva ? '8459671694@okbizaxis' : '9309862465@okbizaxis',
                                          style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade700),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.fullscreen, size: 16),
                                    onPressed: () => PaymentQrDialog.show(context, initialFirm: bill.businessName),
                                    label: const Text('Show QR', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Net Banking Card
                      if (selectedMode == PaymentMode.netBanking) ...[
                        const SizedBox(height: 12),
                        Builder(
                          builder: (ctx) {
                            final firmInfo = FirmDetailsHelper.getInfo(bill.businessName);
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFBBF7D0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${firmInfo.shortName} Bank Details',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                                      ),
                                      Text(
                                        firmInfo.accountType,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Bank: ${firmInfo.bankName} • A/c: ${firmInfo.accountNumber}',
                                    style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade800),
                                  ),
                                  Text(
                                    'IFSC: ${firmInfo.ifscCode}',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade800),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],

                      // Cheque Number Input
                      if (selectedMode == PaymentMode.cheque) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: chequeNoCtrl,
                          decoration: InputDecoration(
                            labelText: 'Cheque Number (Optional)',
                            hintText: 'e.g. 123456',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],

                      // UTR Reference Input
                      if (selectedMode == PaymentMode.upi || selectedMode == PaymentMode.netBanking) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: refNoCtrl,
                          decoration: InputDecoration(
                            labelText: 'UTR / Transaction Reference (Optional)',
                            hintText: 'e.g. UPI Ref / NEFT Ref',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),

                      // Action Buttons (Cancel and Save & Verify)
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => Navigator.pop(bottomSheetCtx),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF64748B)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 1,
                              ),
                              icon: const Icon(Icons.check_circle_outline, size: 18),
                              label: const Text(
                                'Save & Verify',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              onPressed: () async {
                                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                                if (amount <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enter a valid collection amount')),
                                  );
                                  return;
                                }

                                Navigator.pop(bottomSheetCtx);

                                // Record payment in provider with bank name, cheque number, reference
                                await provider.recordCollectionForPendingBill(
                                  pendingBill: bill,
                                  collectedAmount: amount,
                                  paymentMode: selectedMode,
                                  collectionDate: DateTime.now(),
                                  bankName: selectedBank,
                                  chequeNumber: selectedMode == PaymentMode.cheque ? chequeNoCtrl.text.trim() : null,
                                  referenceNumber: (selectedMode == PaymentMode.upi || selectedMode == PaymentMode.netBanking) ? refNoCtrl.text.trim() : null,
                                );

                                if (!context.mounted) return;

                                // Show 2-Factor verification receipt for customer
                                final remaining = (bill.balanceDue - amount) > 0 ? (bill.balanceDue - amount) : 0.0;
                                final driverName = currentUser?.name ?? 'user1';

                                await PaymentReceiptDialog.show(
                                  context,
                                  customerName: bill.shopName,
                                  customerMobile: shop.mobileNumber,
                                  firmName: bill.businessName,
                                  billNo: bill.billNumber,
                                  billTotal: bill.totalAmount,
                                  amountCollected: amount,
                                  balanceRemaining: remaining,
                                  paymentMode: selectedMode,
                                  salesmanName: driverName,
                                  collectionDate: DateTime.now(),
                                );
                              },
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
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<CollectionProvider>();
    final user = auth.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Session expired. Please log in.')));
    }

    final assignedRoutes = provider.allRoutes
        .where((r) => user.assignedRouteIds.contains(r.id))
        .toList();
    final routeNamesStr = assignedRoutes.isNotEmpty
        ? assignedRoutes.map((r) => r.name).join(', ')
        : 'No route assigned';

    // Pending bills for this driver's assigned routes
    final deliveryBills = provider.pendingBills
        .where((b) => !b.isPaid)
        .where((b) {
          if (_searchQuery.trim().isEmpty) return true;
          final q = _searchQuery.toLowerCase().trim();
          return MarathiSearchHelper.matches(b.shopName, q) ||
              b.billNumber.toLowerCase().contains(q);
        })
        .toList();

    // Outlets for this driver's assigned routes
    final routeShops = provider.shops.where((s) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      return MarathiSearchHelper.matches(s.name, q) ||
          s.address.toLowerCase().contains(q) ||
          s.mobileNumber.contains(q);
    }).toList();

    // Driver's collections today
    final todayCollections = provider.getFilteredCollections();
    final todayTotal = todayCollections.fold(0.0, (s, c) => s + c.collectedAmount);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, size: 18, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                Text(
                  user.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    'DRIVER',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Route: $routeNamesStr',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Payment QR',
            icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
            onPressed: () => PaymentQrDialog.show(context),
          ),
          IconButton(
            tooltip: 'Bank Details',
            icon: const Icon(Icons.account_balance_outlined, color: Colors.white),
            onPressed: () => FirmDetailsHelper.showQuickShareModal(context),
          ),
          IconButton(
            tooltip: 'Sync Data',
            icon: const Icon(Icons.sync, color: Colors.white70),
            onPressed: () async {
              await provider.syncAllWithCloud(notify: true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Delivery data refreshed!'), duration: Duration(seconds: 1)),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Logout Driver?'),
                  content: const Text('Are you sure you want to log out of the Driver account?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Logout', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await auth.logout();
              }
            },
          ),
        ],
      ),
      body: user.assignedRouteIds.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.route, size: 54, color: Colors.amber.shade800),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No Delivery Route Assigned Today',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Super Admin has not assigned a route to this login yet.\nPlease contact Super Admin to assign your delivery route.',
                      style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check for Assigned Route'),
                      onPressed: () => auth.initialize(),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Top Search Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.white,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: _currentTab == 0
                          ? 'Search delivery bills by shop or #...'
                          : (_currentTab == 1 ? 'Search outlets by name or area...' : 'Search collections...'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const Divider(height: 1),

                // Tab Content
                Expanded(
                  child: IndexedStack(
                    index: _currentTab,
                    children: [
                      // Tab 0: Delivery Pending Bills
                      _buildDeliveryBillsTab(deliveryBills),
                      // Tab 1: Route Outlets & Navigation
                      _buildOutletsTab(routeShops),
                      // Tab 2: My Collections Today
                      _buildCollectionsTab(todayCollections, todayTotal),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (idx) => setState(() => _currentTab = idx),
        indicatorColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: deliveryBills.isNotEmpty,
              label: Text('${deliveryBills.length}'),
              child: const Icon(Icons.local_shipping_outlined),
            ),
            selectedIcon: const Icon(Icons.local_shipping, color: AppTheme.primary),
            label: 'Delivery Bills',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: routeShops.isNotEmpty,
              label: Text('${routeShops.length}'),
              child: const Icon(Icons.storefront_outlined),
            ),
            selectedIcon: const Icon(Icons.storefront, color: AppTheme.primary),
            label: 'Route Outlets',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: todayCollections.isNotEmpty,
              label: Text('${todayCollections.length}'),
              child: const Icon(Icons.check_circle_outline),
            ),
            selectedIcon: const Icon(Icons.check_circle, color: AppTheme.primary),
            label: 'My Collections',
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryBillsTab(List<PendingBillModel> bills) {
    if (bills.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.done_all_rounded, size: 54, color: Colors.green.shade400),
              const SizedBox(height: 12),
              const Text('No Pending Bills on this Route', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('All bills on your assigned route are settled!', style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final totalPendingAmount = bills.fold(0.0, (s, b) => s + b.balanceDue);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFFEFF6FF),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${bills.length} Pending Bills to Deliver',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
              ),
              Text(
                'Total: ${CurrencyFormatter.format(totalPendingAmount)}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF1E3A8A)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: bills.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (ctx, idx) {
              final bill = bills[idx];
              final dateStr = DateFormat('dd MMM yyyy').format(bill.invoiceDate);

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blueGrey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bill.shopName,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Bill #${bill.billNumber} • $dateStr • ${bill.businessName}',
                                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                CurrencyFormatter.format(bill.balanceDue),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                              Text(
                                'Due of ${CurrencyFormatter.format(bill.totalAmount)}',
                                style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.payments_outlined, size: 18),
                              label: const Text('Collect Payment', style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: () => _showCollectPaymentDialog(context, bill),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: 'Show QR',
                            icon: const Icon(Icons.qr_code_2_rounded, size: 18, color: AppTheme.primary),
                            onPressed: () => PaymentQrDialog.show(context, initialFirm: bill.businessName),
                          ),
                          const SizedBox(width: 4),
                          IconButton.outlined(
                            tooltip: 'Send Bank Details',
                            icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF10B981)),
                            onPressed: () {
                              final p = context.read<CollectionProvider>();
                              final shop = p.shops.firstWhere(
                                (s) => s.id == bill.shopId,
                                orElse: () => ShopModel(
                                  id: bill.shopId,
                                  name: bill.shopName,
                                  routeId: bill.routeId,
                                  routeName: bill.routeName,
                                  mobileNumber: '',
                                  address: '',
                                ),
                              );
                              FirmDetailsHelper.showQuickShareModal(
                                context,
                                defaultFirm: bill.businessName,
                                recipientMobile: shop.mobileNumber,
                                recipientName: bill.shopName,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOutletsTab(List<ShopModel> shops) {
    if (shops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.storefront_outlined, size: 54, color: Colors.blueGrey.shade300),
              const SizedBox(height: 12),
              const Text('No Outlets on this Route', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: shops.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final shop = shops[idx];

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.blueGrey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.storefront, color: Color(0xFF0284C7), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop.name,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          if (shop.ownerName != null && shop.ownerName!.isNotEmpty)
                            Text(
                              'Owner: ${shop.ownerName}',
                              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                            ),
                          if (shop.address.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                shop.address,
                                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Google Maps Navigation Button
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.navigation_rounded, size: 18),
                        label: const Text('Maps Navigate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        onPressed: () => _openGoogleMaps(shop),
                      ),
                    ),
                    if (shop.mobileNumber.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.phone, size: 16, color: Color(0xFF10B981)),
                        label: const Text('Call', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                        onPressed: () => _callPhone(shop.mobileNumber),
                      ),
                    ],
                    const SizedBox(width: 6),
                    IconButton.outlined(
                      tooltip: 'Send Bank Details',
                      icon: const Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFF10B981)),
                      onPressed: () {
                        FirmDetailsHelper.showQuickShareModal(
                          context,
                          recipientMobile: shop.mobileNumber,
                          recipientName: shop.name,
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    IconButton.outlined(
                      tooltip: 'Show QR',
                      icon: const Icon(Icons.qr_code_2_rounded, size: 16, color: AppTheme.primary),
                      onPressed: () => PaymentQrDialog.show(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollectionsTab(List<CollectionModel> collections, double total) {
    if (collections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined, size: 54, color: Colors.blueGrey.shade300),
              const SizedBox(height: 12),
              const Text('No Collections Recorded Today', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Deliver pending bills and tap "Collect Payment" to record receipts.', style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final cash = collections.where((c) => c.paymentMode == PaymentMode.cash).fold(0.0, (s, c) => s + c.collectedAmount);
    final upi = collections.where((c) => c.paymentMode == PaymentMode.upi).fold(0.0, (s, c) => s + c.collectedAmount);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Collected Today', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    Text(
                      CurrencyFormatter.format(total),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Cash: ${CurrencyFormatter.format(cash)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    Text('UPI: ${CurrencyFormatter.format(upi)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: collections.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (ctx, idx) {
              final c = collections[idx];
              final timeStr = DateFormat('hh:mm a').format(c.collectedAt);

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.blueGrey.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(c.shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      Text(
                        CurrencyFormatter.format(c.collectedAmount),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF10B981)),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    'Bill #${c.billNumber} • ${c.paymentMode.label} • $timeStr',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
