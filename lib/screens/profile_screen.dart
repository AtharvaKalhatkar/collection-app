import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/collection_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/firm_details.dart';
import '../utils/theme.dart';
import '../widgets/payment_qr_dialog.dart';
import 'statement_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _showEditProfileDialog(BuildContext context, CollectionProvider provider) {
    final nameCtrl = TextEditingController(text: provider.salesmanName);
    final phoneCtrl = TextEditingController(text: provider.salesmanPhone);
    final roleCtrl = TextEditingController(text: provider.salesmanRole);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Edit Officer Profile',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Officer Name',
                hintText: 'e.g. Akash',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                hintText: 'e.g. 9822012345',
                prefixIcon: const Icon(Icons.phone_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: roleCtrl,
              decoration: InputDecoration(
                labelText: 'Designation / Role',
                hintText: 'e.g. Collection & Sales Executive',
                prefixIcon: const Icon(Icons.badge_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await provider.updateProfile(
                  name: nameCtrl.text,
                  phone: phoneCtrl.text,
                  role: roleCtrl.text,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Profile updated successfully!'),
                        ],
                      ),
                      backgroundColor: Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'Save Changes',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearTransactions(BuildContext context, CollectionProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_outlined, color: AppTheme.balanceDueColor),
            SizedBox(width: 8),
            Text('Clear Transactions?'),
          ],
        ),
        content: const Text(
          'This will remove all collections, pending bills, and test orders to give you a clean slate.\n\nAll your Beat Routes and Registered Outlets will be KEPT completely safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.balanceDueColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear & Start Fresh', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await provider.resetTransactions();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transactions cleared! Routes and Outlets preserved.'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final todayCollections = provider.getFilteredCollections();
    final totalCollected = todayCollections.fold<double>(0.0, (sum, c) => sum + c.collectedAmount);
    final totalBills = todayCollections.length;
    final totalPendingDue = provider.pendingBills
        .where((b) => !b.isPaid)
        .fold<double>(0.0, (sum, b) => sum + b.balanceDue);
    final totalRoutes = provider.routes.length;
    final totalShops = provider.shops.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Profile',
            onPressed: () => _showEditProfileDialog(context, provider),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Officer Profile Header Card (Editable)
            _buildProfileHeaderCard(context, provider),

            const SizedBox(height: 16),

            // 2. Field Activity & Performance Overview
            _buildPerformanceStats(
              totalCollected: totalCollected,
              totalBills: totalBills,
              totalPendingDue: totalPendingDue,
              totalRoutes: totalRoutes,
              totalShops: totalShops,
            ),

            const SizedBox(height: 16),

            // 3. Quick Payment Tools Hub (QR & Bank details sharing)
            _buildPaymentHubCard(context),

            const SizedBox(height: 16),

            // 4. Reports & Diagnostic Tools
            _buildToolsCard(context, provider),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeaderCard(BuildContext context, CollectionProvider provider) {
    final initials = provider.salesmanName.trim().isNotEmpty
        ? provider.salesmanName.trim().substring(0, 1).toUpperCase()
        : 'A';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppTheme.secondary,
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.salesmanName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      provider.salesmanRole.isNotEmpty ? provider.salesmanRole : 'Collection Executive',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blueGrey.shade300,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 12, color: Color(0xFF10B981)),
                        const SizedBox(width: 4),
                        Text(
                          provider.salesmanPhone.isNotEmpty ? provider.salesmanPhone : '+91 98220 12345',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey.shade200,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                ),
                icon: const Icon(Icons.edit, size: 16, color: Colors.white),
                tooltip: 'Edit Profile Details',
                onPressed: () => _showEditProfileDialog(context, provider),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStatus(
                icon: Icons.check_circle_rounded,
                label: 'Status',
                value: 'Field Active',
                color: const Color(0xFF10B981),
              ),
              _buildMiniStatus(
                icon: Icons.alt_route_rounded,
                label: 'Assigned Beats',
                value: '${provider.routes.length} Routes',
                color: AppTheme.secondary,
              ),
              _buildMiniStatus(
                icon: Icons.storefront_rounded,
                label: 'Registered Stores',
                value: '${provider.shops.length} Outlets',
                color: const Color(0xFFF59E0B),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatus({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade400, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPerformanceStats({
    required double totalCollected,
    required int totalBills,
    required double totalPendingDue,
    required int totalRoutes,
    required int totalShops,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'ACTIVITY SUMMARY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.blueGrey,
                  letterSpacing: 0.8,
                ),
              ),
              Icon(Icons.insights, size: 16, color: Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: "Today's Collections",
                  value: CurrencyFormatter.format(totalCollected),
                  icon: Icons.currency_rupee,
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  label: "Receipts Collected",
                  value: '$totalBills',
                  icon: Icons.receipt_long_outlined,
                  color: AppTheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildMetricTile(
            label: 'Total Outstanding Balance Due',
            value: CurrencyFormatter.format(totalPendingDue),
            icon: Icons.pending_actions_outlined,
            color: AppTheme.chequeColor,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blueGrey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentHubCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'CUSTOMER PAYMENT TOOLS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.blueGrey,
                  letterSpacing: 0.8,
                ),
              ),
              Icon(Icons.payment_outlined, size: 16, color: Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Quickly send Purva or Manas bank transfer details or show QR codes when a customer requests payment info.',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    FirmDetailsHelper.showQuickShareModal(context);
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send Bank Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    PaymentQrDialog.show(context);
                  },
                  icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                  label: const Text('Scan QR Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolsCard(BuildContext context, CollectionProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'DATA & SETTINGS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.blueGrey,
                  letterSpacing: 0.8,
                ),
              ),
              Icon(Icons.settings_outlined, size: 16, color: Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 8),

          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.description_outlined, color: AppTheme.secondary, size: 20),
              ),
              title: const Text('Collection Statement & Ledger', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              subtitle: const Text('Export and view reports in PDF and Excel', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StatementScreen()),
                );
              },
            ),
          ),
          const Divider(height: 1),

          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.balanceDueColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.cleaning_services_outlined, color: AppTheme.balanceDueColor, size: 20),
              ),
              title: const Text('Start Fresh (Clear Transactions)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppTheme.balanceDueColor)),
              subtitle: const Text('Clears old records; keeps all Routes & Outlets', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              onTap: () => _confirmClearTransactions(context, provider),
            ),
          ),
          const Divider(height: 1),

          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('App Version', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600)),
              const Text('v1.0.0 (Field PWA)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Storage Engine', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600)),
              const Text('Local Cache & Cloud Sync', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
            ],
          ),
        ],
      ),
    );
  }
}
