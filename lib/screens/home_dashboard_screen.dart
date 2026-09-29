import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/collection_provider.dart';
import '../models/payment_mode.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import 'record_collection_screen.dart';
import 'collection_details_dialog.dart';
import 'collections_list_screen.dart';
import 'add_shop_screen.dart';
import 'firebase_config_dialog.dart';

class HomeDashboardScreen extends StatelessWidget {
  final VoidCallback onNavigateToRoutes;
  final VoidCallback onNavigateToCollections;

  const HomeDashboardScreen({
    super.key,
    required this.onNavigateToRoutes,
    required this.onNavigateToCollections,
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
            Expanded(child: Text('Collection summary copied to clipboard!')),
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();

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
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: const Center(
                child: Icon(Icons.person_outline, color: Colors.white, size: 20),
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
                          provider.salesmanName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'OFFICER',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF34D399),
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Purva Enterprises • Manas Sales',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined, size: 20),
            tooltip: 'Select Date',
            onPressed: () => _pickDate(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: 'More Options',
            onSelected: (val) async {
              if (val == 'add_store') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddShopScreen()),
                );
              } else if (val == 'share') {
                _copyReport(context);
              } else if (val == 'sync_cloud') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Syncing all records to Firebase Cloud Firestore...')),
                );
                final ok = await provider.syncAllToCloud();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Synced ${provider.collections.length} collections and ${provider.shops.length} stores to Firestore!'
                          : 'Sync failed: check connection'),
                      backgroundColor: ok ? const Color(0xFF10B981) : AppTheme.balanceDueColor,
                    ),
                  );
                }
              } else if (val == 'firebase') {
                showDialog(
                  context: context,
                  builder: (_) => const FirebaseConfigDialog(),
                );
              } else if (val == 'reset') {
                provider.resetToSample();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sample demo data reloaded')),
                );
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'sync_cloud',
                child: Row(
                  children: [
                    Icon(Icons.cloud_upload_outlined, size: 18, color: Color(0xFF10B981)),
                    SizedBox(width: 10),
                    Text('Sync All to Firebase'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add_store',
                child: Row(
                  children: [
                    Icon(Icons.add_business_outlined, size: 18, color: AppTheme.secondary),
                    SizedBox(width: 10),
                    Text('Add Store / Customer'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share_outlined, size: 18, color: AppTheme.primary),
                    SizedBox(width: 10),
                    Text('Share Daily Summary'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'firebase',
                child: Row(
                  children: [
                    Icon(
                      provider.isFirebaseConnected ? Icons.cloud_done : Icons.cloud_sync,
                      size: 18,
                      color: provider.isFirebaseConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 10),
                    Text(provider.isFirebaseConnected ? 'Firebase (Connected)' : 'Firebase Cloud Sync'),
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
                    Text('Reload Sample Data'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => provider.initialize(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Date Indicator & Business Pills Row
              Row(
                children: [
                  InkWell(
                    onTap: () => _pickDate(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_month_outlined,
                            size: 15,
                            color: isToday ? AppTheme.primary : AppTheme.chequeColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isToday ? 'Today: $dateStr' : dateStr,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isToday ? AppTheme.primary : AppTheme.chequeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => const FirebaseConfigDialog(),
                    ),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: provider.isFirebaseConnected
                            ? const Color(0xFF10B981).withValues(alpha: 0.1)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: provider.isFirebaseConnected
                              ? const Color(0xFF10B981).withValues(alpha: 0.3)
                              : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            provider.isFirebaseConnected ? Icons.cloud_done : Icons.cloud_queue,
                            size: 14,
                            color: provider.isFirebaseConnected ? const Color(0xFF059669) : Colors.blueGrey,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            provider.isFirebaseConnected ? 'Cloud Synced' : 'Offline Mode',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: provider.isFirebaseConnected ? const Color(0xFF059669) : Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!isToday)
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => provider.setSelectedDate(DateTime.now()),
                      child: const Text('Return to Today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // High-Visibility Dual-Firm Quick Switcher Bar
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    // All Firms / Combined Option
                    Expanded(
                      child: InkWell(
                        onTap: () => provider.setFilterBusiness(null),
                        borderRadius: BorderRadius.circular(7),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: provider.filterBusiness == null ? AppTheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'ALL FIRMS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: provider.filterBusiness == null ? Colors.white : Colors.blueGrey.shade800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                CurrencyFormatter.format(purvaTotal + manasTotal),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: provider.filterBusiness == null ? Colors.white70 : Colors.blueGrey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Purva Enterprises Option
                    Expanded(
                      child: InkWell(
                        onTap: () => provider.setFilterBusiness('Purva Enterprises'),
                        borderRadius: BorderRadius.circular(7),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: provider.filterBusiness == 'Purva Enterprises'
                                ? AppTheme.purvaPrimary
                                : AppTheme.purvaLight,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: provider.filterBusiness == 'Purva Enterprises'
                                  ? AppTheme.purvaPrimary
                                  : AppTheme.purvaBorder,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'PURVA',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: provider.filterBusiness == 'Purva Enterprises'
                                      ? Colors.white
                                      : AppTheme.purvaText,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                CurrencyFormatter.format(purvaTotal),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: provider.filterBusiness == 'Purva Enterprises'
                                      ? Colors.white70
                                      : AppTheme.purvaText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Manas Sales Option
                    Expanded(
                      child: InkWell(
                        onTap: () => provider.setFilterBusiness('Manas Sales'),
                        borderRadius: BorderRadius.circular(7),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: provider.filterBusiness == 'Manas Sales'
                                ? AppTheme.manasPrimary
                                : AppTheme.manasLight,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: provider.filterBusiness == 'Manas Sales'
                                  ? AppTheme.manasPrimary
                                  : AppTheme.manasBorder,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'MANAS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: provider.filterBusiness == 'Manas Sales'
                                      ? Colors.white
                                      : AppTheme.manasText,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                CurrencyFormatter.format(manasTotal),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: provider.filterBusiness == 'Manas Sales'
                                      ? Colors.white70
                                      : AppTheme.manasText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Side-by-Side Dual-Firm Overview Cards (shown when 'All' is active)
              if (provider.filterBusiness == null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Purva Card
                    Expanded(
                      child: InkWell(
                        onTap: () => provider.setFilterBusiness('Purva Enterprises'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.purvaBorder, width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.purvaLight,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'PURVA',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.purvaText,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 10, color: AppTheme.purvaText),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Purva Enterprises',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                CurrencyFormatter.format(purvaTotal),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.purvaPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '$purvaBills bills',
                                    style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                                  ),
                                  if (purvaPending > 0)
                                    Text(
                                      'Due: ${CurrencyFormatter.format(purvaPending)}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.balanceDueColor,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Manas Card
                    Expanded(
                      child: InkWell(
                        onTap: () => provider.setFilterBusiness('Manas Sales'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.manasBorder, width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.manasLight,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'MANAS',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.manasText,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 10, color: AppTheme.manasText),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Manas Sales',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                CurrencyFormatter.format(manasTotal),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.manasPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '$manasBills bills',
                                    style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                                  ),
                                  Text(
                                    manasPending > 0
                                        ? 'Due: ${CurrencyFormatter.format(manasPending)}'
                                        : 'All Paid',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: manasPending > 0 ? AppTheme.balanceDueColor : AppTheme.cashColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // Active Firm Indicator (when a single firm is selected)
              if (provider.filterBusiness != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.getBusinessLightColor(provider.filterBusiness!),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.getBusinessBorderColor(provider.filterBusiness!)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.business_outlined, size: 16, color: AppTheme.getBusinessColor(provider.filterBusiness!)),
                          const SizedBox(width: 8),
                          Text(
                            'Active Firm: ${provider.filterBusiness}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.getBusinessColor(provider.filterBusiness!),
                            ),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: () => provider.setFilterBusiness(null),
                        child: Row(
                          children: [
                            Text(
                              'Show Both',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.getBusinessColor(provider.filterBusiness!),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.close, size: 14, color: AppTheme.getBusinessColor(provider.filterBusiness!)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Executive Financial Overview Hero Card (dynamically branded by firm)
              Container(
                decoration: BoxDecoration(
                  color: heroColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: heroColor.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          heroLabel,
                          style: TextStyle(
                            color: Colors.blueGrey.shade200,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${provider.totalBillsCount} Invoices',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      CurrencyFormatter.format(provider.totalCollection),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Financial metrics row: Total Invoiced vs Pending Balance
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TOTAL INVOICED',
                                style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                CurrencyFormatter.format(provider.totalBillAmount),
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          Container(width: 1, height: 26, color: Colors.white.withValues(alpha: 0.2)),
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CollectionsListScreen(initialTabIndex: 1),
                                ),
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'BALANCE PENDING',
                                      style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.arrow_forward_ios, size: 10, color: Colors.white70),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  CurrencyFormatter.format(provider.totalBalanceDue),
                                  style: TextStyle(
                                    color: provider.totalBalanceDue > 0 ? const Color(0xFFFCA5A5) : Colors.greenAccent,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 26, color: Colors.white.withValues(alpha: 0.2)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'STORES VISITED',
                                style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${provider.uniqueShopsCount}',
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Pending Invoices Alert Section (if any bills pending)
              Builder(
                builder: (context) {
                  final pendingBills = provider.getPendingBills(forBusiness: provider.filterBusiness);
                  if (pendingBills.isEmpty) return const SizedBox.shrink();

                  final totalDue = pendingBills.fold(0.0, (s, b) => s + b.balanceDue);

                  return Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.pending_actions_outlined, size: 18, color: Color(0xFFD97706)),
                                const SizedBox(width: 8),
                                Text(
                                  'PENDING INVOICES (${pendingBills.length})',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF92400E),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD97706),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Due: ${CurrencyFormatter.format(totalDue)}',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...pendingBills.take(2).map((bill) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        bill.shopName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Text(
                                            'Invoice #${bill.billNumber}',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade800),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppTheme.getBusinessLightColor(bill.businessName),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: AppTheme.getBusinessBorderColor(bill.businessName), width: 0.8),
                                            ),
                                            child: Text(
                                              bill.businessName == 'Purva Enterprises' ? 'PURVA' : (bill.businessName == 'Manas Sales' ? 'MANAS' : bill.businessName),
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: AppTheme.getBusinessTextColor(bill.businessName),
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        'Billed: ${CurrencyFormatter.format(bill.billTotal)} • Due: ${CurrencyFormatter.format(bill.balanceDue)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.balanceDueColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.add, size: 13),
                                  label: const Text('Collect'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD97706),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    elevation: 0,
                                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RecordCollectionScreen(
                                          initialShopId: bill.shopId,
                                          initialBillNumber: bill.billNumber,
                                          initialBillTotal: bill.billTotal,
                                          initialBalanceDue: bill.balanceDue,
                                          initialBusiness: bill.businessName,
                                          isFollowUp: true,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CollectionsListScreen(initialTabIndex: 1),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'View All ${pendingBills.length} Pending Invoices',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward, size: 14, color: Color(0xFF92400E)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // End-of-Day 4 Payment Method Breakdown
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Reconciliation by Payment Mode',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    'End of Day Tally',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 2x2 Grid for the 4 modes with professional vector icons
              Row(
                children: [
                  Expanded(
                    child: _buildModeCard(
                      label: 'Cash in Hand',
                      amount: provider.totalCash,
                      icon: Icons.payments_outlined,
                      accentColor: AppTheme.cashColor,
                      billsCount: todayCollections.where((c) => c.paymentMode == PaymentMode.cash).length,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildModeCard(
                      label: 'UPI / Digital QR',
                      amount: provider.totalUpi,
                      icon: Icons.qr_code_2_rounded,
                      accentColor: AppTheme.upiColor,
                      billsCount: todayCollections.where((c) => c.paymentMode == PaymentMode.upi).length,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildModeCard(
                      label: 'Cheque Payment',
                      amount: provider.totalCheque,
                      icon: Icons.fact_check_outlined,
                      accentColor: AppTheme.chequeColor,
                      billsCount: todayCollections.where((c) => c.paymentMode == PaymentMode.cheque).length,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildModeCard(
                      label: 'Net Banking (IMPS/NEFT)',
                      amount: provider.totalNetBanking,
                      icon: Icons.account_balance_outlined,
                      accentColor: AppTheme.netBankingColor,
                      billsCount: todayCollections.where((c) => c.paymentMode == PaymentMode.netBanking).length,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Quick Action Buttons (Balanced 50/50 Prominent Actions)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text(
                        'Record Payment',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 1.5,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RecordCollectionScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_business_outlined, size: 18),
                      label: const Text(
                        'Add Store',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondary,
                        foregroundColor: Colors.white,
                        elevation: 1.5,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AddShopScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Today's Collections Section Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recorded Collections (${todayCollections.length})',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.share_outlined, size: 14, color: AppTheme.secondary),
                        label: const Text(
                          'Share',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.secondary),
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        onPressed: () => _copyReport(context),
                      ),
                      const SizedBox(width: 2),
                      TextButton(
                        onPressed: onNavigateToCollections,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        child: const Text('View All', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),

              if (todayCollections.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 40, color: Colors.blueGrey.shade300),
                        const SizedBox(height: 10),
                        Text(
                          'No payment collections recorded for this date',
                          style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Record First Payment'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RecordCollectionScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: todayCollections.length > 5 ? 5 : todayCollections.length,
                  itemBuilder: (context, index) {
                    final item = todayCollections[index];
                    final modeColor = _getModeColor(item.paymentMode);
                    final time = DateFormat('hh:mm a').format(item.collectedAt);
                    final isPartial = item.isPartial;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => CollectionDetailsDialog(collection: item),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: modeColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Icon(
                                    item.paymentMode.icon,
                                    size: 20,
                                    color: modeColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.shopName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: Color(0xFF0F172A),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (item.photoBase64 != null)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 4.0),
                                            child: Icon(Icons.attach_file, size: 14, color: Colors.blueGrey),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.getBusinessLightColor(item.businessName),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: AppTheme.getBusinessBorderColor(item.businessName),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            item.businessName == 'Purva Enterprises' ? 'PURVA' : (item.businessName == 'Manas Sales' ? 'MANAS' : item.businessName),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.getBusinessTextColor(item.businessName),
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Bill: ${item.billNumber}',
                                          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          '${item.routeName} • $time',
                                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade400),
                                        ),
                                        if (isPartial) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppTheme.chequeColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              'Due: ${CurrencyFormatter.format(item.balanceAmount)}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.partialBadgeColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    CurrencyFormatter.format(item.collectedAmount),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: modeColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: modeColor.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.paymentMode.label,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: modeColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

              if (todayCollections.length > 5) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: onNavigateToCollections,
                    child: Text('View remaining ${todayCollections.length - 5} records'),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required String label,
    required double amount,
    required IconData icon,
    required Color accentColor,
    required int billsCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$billsCount',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.blueGrey.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.blueGrey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            CurrencyFormatter.format(amount),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}
