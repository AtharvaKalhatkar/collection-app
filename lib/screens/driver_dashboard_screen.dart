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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openGoogleMaps(ShopModel shop) async {
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

    final amountCtrl = TextEditingController(
      text: bill.balanceDue.toStringAsFixed(0),
    );
    PaymentMode selectedMode = PaymentMode.cash;

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.payments_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Collect Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(bill.shopName, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
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
                          const Text('Invoice #:', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                          Text(bill.billNumber, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Bill Total:', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                          Text(CurrencyFormatter.format(bill.totalAmount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Balance Due:', style: TextStyle(fontSize: 12, color: Colors.red)),
                          Text(
                            CurrencyFormatter.format(bill.balanceDue),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.red),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Collected Amount (₹)',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Payment Mode:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [PaymentMode.cash, PaymentMode.upi, PaymentMode.cheque].map((mode) {
                    final isSel = selectedMode == mode;
                    return ChoiceChip(
                      label: Text(mode.label),
                      selected: isSel,
                      selectedColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        color: isSel ? Colors.white : Colors.black87,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      onSelected: (val) {
                        if (val) setDlgState(() => selectedMode = mode);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid collection amount')),
                  );
                  return;
                }

                Navigator.pop(dlgCtx);

                // Record payment in provider
                await provider.recordCollectionForPendingBill(
                  pendingBill: bill,
                  collectedAmount: amount,
                  paymentMode: selectedMode,
                  collectionDate: DateTime.now(),
                );

                if (!context.mounted) return;

                // Show 2-Factor verification receipt for customer
                final remaining = (bill.balanceDue - amount) > 0 ? (bill.balanceDue - amount) : 0.0;
                final driverName = currentUser?.name ?? 'user1';
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
              child: const Text('Save & Verify', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.phone, size: 16, color: Color(0xFF10B981)),
                        label: const Text('Call', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                        onPressed: () => _callPhone(shop.mobileNumber),
                      ),
                    ],
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
