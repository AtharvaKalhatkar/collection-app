import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/collection_model.dart';
import '../providers/collection_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import 'record_collection_screen.dart';
import 'send_reminder_dialog.dart';
import '../widgets/fullscreen_image_viewer.dart';
import '../utils/image_compress_helper.dart';

class CollectionDetailsDialog extends StatelessWidget {
  final CollectionModel collection;

  const CollectionDetailsDialog({super.key, required this.collection});

  Color _getModeColor(PaymentMode mode) {
    switch (mode) {
      case PaymentMode.cash:
        return AppTheme.cashColor;
      case PaymentMode.upi:
        return AppTheme.upiColor;
      case PaymentMode.cheque:
        return AppTheme.chequeColor;
      case PaymentMode.netBanking:
        return AppTheme.netBankingColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final billSummary = provider.getBillSummary(collection.shopId, collection.billNumber);
    final overallPending = billSummary != null ? billSummary.isPending : collection.isPartial;
    final balanceDue = billSummary != null ? billSummary.balanceDue : collection.balanceAmount;
    final totalBill = billSummary != null ? billSummary.billTotal : collection.billAmount;
    final totalCollectedOnBill = billSummary != null ? billSummary.totalCollected : collection.collectedAmount;

    final modeColor = _getModeColor(collection.paymentMode);
    final timeStr = DateFormat('hh:mm a, dd MMM yyyy').format(collection.collectedAt);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with Business and close
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.getBusinessLightColor(collection.businessName),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.getBusinessBorderColor(collection.businessName)),
                      ),
                      child: Text(
                        collection.businessName,
                        style: TextStyle(
                          color: AppTheme.getBusinessTextColor(collection.businessName),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Shop Name & Route
                Text(
                  collection.shopName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 15, color: Colors.blueGrey),
                    const SizedBox(width: 4),
                    Text(
                      collection.routeName.isNotEmpty ? collection.routeName : 'General Beat',
                      style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.access_time, size: 15, color: Colors.blueGrey),
                    const SizedBox(width: 4),
                    Text(
                      timeStr,
                      style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Overall Invoice Status Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: overallPending
                        ? AppTheme.chequeColor.withValues(alpha: 0.08)
                        : AppTheme.cashColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: overallPending
                          ? AppTheme.chequeColor.withValues(alpha: 0.3)
                          : AppTheme.cashColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            overallPending ? Icons.pending_outlined : Icons.check_circle_outline,
                            size: 18,
                            color: overallPending ? AppTheme.chequeColor : AppTheme.cashColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            overallPending ? 'Status: PENDING' : 'Status: PAID',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: overallPending ? AppTheme.chequeColor : AppTheme.cashColor,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        overallPending
                            ? 'Due: ${CurrencyFormatter.format(balanceDue)}'
                            : 'Fully Settled',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: overallPending ? AppTheme.balanceDueColor : AppTheme.cashColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Financial Breakdown Card (Bill Amount, Collected, Balance)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Received', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                              const SizedBox(height: 2),
                              Text(
                                CurrencyFormatter.format(collection.collectedAmount),
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: modeColor,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: modeColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: modeColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(collection.paymentMode.icon, size: 14, color: modeColor),
                                const SizedBox(width: 6),
                                Text(
                                  collection.paymentMode.label,
                                  style: TextStyle(
                                    color: modeColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Text('Bill Total: ', style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
                              Text(
                                CurrencyFormatter.format(totalBill),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Text('Collected: ', style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
                              Text(
                                CurrencyFormatter.format(totalCollectedOnBill),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Details Table
                _buildInfoRow('Invoice No.', collection.billNumber.isNotEmpty ? collection.billNumber : 'N/A', Icons.receipt_outlined),
                _buildInfoRow('Bill Date', DateFormat('dd MMM yyyy').format(collection.billDate), Icons.calendar_today_outlined),
                _buildInfoRow('Collected On', DateFormat('hh:mm a, dd MMM yyyy').format(collection.collectedAt), Icons.event_available_outlined),
                if (collection.chequeNumber != null && collection.chequeNumber!.isNotEmpty)
                  _buildInfoRow('Cheque No.', collection.chequeNumber!, Icons.numbers_outlined),
                if (collection.bankName != null && collection.bankName!.isNotEmpty)
                  _buildInfoRow('Bank Name', collection.bankName!, Icons.account_balance_outlined),
                if (collection.referenceNumber != null && collection.referenceNumber!.isNotEmpty)
                  _buildInfoRow('Ref / UTR', collection.referenceNumber!, Icons.tag_outlined),
                _buildInfoRow('Collected By', collection.salesmanName, Icons.person_outline),
                if (collection.remarks != null && collection.remarks!.isNotEmpty)
                  _buildInfoRow('Remarks', collection.remarks!, Icons.notes_outlined),

                // Multi-Installment History if more than 1 payment
                if (billSummary != null && billSummary.collections.length > 1) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'PAYMENT HISTORY FOR THIS INVOICE',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 0.8,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: billSummary.collections.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final hist = billSummary.collections[idx];
                        final histTime = DateFormat('dd MMM, hh:mm a').format(hist.collectedAt);
                        final isCurrent = hist.id == collection.id;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(hist.paymentMode.icon, size: 15, color: _getModeColor(hist.paymentMode)),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${hist.paymentMode.label} ${isCurrent ? "(This Entry)" : ""}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                        ),
                                      ),
                                      Text(histTime, style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade600)),
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                CurrencyFormatter.format(hist.collectedAmount),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],

                // Photo preview if available (Clickable & Zoomable)
                Builder(
                  builder: (ctx) {
                    final docPhotos = collection.allPhotos.isNotEmpty
                        ? collection.allPhotos
                        : provider.getPhotosForBill(collection.billNumber, shopId: collection.shopId, shopName: collection.shopName);
                    final firstPhoto = docPhotos.isNotEmpty
                        ? docPhotos.first
                        : (collection.photoBase64 ?? provider.getPhotoForBill(collection.billNumber, shopId: collection.shopId, shopName: collection.shopName));

                    final photoBytes = ImageCompressHelper.safeBase64Decode(firstPhoto);
                    if (photoBytes == null) {
                      return const SizedBox.shrink();
                    }

                    final hasMultiple = docPhotos.length > 1;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'DOCUMENT PROOF (बिल फोटो)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    letterSpacing: 0.8,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                                if (hasMultiple) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.amber.shade400),
                                    ),
                                    child: Text(
                                      '${docPhotos.length} Photos',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FullScreenImageViewer(
                                      imagesBase64: docPhotos.isNotEmpty ? docPhotos : (firstPhoto != null ? [firstPhoto] : null),
                                      title: 'Invoice Proof #${collection.billNumber}',
                                      subtitle: hasMultiple
                                          ? '${docPhotos.length} Photos Attached • ${collection.shopName}'
                                          : '${collection.shopName} • ${collection.businessName}',
                                    ),
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.fullscreen, size: 16, color: AppTheme.primary),
                                  SizedBox(width: 4),
                                  Text(
                                    'Full Screen Zoom',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FullScreenImageViewer(
                                  imagesBase64: docPhotos.isNotEmpty ? docPhotos : (firstPhoto != null ? [firstPhoto] : null),
                                  title: 'Invoice Proof #${collection.billNumber}',
                                  subtitle: hasMultiple
                                      ? '${docPhotos.length} Photos Attached • ${collection.shopName}'
                                      : '${collection.shopName} • ${collection.businessName}',
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 180,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    border: Border.all(color: AppTheme.border),
                                  ),
                                  child: Image.memory(
                                    photoBytes,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(child: Text('Could not load photo'));
                                    },
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.zoom_in, size: 14, color: Colors.white),
                                      const SizedBox(width: 4),
                                      Text(
                                        hasMultiple ? 'Tap to View All ${docPhotos.length} Photos' : 'Tap to Zoom & Enlarge',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),

                // Pending Actions: Collect Balance & Send Reminder
                if (overallPending && balanceDue > 0) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_card_outlined, size: 17),
                    label: Text(
                      'Collect Remaining Balance (${CurrencyFormatter.format(balanceDue)})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RecordCollectionScreen(
                            initialShopId: collection.shopId,
                            initialBillNumber: collection.billNumber,
                            initialBillTotal: totalBill,
                            initialBalanceDue: balanceDue,
                            initialBusiness: collection.businessName,
                            isFollowUp: true,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_active_outlined, size: 16, color: AppTheme.chequeColor),
                    label: Text(
                      'Send Payment Reminder (${CurrencyFormatter.format(balanceDue)})',
                      style: const TextStyle(color: AppTheme.chequeColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.chequeColor),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final shop = provider.getShopById(collection.shopId);
                      showDialog(
                        context: context,
                        builder: (ctx) => SendReminderDialog(
                          shopName: collection.shopName,
                          mobileNumber: shop?.mobileNumber ?? '',
                          businessName: collection.businessName,
                          salesmanName: collection.salesmanName,
                          balanceAmount: balanceDue,
                          billNumber: collection.billNumber,
                          billTotal: totalBill,
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: 16),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline, color: AppTheme.balanceDueColor, size: 18),
                        label: const Text('Delete Entry', style: TextStyle(color: AppTheme.balanceDueColor)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Record?'),
                              content: const Text('This cannot be undone.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.balanceDueColor),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && context.mounted) {
                            await context.read<CollectionProvider>().deleteCollection(collection.id);
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
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

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Colors.blueGrey.shade600),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
