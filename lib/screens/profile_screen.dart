import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/collection_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/firm_details.dart';
import '../utils/theme.dart';
import '../widgets/payment_qr_dialog.dart';
import 'statement_screen.dart';
import 'cash_handover_screen.dart';
import 'vehicle_collection_screen.dart';
import 'user_management_screen.dart';
import '../services/bill_ocr_service.dart';

class ProfileScreen extends StatelessWidget {
  final VoidCallback? onBackToOverview;

  const ProfileScreen({
    super.key,
    this.onBackToOverview,
  });

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

  void _showManageVehiclesDialog(BuildContext context, CollectionProvider provider) {
    final newVehicleCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final vehicles = provider.vehicles;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.local_shipping_rounded, color: Color(0xFF0284C7), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Manage Delivery Vehicles',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Text(
                    'Add or delete vehicles for Daily Vehicle Collection & fuel logging.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: vehicles.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('No vehicles added yet.'),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: vehicles.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final v = vehicles[idx];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.directions_car_filled_outlined,
                                    size: 20, color: Color(0xFF0284C7)),
                                title: Text(
                                  v,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                  tooltip: 'Delete Vehicle',
                                  onPressed: () async {
                                    await provider.deleteVehicle(v);
                                    setModalState(() {});
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newVehicleCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: 'New Vehicle Number',
                            hintText: 'e.g. MH 14 XX 1234',
                            isDense: true,
                            prefixIcon: const Icon(Icons.add_road_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          final text = newVehicleCtrl.text.trim();
                          if (text.isNotEmpty) {
                            await provider.addVehicle(text);
                            newVehicleCtrl.clear();
                            setModalState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showManageEmployeesDialog(BuildContext context, CollectionProvider provider) {
    final newEmployeeCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final employees = provider.employees;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.badge_outlined, color: Color(0xFF10B981), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Manage Collection Staff',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Text(
                    'Add or delete staff names for vehicle handover and collection slips.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: employees.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('No employees added yet.'),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: employees.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final e = employees[idx];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.person_outline,
                                    size: 20, color: Color(0xFF10B981)),
                                title: Text(
                                  e,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                  tooltip: 'Delete Employee',
                                  onPressed: () async {
                                    await provider.deleteEmployee(e);
                                    setModalState(() {});
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newEmployeeCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'New Employee Name',
                            hintText: 'e.g. Ramesh',
                            isDense: true,
                            prefixIcon: const Icon(Icons.person_add_outlined, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          final text = newEmployeeCtrl.text.trim();
                          if (text.isNotEmpty) {
                            await provider.addEmployee(text);
                            newEmployeeCtrl.clear();
                            setModalState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showGeminiKeyDialog(BuildContext context) async {
    final currentKey = await BillOcrService.getApiKey() ?? '';
    final ctrl = TextEditingController(text: currentKey);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 22),
              SizedBox(width: 8),
              Text('Cloud AI Bill Scanner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Gemini AI automatically reads Invoice #, Date, Bill Amount, and matches English/Marathi party names when capturing bills.',
                style: TextStyle(fontSize: 12.5, color: Colors.blueGrey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: 'Gemini API Key',
                  hintText: 'AIzaSy...',
                  prefixIcon: const Icon(Icons.key),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '✓ Synced automatically across all logins & devices via Supabase cloud.',
                style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final cloudKey = await BillOcrService.syncFromCloud();
                if (cloudKey != null && cloudKey.isNotEmpty) {
                  ctrl.text = cloudKey;
                  setDlgState(() {});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Synced key from cloud!')),
                    );
                  }
                }
              },
              child: const Text('Pull Cloud Key'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final newKey = ctrl.text.trim();
                await BillOcrService.saveApiKey(newKey);
                if (dlgCtx.mounted) {
                  Navigator.pop(dlgCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gemini API key saved & synced across all logins!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('Save & Cloud Sync', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
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
        leading: onBackToOverview != null || Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Overview',
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else if (onBackToOverview != null) {
                    onBackToOverview!();
                  }
                },
              )
            : null,
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
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.currentUser;

    final displayName = currentUser?.name ?? provider.salesmanName;
    final displayPhone = currentUser?.phone ?? provider.salesmanPhone;
    final displayRole = currentUser?.roleDisplayName ?? (provider.salesmanRole.isNotEmpty ? provider.salesmanRole : 'Collection Executive');

    final initials = displayName.trim().isNotEmpty
        ? displayName.trim().substring(0, 1).toUpperCase()
        : 'A';

    Color roleBadgeColor = const Color(0xFFD97706);
    if (currentUser?.isSuperAdmin == true) {
      roleBadgeColor = const Color(0xFF3B82F6);
    } else if (currentUser?.isOffice == true) {
      roleBadgeColor = const Color(0xFF10B981);
    }

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
                backgroundColor: roleBadgeColor,
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: roleBadgeColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: roleBadgeColor.withValues(alpha: 0.6)),
                          ),
                          child: Text(
                            displayRole,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: roleBadgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 12, color: Color(0xFF10B981)),
                        const SizedBox(width: 4),
                        Text(
                          displayPhone,
                          style: TextStyle(
                            fontSize: 12.5,
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
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.currentUser;

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

          // 1. Staff & Role Management (Super Admin & Office)
          if (currentUser == null || currentUser.isSuperAdmin || currentUser.isOffice) ...[
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.manage_accounts_rounded, color: Color(0xFF2563EB), size: 20),
                ),
                title: const Text('Staff & Role Management', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                subtitle: const Text('Change staff mobile numbers, passwords & roles', style: TextStyle(fontSize: 11.5)),
                trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UserManagementScreen()),
                  );
                },
              ),
            ),
            const Divider(height: 1),
          ],

          // 2. Collection Statement & Ledger
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

          // Cash Handover & Denominations Counter
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.payments_rounded, color: Color(0xFF10B981), size: 20),
              ),
              title: const Text('Cash Counter', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              subtitle: const Text('Count ₹500, ₹200, ₹100 notes & match daily cash', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
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
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_shipping_rounded, color: Color(0xFF0284C7), size: 20),
              ),
              title: const Text('Daily Vehicle Collection', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              subtitle: const Text('Vehicle cash, fuel expenses & cash counter handover', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VehicleCollectionScreen(
                      initialDate: provider.selectedDate,
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),

          // Manage Delivery Vehicles
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.directions_car_filled_outlined, color: Color(0xFF0284C7), size: 20),
              ),
              title: const Text('Manage Vehicles', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              subtitle: Text('${provider.vehicles.length} delivery vans registered • Add or remove', style: const TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              onTap: () => _showManageVehiclesDialog(context, provider),
            ),
          ),
          const Divider(height: 1),

          // Manage Employees / Staff
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.people_alt_outlined, color: Color(0xFF10B981), size: 20),
              ),
              title: const Text('Manage Employees', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              subtitle: Text('${provider.employees.length} collection staff registered • Add or remove', style: const TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              onTap: () => _showManageEmployeesDialog(context, provider),
            ),
          ),
          const Divider(height: 1),

          // Cloud AI Bill Scanner (Gemini API Key)
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 20),
              ),
              title: const Text('AI Bill Scanner (Cloud Key)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              subtitle: const Text('Auto-syncs Gemini Vision API key across phone & desktop', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              onTap: () => _showGeminiKeyDialog(context),
            ),
          ),
          const Divider(height: 1),

          // 3. Automated Cloud Backup (Runs every 4 days)
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.cloud_sync_rounded, color: Color(0xFF10B981), size: 20),
              ),
              title: const Text('Automated Cloud Backup', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              subtitle: Text(
                provider.lastBackupTime != null
                    ? 'Auto-runs every 4 days • Last: ${DateFormat('dd MMM, hh:mm a').format(provider.lastBackupTime!)}'
                    : 'Auto-runs every 4 days • Cloud Active',
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: ElevatedButton(
                onPressed: () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Creating cloud backup snapshot...')),
                  );
                  final ok = await provider.triggerManualBackup();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? 'Backup completed & verified in cloud!' : 'Backup failed. Check network.'),
                        backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Backup Now', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const Divider(height: 1),

          // 4. Start Fresh / Clear Transactions
          if (currentUser == null || currentUser.isSuperAdmin) ...[
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
          ],

          // 5. Staff Log Out
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.logout_rounded, color: AppTheme.balanceDueColor, size: 20),
              ),
              title: const Text(
                'Log Out',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppTheme.balanceDueColor),
              ),
              subtitle: Text(
                'Signed in as ${currentUser?.name ?? provider.salesmanName} (${currentUser?.phone ?? provider.salesmanPhone})',
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Log Out?'),
                    content: const Text('Are you sure you want to log out of your staff account?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dCtx);
                          auth.logout();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.balanceDueColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Log Out'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

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
