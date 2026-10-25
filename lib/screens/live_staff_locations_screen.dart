import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import '../utils/quick_alert.dart';
import '../services/location_tracking_service.dart';

class LiveStaffLocationsScreen extends StatefulWidget {
  const LiveStaffLocationsScreen({super.key});

  @override
  State<LiveStaffLocationsScreen> createState() => _LiveStaffLocationsScreenState();
}

class _LiveStaffLocationsScreenState extends State<LiveStaffLocationsScreen> {
  String _selectedRoleFilter = 'all'; // 'all', 'salesman', 'driver', 'office'
  bool _isRefreshing = false;

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    final auth = context.read<AuthProvider>();
    final collectionProvider = context.read<CollectionProvider>();

    // Also update own current user location immediately
    await LocationTrackingService().captureImmediate(
      auth: auth,
      collectionProvider: collectionProvider,
    );
    await auth.refreshUsers();

    if (mounted) {
      setState(() => _isRefreshing = false);
      QuickAlert.success(context, 'Live staff locations updated');
    }
  }

  void _openMaps(double lat, double lng) async {
    final url = 'https://maps.google.com/?q=$lat,$lng';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _callPhone(String phone) async {
    if (phone.trim().isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _shareLocationViaWhatsApp(UserModel user) async {
    if (!user.hasLocation) return;
    final text = 'Live Location of ${user.name} (${user.roleDisplayName}):\n'
        '• Status: ${user.isOnline ? "Active Online" : "Last seen ${user.locationTimeAgo}"}\n'
        '• Landmark: ${user.locationLandmark ?? "Field"}\n'
        '• Google Maps: ${user.mapsUrl}';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<CollectionProvider>();
    final users = auth.users.where((u) => u.id != 'config_gemini_api' && !u.isSuperAdmin).toList();

    final filteredUsers = users.where((u) {
      if (_selectedRoleFilter == 'salesman') return u.isSalesman;
      if (_selectedRoleFilter == 'driver') return u.isDriver;
      if (_selectedRoleFilter == 'office') return u.isOffice;
      return true;
    }).toList();

    final onlineCount = users.where((u) => u.isOnline).length;
    final locatedCount = users.where((u) => u.hasLocation).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Live Staff & Fleet Locations',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh GPS Fix',
            onPressed: _isRefreshing ? null : _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          children: [
            // Status Summary Cards
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.groups_outlined, size: 16, color: Colors.blueGrey),
                            SizedBox(width: 4),
                            Text('Total Staff', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${users.length}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.sensors, size: 16, color: Color(0xFF16A34A)),
                            SizedBox(width: 4),
                            Text('Active Now', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$onlineCount Online',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF15803D)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.location_on, size: 16, color: Color(0xFF2563EB)),
                            SizedBox(width: 4),
                            Text('GPS Tracked', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$locatedCount / ${users.length}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Role Filter Segment
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  _buildFilterTab('all', 'All (${users.length})'),
                  _buildFilterTab('salesman', 'Salesmen (${users.where((u) => u.isSalesman).length})'),
                  _buildFilterTab('driver', 'Drivers (${users.where((u) => u.isDriver).length})'),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Staff Location Cards List
            if (filteredUsers.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: const Text('No staff members found matching filter.'),
              )
            else
              ...filteredUsers.map((u) {
                final summary = provider.getStaffSummary(u.name);
                final hasLoc = u.hasLocation;
                final isOnline = u.isOnline;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isOnline ? const Color(0xFF86EFAC) : AppTheme.border,
                      width: isOnline ? 1.5 : 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card Header: Avatar, Name, Role, Online Badge
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: u.isDriver
                                    ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                                    : (u.isSalesman
                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                        : Colors.amber.shade100),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                u.isDriver
                                    ? Icons.local_shipping
                                    : (u.isSalesman ? Icons.two_wheeler : Icons.business_center),
                                color: u.isDriver
                                    ? const Color(0xFF0284C7)
                                    : (u.isSalesman ? const Color(0xFF059669) : Colors.amber.shade800),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        u.name,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.blueGrey.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          u.roleDisplayName.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blueGrey.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    u.phone,
                                    style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                                  ),
                                ],
                              ),
                            ),

                            // Online/Offline Status Indicator
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isOnline
                                    ? const Color(0xFFDCFCE7)
                                    : (hasLoc ? Colors.grey.shade100 : Colors.red.shade50),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isOnline
                                      ? const Color(0xFF86EFAC)
                                      : (hasLoc ? Colors.grey.shade300 : Colors.red.shade200),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isOnline
                                          ? const Color(0xFF16A34A)
                                          : (hasLoc ? Colors.blueGrey : Colors.red),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    isOnline
                                        ? 'LIVE'
                                        : (hasLoc ? u.locationTimeAgo : 'No GPS'),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: isOnline
                                          ? const Color(0xFF15803D)
                                          : (hasLoc ? Colors.blueGrey.shade700 : Colors.red.shade700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Location Details Container
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on, size: 16, color: Color(0xFFDC2626)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          hasLoc
                                              ? (u.locationLandmark ?? 'Active in Beat Route')
                                              : 'Location not shared yet',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: hasLoc ? const Color(0xFF0F172A) : Colors.blueGrey.shade500,
                                          ),
                                        ),
                                        if (hasLoc) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'GPS: ${u.latitude?.toStringAsFixed(5)}, ${u.longitude?.toStringAsFixed(5)} • Updated: ${u.locationTimeAgo}',
                                            style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (u.isDriver && u.assignedRouteIds.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.alt_route, size: 14, color: Color(0xFF0284C7)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Assigned: ${u.assignedRouteIds.map((id) => provider.getRouteName(id)).join(", ")}',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF0369A1), fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Performance & Summary Strip
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Today: ${CurrencyFormatter.format(summary.totalAmount)} (${summary.collectionsCount} bills)',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            ),
                            Row(
                              children: [
                                if (u.phone.isNotEmpty && RegExp(r'^\d+$').hasMatch(u.phone))
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.phone_outlined, size: 18, color: Color(0xFF2563EB)),
                                    tooltip: 'Call Staff',
                                    onPressed: () => _callPhone(u.phone),
                                  ),
                                if (hasLoc)
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF16A34A)),
                                    tooltip: 'Share Live Location',
                                    onPressed: () => _shareLocationViaWhatsApp(u),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        // Main Action Button: Open Google Maps
                        if (hasLoc) ...[
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.map_outlined, size: 16),
                              label: Text(
                                'Track ${u.name} on Google Maps',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                              onPressed: () => _openMaps(u.latitude!, u.longitude!),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab(String role, String label) {
    final isSelected = _selectedRoleFilter == role;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedRoleFilter = role),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : Colors.blueGrey.shade800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
