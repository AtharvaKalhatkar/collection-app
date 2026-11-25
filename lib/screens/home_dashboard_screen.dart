import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../utils/theme.dart';
import '../widgets/assign_routes_dialog.dart';
import '../providers/collection_provider.dart';
import '../providers/auth_provider.dart';
import '../models/payment_mode.dart';
import '../utils/currency_formatter.dart';
import 'add_pending_bill_screen.dart';
import 'pending_bills_list_screen.dart';
import 'make_collection_screen.dart';
import 'statement_screen.dart';
import 'cash_handover_screen.dart';
import 'collection_details_dialog.dart';
import 'add_shop_screen.dart';
import '../widgets/payment_qr_dialog.dart';
import 'profile_screen.dart';
import 'live_staff_locations_screen.dart';
import 'order_dashboard_screen.dart';
import 'all_orders_screen.dart';
import '../widgets/tally_sync_dialog.dart';
import '../utils/firm_details.dart';
import '../widgets/clean_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeDashboardScreen extends StatelessWidget {
  final VoidCallback onNavigateToRoutes;
  final VoidCallback onNavigateToCollections;
  final VoidCallback? onNavigateToOrders;
  final VoidCallback? onNavigateToProfile;
  final VoidCallback? onNavigateToTracking;

  const HomeDashboardScreen({
    super.key,
    required this.onNavigateToRoutes,
    required this.onNavigateToCollections,
    this.onNavigateToOrders,
    this.onNavigateToProfile,
    this.onNavigateToTracking,
  });

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

  void _showModeBillsSheet(BuildContext context, CollectionProvider provider, PaymentMode mode) {
    final modeBills = provider.getCollectionsForMode(
      mode,
      forDate: provider.selectedDate,
      business: provider.filterBusiness,
    );
    final totalAmount = modeBills.fold(0.0, (s, c) => s + c.collectedAmount);
    final modeColor = _getModeColor(mode);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: modeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(mode.icon, color: modeColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${mode.label} Collections',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Total: ${CurrencyFormatter.format(totalAmount)} (${modeBills.length} receipts)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: modeColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Expanded(
                  child: modeBills.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(mode.icon, size: 44, color: Colors.blueGrey.shade200),
                              const SizedBox(height: 8),
                              Text(
                                'No ${mode.label} collections recorded for this date',
                                style: TextStyle(color: Colors.blueGrey.shade600),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: modeBills.length,
                          separatorBuilder: (_, index) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final item = modeBills[idx];
                            final timeStr = DateFormat('hh:mm a').format(item.collectedAt);
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.shopName,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                    ),
                                  ),
                                  Text(
                                    CurrencyFormatter.format(item.collectedAmount),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      color: modeColor,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  'Bill No: ${item.billNumber}${item.bankName != null && item.bankName!.trim().isNotEmpty ? " • ${item.bankName!.trim()}" : ""} • ${item.routeName} • $timeStr',
                                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                showDialog(
                                  context: context,
                                  builder: (_) => CollectionDetailsDialog(collection: item),
                                );
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                if (mode == PaymentMode.cash) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.payments_rounded, size: 16),
                      label: const Text('Cash Counter'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CashHandoverScreen(
                              initialDate: provider.selectedDate,
                              initialBusiness: provider.filterBusiness,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.assessment_outlined, size: 16),
                    label: const Text('Full Statement'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      side: BorderSide(color: modeColor),
                      foregroundColor: modeColor,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StatementScreen(initialMode: mode),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _copyReport(BuildContext context) {
    final provider = context.read<CollectionProvider>();
    final report = provider.generateWhatsAppReportText();
    Clipboard.setData(ClipboardData(text: report));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('Report copied!')),
          ],
        ),
        backgroundColor: AppTheme.secondary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final provider = context.read<CollectionProvider>();
    final picked = await showDatePicker(
      context: context,
      initialDate: provider.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      provider.setSelectedDate(picked);
    }
  }

  void _showInstallInstructions(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.install_mobile_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Install Collection App', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add this app to your phone home screen for 1-tap quick access:',
              style: TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Android Phone (Chrome):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppTheme.primary)),
                  SizedBox(height: 4),
                  Text('1. Tap the 3 dots (⋮) at top-right of Chrome\n2. Tap "Install app" or "Add to Home screen"', style: TextStyle(fontSize: 12)),
                  SizedBox(height: 10),
                  Text('iPhone (Safari):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppTheme.primary)),
                  SizedBox(height: 4),
                  Text('1. Tap Share icon (square with arrow) at bottom\n2. Scroll down & tap "Add to Home Screen"', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.currentUser;
    final canAssign = currentUser?.canAssignRoutes == true;
    final canTally = currentUser?.canAccessTally == true;
    final canOrders = currentUser?.canAccessOrders == true;

    if (provider.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final dateStr = DateFormat('EEE, dd MMM yyyy').format(provider.selectedDate);
    final isToday = DateFormat('yyyy-MM-dd').format(provider.selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    final todayCollections = provider.getFilteredCollections();

    final purvaTotal = provider.getTotalCollectionForBusiness('Purva Enterprises');
    final purvaBills = provider.getBillsCountForBusiness('Purva Enterprises');
    final purvaPending = provider.getPendingBalanceForBusiness('Purva Enterprises');

    final manasTotal = provider.getTotalCollectionForBusiness('Manas Sales');
    final manasBills = provider.getBillsCountForBusiness('Manas Sales');
    final manasPending = provider.getPendingBalanceForBusiness('Manas Sales');

    final Color heroColor = provider.filterBusiness == 'Purva Enterprises'
        ? AppTheme.purvaPrimary
        : (provider.filterBusiness == 'Manas Sales'
            ? AppTheme.manasPrimary
            : AppTheme.primary);

    final String heroLabel = provider.filterBusiness == 'Purva Enterprises'
        ? 'PURVA ENTERPRISES COLLECTION'
        : (provider.filterBusiness == 'Manas Sales'
            ? 'MANAS SALES COLLECTION'
            : 'TOTAL COLLECTION TODAY');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        title: InkWell(
          onTap: () {
            if (onNavigateToProfile != null) {
              onNavigateToProfile!();
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.purvaLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.purvaBorder),
                  ),
                  child: const Center(
                    child: Icon(Icons.business_rounded, color: AppTheme.purvaPrimary, size: 18),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              context.watch<AuthProvider>().currentUser?.plainName ?? provider.salesmanName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AppTheme.manasLight,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.manasBorder),
                            ),
                            child: Text(
                              (currentUser?.isSuperAdmin == true)
                                  ? 'SUPER ADMIN'
                                  : (currentUser?.isOffice == true
                                      ? 'OFFICE'
                                      : (currentUser?.isCollection == true
                                          ? 'COLLECTION'
                                          : 'SALES & COLL')),
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.manasText,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Purva • Manas',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          // Live Payment Alert Bell with Red Notification Badge (Super Admin & Office Staff Only)
          if (context.watch<AuthProvider>().currentUser?.isSuperAdmin == true ||
              context.watch<AuthProvider>().currentUser?.isOffice == true)
            _PaymentAlertBell(provider: provider),
          IconButton(
            icon: const Icon(Icons.send_rounded, size: 20),
            tooltip: 'Send Bank Details',
            visualDensity: VisualDensity.compact,
            onPressed: () => FirmDetailsHelper.showQuickShareModal(
              context,
              defaultFirm: provider.filterBusiness,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_2_rounded, size: 22),
            tooltip: 'Payment QR',
            visualDensity: VisualDensity.compact,
            onPressed: () => PaymentQrDialog.show(context, initialFirm: provider.filterBusiness),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: 'More Options',
            onSelected: (val) async {
              if (val == 'book_orders') {
                if (onNavigateToOrders != null) {
                  onNavigateToOrders!();
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OrderDashboardScreen()),
                  );
                }
              } else if (val == 'all_orders') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AllOrdersScreen()),
                );
              } else if (val == 'live_map') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LiveStaffLocationsScreen()),
                );
              } else if (val == 'assign_driver_routes') {
                AssignRoutesDialog.show(context);
              } else if (val == 'bank_info') {
                FirmDetailsHelper.showQuickShareModal(
                  context,
                  defaultFirm: provider.filterBusiness,
                );
              } else if (val == 'install') {
                _showInstallInstructions(context);
              } else if (val == 'qr') {
                PaymentQrDialog.show(context, initialFirm: provider.filterBusiness);
              } else if (val == 'add_store') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddShopScreen()),
                );
              } else if (val == 'share') {
                _copyReport(context);
              } else if (val == 'sync_cloud' || val == 'sync') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Syncing with Supabase across all devices...'),
                    duration: Duration(seconds: 1),
                  ),
                );
                final ok = await provider.syncAllWithCloud(notify: true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Synced: ${provider.collections.length} collections, ${provider.pendingBills.length} bills, ${provider.allShops.length} outlets!'
                          : 'Sync failed: check internet connection'),
                      backgroundColor: ok ? const Color(0xFF10B981) : AppTheme.balanceDueColor,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } else if (val == 'reset') {
                provider.resetToSample();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Data reset done')),
                );
              }
            },
            itemBuilder: (ctx) => [
              if (context.read<AuthProvider>().currentUser?.canAccessOrders == true) ...[
                const PopupMenuItem(
                  value: 'book_orders',
                  child: Row(
                    children: [
                      Icon(Icons.store_mall_directory_rounded, size: 18, color: Color(0xFF1E3A8A)),
                      SizedBox(width: 10),
                      Text('Book Orders'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'all_orders',
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_rounded, size: 18, color: Color(0xFF1E3A8A)),
                      SizedBox(width: 10),
                      Text('All Booked Orders'),
                    ],
                  ),
                ),
              ],
              if (context.read<AuthProvider>().currentUser?.isSuperAdmin == true) ...[
                const PopupMenuItem(
                  value: 'live_map',
                  child: Row(
                    children: [
                      Icon(Icons.route_rounded, size: 18, color: Color(0xFF2563EB)),
                      SizedBox(width: 10),
                      Text('Staff Timeline & Live GPS'),
                    ],
                  ),
                ),
              ],
              if (context.read<AuthProvider>().currentUser?.canAssignRoutes == true) ...[
                const PopupMenuItem(
                  value: 'assign_driver_routes',
                  child: Row(
                    children: [
                      Icon(Icons.alt_route_rounded, size: 18, color: Color(0xFF0D9488)),
                      SizedBox(width: 10),
                      Text('Assign Routes'),
                    ],
                  ),
                ),
              ],
              const PopupMenuItem(
                value: 'bank_info',
                child: Row(
                  children: [
                    Icon(Icons.send_rounded, size: 18, color: Color(0xFF25D366)),
                    SizedBox(width: 10),
                    Text('Send Payment Info'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'install',
                child: Row(
                  children: [
                    Icon(Icons.install_mobile_rounded, size: 18, color: Color(0xFF10B981)),
                    SizedBox(width: 10),
                    Text('Install App (PWA)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'qr',
                child: Row(
                  children: [
                    Icon(Icons.qr_code_2_rounded, size: 18, color: AppTheme.primary),
                    SizedBox(width: 10),
                    Text('Payment QR Code'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'sync_cloud',
                child: Row(
                  children: [
                    Icon(Icons.sync_rounded, size: 18, color: Color(0xFF10B981)),
                    SizedBox(width: 10),
                    Text('Sync Now (All Devices)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add_store',
                child: Row(
                  children: [
                    Icon(Icons.add_business_outlined, size: 18, color: AppTheme.secondary),
                    SizedBox(width: 10),
                    Text('Add Outlet'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share_outlined, size: 18, color: AppTheme.primary),
                    SizedBox(width: 10),
                    Text('Share Report'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 18, color: Colors.blueGrey),
                    SizedBox(width: 10),
                    Text('Reset Data'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Integrated Sub-Header Control Bar (Segmented Firm Switcher + Compact Date + Sync)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                // Compact Segmented Firm Pill
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppTheme.subtleSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        _buildFirmTabPill(
                          label: 'All',
                          isSelected: provider.filterBusiness == null,
                          activeColor: AppTheme.primary,
                          onTap: () => provider.setFilterBusiness(null),
                        ),
                        _buildFirmTabPill(
                          label: 'Purva',
                          isSelected: provider.filterBusiness == 'Purva Enterprises',
                          activeColor: AppTheme.purvaPrimary,
                          onTap: () => provider.setFilterBusiness('Purva Enterprises'),
                        ),
                        _buildFirmTabPill(
                          label: 'Manas',
                          isSelected: provider.filterBusiness == 'Manas Sales',
                          activeColor: AppTheme.manasPrimary,
                          onTap: () => provider.setFilterBusiness('Manas Sales'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Date Pill
                InkWell(
                  onTap: () => _pickDate(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isToday ? AppTheme.subtleSurface : AppTheme.chequeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isToday ? AppTheme.border : AppTheme.chequeColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: isToday ? AppTheme.primary : AppTheme.chequeColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isToday ? 'Today' : DateFormat('dd MMM').format(provider.selectedDate),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isToday ? AppTheme.primary : AppTheme.chequeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Compact Live Cloud Sync Status Button
                InkWell(
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Syncing data across devices...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                    final ok = await provider.syncAllWithCloud(notify: true);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok
                              ? 'Synced ${provider.collections.length} collections & ${provider.pendingBills.length} bills'
                              : 'Offline cache active'),
                          backgroundColor: ok ? AppTheme.manasPrimary : AppTheme.textSecondary,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Tooltip(
                    message: provider.isCloudConnected ? 'Cloud Synced' : 'Offline Cache',
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: provider.isCloudConnected
                            ? AppTheme.manasLight
                            : AppTheme.subtleSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: provider.isCloudConnected
                              ? AppTheme.manasBorder
                              : AppTheme.border,
                        ),
                      ),
                      child: provider.isSyncing
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.manasPrimary),
                              ),
                            )
                          : Icon(
                              provider.isCloudConnected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                              size: 16,
                              color: provider.isCloudConnected ? AppTheme.manasPrimary : AppTheme.textSecondary,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable Editorial Dashboard Body
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => provider.syncAllWithCloud(notify: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  // 2. Signature White Architectural Summary Card
                  _buildEditorialSummaryCard(
                    context: context,
                    provider: provider,
                    heroColor: heroColor,
                    heroLabel: heroLabel,
                    dateStr: dateStr,
                    isToday: isToday,
                  ),

                  // 3. Firm Split Bar (Compact side-by-side when viewing All Firms)
                  if (provider.filterBusiness == null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFirmMiniSplitCard(
                            tag: 'PURVA',
                            amount: purvaTotal,
                            pendingAmount: purvaPending,
                            billsCount: purvaBills,
                            accentColor: AppTheme.purvaPrimary,
                            onTap: () => provider.setFilterBusiness('Purva Enterprises'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildFirmMiniSplitCard(
                            tag: 'MANAS',
                            amount: manasTotal,
                            pendingAmount: manasPending,
                            billsCount: manasBills,
                            accentColor: AppTheme.manasPrimary,
                            onTap: () => provider.setFilterBusiness('Manas Sales'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),

                  // 4. Primary Split CTA Row (Single-Line Sharp Buttons, Zero Subheadings)
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: heroColor,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const MakeCollectionScreen()),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.payments_outlined, color: Colors.white, size: 19),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Collection',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const PendingBillsListScreen()),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF0284C7), width: 1.4),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.receipt_long_outlined, color: Color(0xFF0284C7), size: 19),
                                  const SizedBox(width: 7),
                                  const Flexible(
                                    child: Text(
                                      'Pending Bills',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${provider.pendingBills.where((b) => !b.isPaid).length}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0369A1),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 5. Grouped Field Operations List Card (Zero Subheadings, Clean Hairlines)
                  const CleanSectionHeader(title: 'Field Tools'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      children: [
                        _buildToolRow(
                          title: 'Upload Bill',
                          icon: Icons.add_photo_alternate_outlined,
                          color: const Color(0xFF0284C7),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const AddPendingBillScreen()),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        _buildToolRow(
                          title: 'Statement',
                          icon: Icons.assessment_outlined,
                          color: const Color(0xFF4F46E5),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const StatementScreen()),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        _buildToolRow(
                          title: 'Cash Counter',
                          icon: Icons.payments_rounded,
                          color: AppTheme.manasPrimary,
                          trailingValue: CurrencyFormatter.format(provider.totalCash),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CashHandoverScreen(
                                  initialDate: provider.selectedDate,
                                  initialBusiness: provider.filterBusiness,
                                ),
                              ),
                            );
                          },
                        ),
                        if (canOrders) ...[
                          const Divider(height: 1),
                          _buildToolRow(
                            title: 'Book Orders',
                            icon: Icons.shopping_bag_outlined,
                            color: AppTheme.purvaPrimary,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const OrderDashboardScreen()),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          _buildToolRow(
                            title: 'All Booked Orders',
                            icon: Icons.receipt_long_outlined,
                            color: AppTheme.purvaPrimary,
                            trailingValue: '${provider.salesOrders.length}',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AllOrdersScreen()),
                              );
                            },
                          ),
                        ],
                        if (currentUser?.isSuperAdmin == true) ...[
                          const Divider(height: 1),
                          _buildToolRow(
                            title: 'Live Staff Tracking',
                            icon: Icons.share_location_outlined,
                            color: const Color(0xFF2563EB),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const LiveStaffLocationsScreen()),
                              );
                            },
                          ),
                        ],
                        if (canAssign) ...[
                          const Divider(height: 1),
                          _buildToolRow(
                            title: 'Assign Routes',
                            icon: Icons.alt_route_rounded,
                            color: AppTheme.manasPrimary,
                            onTap: () => AssignRoutesDialog.show(context),
                          ),
                        ],
                        if (canTally) ...[
                          const Divider(height: 1),
                          _buildToolRow(
                            title: 'Tally Hub',
                            icon: Icons.swap_horiz_rounded,
                            color: const Color(0xFF0284C7),
                            onTap: () => TallySyncDialog.show(context),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 6. Recent Receipts Feed on Home Dashboard
                  CleanSectionHeader(
                    title: isToday ? 'Recent Collections' : 'Receipts ($dateStr)',
                    trailing: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: onNavigateToCollections,
                      child: Text(
                        'View Ledger',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: heroColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildRecentReceiptsCard(context, todayCollections, heroColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirmTabPill({
    required String label,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorialSummaryCard({
    required BuildContext context,
    required CollectionProvider provider,
    required Color heroColor,
    required String heroLabel,
    required String dateStr,
    required bool isToday,
  }) {
    final total = provider.totalCollection;
    final cash = provider.totalCash;
    final upi = provider.totalUpi;
    final cheque = provider.totalCheque;
    final netBank = provider.totalNetBanking;
    final invoiced = provider.totalBillAmount;
    final recoveryPct = invoiced > 0 ? ((total / invoiced) * 100).clamp(0, 100).round() : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Accent Stripe
          Container(height: 4, color: heroColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        heroLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: onNavigateToCollections,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: heroColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${provider.totalBillsCount} ${provider.totalBillsCount == 1 ? 'Invoice' : 'Invoices'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: heroColor,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.arrow_forward_ios, size: 9, color: heroColor),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Main Metric Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onNavigateToCollections,
                        child: Text(
                          CurrencyFormatter.format(total),
                          style: AppTheme.tabularAmount(
                            color: AppTheme.primary,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                          ),
                        ),
                      ),
                    ),
                    if (invoiced > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.manasLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.manasBorder),
                        ),
                        child: Text(
                          '$recoveryPct% Collected',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.manasText,
                          ),
                        ),
                      )
                    else
                      Text(
                        isToday ? dateStr : DateFormat('dd MMM yyyy').format(provider.selectedDate),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Stacked Payment Mode Ratio Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 6,
                    child: total <= 0
                        ? Container(color: AppTheme.subtleSurface)
                        : Row(
                            children: [
                              if (cash > 0)
                                Expanded(
                                  flex: (cash * 100).round().clamp(1, 1000000),
                                  child: Container(color: AppTheme.cashColor),
                                ),
                              if (upi > 0)
                                Expanded(
                                  flex: (upi * 100).round().clamp(1, 1000000),
                                  child: Container(color: AppTheme.upiColor),
                                ),
                              if (cheque > 0)
                                Expanded(
                                  flex: (cheque * 100).round().clamp(1, 1000000),
                                  child: Container(color: AppTheme.chequeColor),
                                ),
                              if (netBank > 0)
                                Expanded(
                                  flex: (netBank * 100).round().clamp(1, 1000000),
                                  child: Container(color: AppTheme.netBankingColor),
                                ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                // 3-Column Financial KPI Strip
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onNavigateToCollections,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Invoiced', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                CurrencyFormatter.format(invoiced),
                                style: AppTheme.tabularAmount(fontSize: 14, color: AppTheme.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(width: 1, height: 28, color: AppTheme.border),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PendingBillsListScreen()),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pending Due', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                CurrencyFormatter.format(provider.totalBalanceDue),
                                style: AppTheme.tabularAmount(
                                  fontSize: 14,
                                  color: provider.totalBalanceDue > 0 ? AppTheme.balanceDueColor : AppTheme.cashColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(width: 1, height: 28, color: AppTheme.border),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: onNavigateToRoutes,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Visited', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${provider.uniqueShopsCount}',
                              style: AppTheme.tabularAmount(fontSize: 14, color: AppTheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Footer 4-Column Payment Modes Strip (Integrated Inside Hero Card)
          Container(
            decoration: const BoxDecoration(
              color: AppTheme.background,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                _buildInlineModeStat(
                  label: 'Cash',
                  amount: cash,
                  color: AppTheme.cashColor,
                  onTap: () => _showModeBillsSheet(context, provider, PaymentMode.cash),
                ),
                _buildInlineModeStat(
                  label: 'UPI',
                  amount: upi,
                  color: AppTheme.upiColor,
                  onTap: () => _showModeBillsSheet(context, provider, PaymentMode.upi),
                ),
                _buildInlineModeStat(
                  label: 'Cheque',
                  amount: cheque,
                  color: AppTheme.chequeColor,
                  onTap: () => _showModeBillsSheet(context, provider, PaymentMode.cheque),
                ),
                _buildInlineModeStat(
                  label: 'Bank',
                  amount: netBank,
                  color: AppTheme.netBankingColor,
                  onTap: () => _showModeBillsSheet(context, provider, PaymentMode.netBanking),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineModeStat({
    required String label,
    required double amount,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  CurrencyFormatter.format(amount),
                  style: AppTheme.tabularAmount(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: amount > 0 ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFirmMiniSplitCard({
    required String tag,
    required double amount,
    required double pendingAmount,
    required int billsCount,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tag,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: accentColor,
                          ),
                        ),
                        Text(
                          '$billsCount ${billsCount == 1 ? 'bill' : 'bills'}',
                          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            CurrencyFormatter.format(amount),
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.tabularAmount(fontSize: 14, color: AppTheme.primary),
                          ),
                        ),
                        if (pendingAmount > 0)
                          Text(
                            'Due ${CurrencyFormatter.format(pendingAmount)}',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.balanceDueColor,
                            ),
                          ),
                      ],
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

  Widget _buildToolRow({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? trailingValue,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
            if (trailingValue != null) ...[
              Text(
                trailingValue,
                style: AppTheme.tabularAmount(fontSize: 13, fontWeight: FontWeight.w700, color: color),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentReceiptsCard(BuildContext context, List<dynamic> collections, Color heroColor) {
    if (collections.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.subtleSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_outlined, size: 18, color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No receipts recorded for this date yet',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final recent = List.of(collections)..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
    final visible = recent.take(3).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          for (int i = 0; i < visible.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => CollectionDetailsDialog(collection: visible[i]),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTheme.manasLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppTheme.manasPrimary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            visible[i].shopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary),
                          ),
                          Text(
                            'Bill #${visible[i].billNumber} • ${visible[i].paymentMode.displayName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      CurrencyFormatter.format(visible[i].collectedAmount),
                      style: AppTheme.tabularAmount(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppTheme.manasPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT ALERT BELL WITH RED NOTIFICATION BADGE (Super Admin & Office Staff)
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentAlertBell extends StatefulWidget {
  final CollectionProvider provider;
  const _PaymentAlertBell({required this.provider});

  @override
  State<_PaymentAlertBell> createState() => _PaymentAlertBellState();
}

class _PaymentAlertBellState extends State<_PaymentAlertBell> {
  DateTime? _lastSeenTime;
  static const _seenKey = 'last_seen_payment_alert_time';

  @override
  void initState() {
    super.initState();
    _loadLastSeen();
  }

  Future<void> _loadLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_seenKey);
    if (s != null && s.isNotEmpty) {
      final dt = DateTime.tryParse(s);
      if (mounted) setState(() => _lastSeenTime = dt);
    }
  }

  Future<void> _markSeen() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seenKey, now.toIso8601String());
    if (mounted) setState(() => _lastSeenTime = now);
  }

  int _calculateUnreadCount() {
    final now = DateTime.now();
    final todayCollections = widget.provider.collections.where((c) {
      return c.collectedAt.year == now.year &&
          c.collectedAt.month == now.month &&
          c.collectedAt.day == now.day;
    }).toList();

    if (_lastSeenTime == null) {
      return todayCollections.length;
    }
    return todayCollections.where((c) => c.collectedAt.isAfter(_lastSeenTime!)).length;
  }

  @override
  Widget build(BuildContext context) {
    final unread = _calculateUnreadCount();

    return IconButton(
      tooltip: 'Live Payment Alerts',
      visualDensity: VisualDensity.compact,
      onPressed: () {
        _markSeen();
        _showPaymentAlertsSheet(context, widget.provider);
      },
      icon: unread > 0
          ? Badge.count(
              count: unread,
              backgroundColor: const Color(0xFFEF4444), // Red notification badge
              textColor: Colors.white,
              textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
              child: const Icon(Icons.notifications_active_rounded, size: 22, color: Color(0xFFD97706)),
            )
          : const Icon(Icons.notifications_outlined, size: 22, color: AppTheme.primary),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GOOGLE PAY FOR BUSINESS STYLE PAYMENT ALERTS SHEET
// ─────────────────────────────────────────────────────────────────────────────
void _showPaymentAlertsSheet(BuildContext context, CollectionProvider provider) {
  DateTime selectedDate = provider.selectedDate;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final isToday = selectedDate.year == DateTime.now().year &&
              selectedDate.month == DateTime.now().month &&
              selectedDate.day == DateTime.now().day;

          // Filter collections for selected date (all businesses, latest first)
          final dayCollections = provider.collections.where((c) {
            return c.collectedAt.year == selectedDate.year &&
                c.collectedAt.month == selectedDate.month &&
                c.collectedAt.day == selectedDate.day;
          }).toList()
            ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));

          final double totalReceived =
              dayCollections.fold(0.0, (sum, c) => sum + c.collectedAmount);

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    // Drag Handle
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 42,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),

                    // Top Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF86EFAC)),
                            ),
                            child: const Center(
                              child: Icon(Icons.notifications_active_rounded,
                                  color: Color(0xFF15803D), size: 20),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Payment Alerts',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  'Google Pay / Business Live Feed',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Date Picker Pill (defaults to today/selected date, tap to pick ANY date)
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2023),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setSheetState(() => selectedDate = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppTheme.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today_rounded,
                                      size: 13, color: AppTheme.primary),
                                  const SizedBox(width: 5),
                                  Text(
                                    isToday ? 'Today' : DateFormat('dd MMM').format(selectedDate),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down,
                                      size: 16, color: Colors.blueGrey),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20, color: Colors.blueGrey),
                            onPressed: () => Navigator.pop(ctx),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),

                    // Total Received Summary Banner (Google Pay for Business style)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF064E3B), Color(0xFF047857)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF047857).withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'TOTAL RECEIVED',
                                      style: TextStyle(
                                        color: Color(0xFFA7F3D0),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      DateFormat('dd MMM yyyy').format(selectedDate),
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  CurrencyFormatter.format(totalReceived),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '${dayCollections.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const Text(
                                    'Payments',
                                    style: TextStyle(
                                      color: Color(0xFFA7F3D0),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Payments List
                    Expanded(
                      child: dayCollections.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.receipt_long_outlined,
                                        size: 48, color: Colors.blueGrey.shade300),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No payments received on ${DateFormat('dd MMM yyyy').format(selectedDate)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Color(0xFF0F172A)),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'When payments are recorded via UPI, Cash, or Cheque, they will appear here live with outlet names and amounts.',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.blueGrey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: dayCollections.length,
                              itemBuilder: (context, index) {
                                final coll = dayCollections[index];
                                final timeStr = DateFormat('hh:mm a').format(coll.collectedAt);
                                final isUpi = coll.paymentMode == PaymentMode.upi;
                                final isCash = coll.paymentMode == PaymentMode.cash;
                                final modeColor = isUpi
                                    ? const Color(0xFF0284C7)
                                    : (isCash ? const Color(0xFF16A34A) : Colors.orange);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.border),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.03),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                    leading: CircleAvatar(
                                      radius: 20,
                                      backgroundColor: const Color(0xFFDCFCE7),
                                      child: const Icon(
                                        Icons.arrow_downward_rounded,
                                        color: Color(0xFF16A34A),
                                        size: 20,
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            coll.shopName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Color(0xFF0F172A),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '+ ${CurrencyFormatter.format(coll.collectedAmount)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14.5,
                                            color: Color(0xFF16A34A),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              timeStr,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.blueGrey.shade700,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: modeColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                coll.paymentMode.name.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: modeColor,
                                                ),
                                              ),
                                            ),
                                            if (coll.bankName != null && coll.bankName!.trim().isNotEmpty) ...[
                                              const SizedBox(width: 5),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 5, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: Colors.blueGrey.shade100,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  coll.bankName!.trim(),
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.blueGrey.shade800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(width: 6),
                                            Text(
                                              'Bill #${coll.billNumber}',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: Colors.blueGrey.shade500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Collected by ${coll.salesmanName} • ${coll.businessName}',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.blueGrey.shade600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}
