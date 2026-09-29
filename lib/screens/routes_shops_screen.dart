import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/collection_provider.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import 'add_route_dialog.dart';
import 'add_shop_screen.dart';
import 'record_collection_screen.dart';
import 'send_reminder_dialog.dart';

class RoutesShopsScreen extends StatefulWidget {
  const RoutesShopsScreen({super.key});

  @override
  State<RoutesShopsScreen> createState() => _RoutesShopsScreenState();
}

class _RoutesShopsScreenState extends State<RoutesShopsScreen> {
  String? _selectedRouteId;
  String _shopSearch = '';

  Future<void> _confirmAndDeleteShop(ShopModel shop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Store?'),
        content: Text('Are you sure you want to delete "${shop.name}"?\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<CollectionProvider>().deleteShop(shop.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Store "${shop.name}" deleted'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final routes = provider.routes;

    if (_selectedRouteId == null && routes.isNotEmpty) {
      _selectedRouteId = routes.first.id;
    }

    final selectedRoute = routes.firstWhere(
      (r) => r.id == _selectedRouteId,
      orElse: () => routes.isNotEmpty
          ? routes.first
          : RouteModel(id: '', name: 'No Beat Selected'),
    );

    final shopsInRoute = provider.shops.where((s) {
      if (_selectedRouteId != null && _selectedRouteId!.isNotEmpty) {
        if (s.routeId != _selectedRouteId) return false;
      }
      if (_shopSearch.isNotEmpty) {
        final q = _shopSearch.toLowerCase();
        return s.name.toLowerCase().contains(q) ||
            s.mobileNumber.contains(q) ||
            s.address.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Routes & Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business_outlined, size: 20),
            tooltip: 'Add Store',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddShopScreen(initialRouteId: _selectedRouteId),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined, size: 20),
            tooltip: 'Add Beat Route',
            onPressed: () async {
              final newRoute = await showDialog<RouteModel>(
                context: context,
                builder: (ctx) => const AddRouteDialog(),
              );
              if (newRoute != null) {
                setState(() => _selectedRouteId = newRoute.id);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Route Horizontal Selector Bar
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'SALES ROUTES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Colors.blueGrey,
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        final newRoute = await showDialog<RouteModel>(
                          context: context,
                          builder: (ctx) => const AddRouteDialog(),
                        );
                        if (newRoute != null) {
                          setState(() => _selectedRouteId = newRoute.id);
                        }
                      },
                      child: Row(
                        children: const [
                          Icon(Icons.add, size: 14, color: AppTheme.secondary),
                          SizedBox(width: 4),
                          Text(
                            'Add Beat',
                            style: TextStyle(
                              color: AppTheme.secondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (routes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Create your first beat (e.g. Chakan)'),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (ctx) => const AddRouteDialog(),
                        ),
                      ),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: routes.map((r) {
                        final isSelected = _selectedRouteId == r.id;
                        final count = provider.getShopsForRoute(r.id).length;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            avatar: Icon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: isSelected ? Colors.white : AppTheme.primary,
                            ),
                            label: Text('${r.name} ($count)'),
                            selected: isSelected,
                            selectedColor: AppTheme.primary,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.blueGrey.shade800,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 12,
                            ),
                            backgroundColor: Colors.grey.shade100,
                            onSelected: (val) {
                              if (val) setState(() => _selectedRouteId = r.id);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Route Details Banner & Search
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectedRoute.id.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  selectedRoute.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${shopsInRoute.length} stores',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (selectedRoute.description != null && selectedRoute.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  selectedRoute.description!,
                                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                ),
                              ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.edit_outlined, size: 14, color: AppTheme.primary),
                        label: const Text('Edit Route', style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          side: const BorderSide(color: AppTheme.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () async {
                          final result = await showDialog(
                            context: context,
                            builder: (ctx) => AddRouteDialog(existingRoute: selectedRoute),
                          );
                          if (result == 'deleted') {
                            setState(() => _selectedRouteId = null);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search stores in ${selectedRoute.name}...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    suffixIcon: _shopSearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => setState(() => _shopSearch = ''),
                          )
                        : null,
                  ),
                  onChanged: (val) => setState(() => _shopSearch = val),
                ),
              ],
            ),
          ),

          // Shops List
          Expanded(
            child: shopsInRoute.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.storefront_outlined, size: 48, color: Colors.blueGrey.shade200),
                        const SizedBox(height: 10),
                        Text(
                          _shopSearch.isNotEmpty
                              ? 'No stores matching "$_shopSearch"'
                              : 'No stores registered under "${selectedRoute.name}" yet',
                          style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: Text('Add Store to ${selectedRoute.name}'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AddShopScreen(initialRouteId: _selectedRouteId),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: shopsInRoute.length,
                    itemBuilder: (context, index) {
                      final shop = shopsInRoute[index];
                      final collections = provider.getCollectionsForShop(shop.id);
                      final totalPaid = collections.fold(0.0, (sum, c) => sum + c.collectedAmount);
                      final balanceDue = provider.getTotalBalanceForShop(shop.id);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppTheme.border),
                                    ),
                                    child: Center(
                                      child: Text(
                                        shop.name.isNotEmpty ? shop.name[0].toUpperCase() : 'S',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          shop.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        if (shop.ownerName != null && shop.ownerName!.isNotEmpty)
                                          Text(
                                            'Contact: ${shop.ownerName}',
                                            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                          ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            const Icon(Icons.phone_outlined, size: 13, color: Colors.blueGrey),
                                            const SizedBox(width: 4),
                                            Text(
                                              shop.mobileNumber,
                                              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(Icons.place_outlined, size: 13, color: Colors.blueGrey),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                shop.address,
                                                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade500),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20, color: Colors.blueGrey),
                                    padding: EdgeInsets.zero,
                                    tooltip: 'Store options',
                                    onSelected: (val) async {
                                      if (val == 'edit') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => AddShopScreen(existingShop: shop),
                                          ),
                                        );
                                      } else if (val == 'delete') {
                                        _confirmAndDeleteShop(shop);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                                            SizedBox(width: 8),
                                            Text('Edit Store'),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: const [
                                            Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                                            SizedBox(width: 8),
                                            Text('Delete Store', style: TextStyle(color: AppTheme.error)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Collected: ${CurrencyFormatter.format(totalPaid)} (${collections.length} bills)',
                                        style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700, fontWeight: FontWeight.w600),
                                      ),
                                      if (balanceDue > 0)
                                        Text(
                                          'Pending Balance: ${CurrencyFormatter.format(balanceDue)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.partialBadgeColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      if (balanceDue > 0) ...[
                                        OutlinedButton.icon(
                                          icon: const Icon(Icons.notifications_active_outlined, size: 13, color: AppTheme.chequeColor),
                                          label: const Text('Remind', style: TextStyle(color: AppTheme.chequeColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            side: const BorderSide(color: AppTheme.chequeColor),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => SendReminderDialog(
                                                shopName: shop.name,
                                                mobileNumber: shop.mobileNumber,
                                                businessName: provider.businesses.first,
                                                salesmanName: provider.salesmanName,
                                                balanceAmount: balanceDue,
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.add, size: 14),
                                        label: const Text('Record'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => RecordCollectionScreen(initialShopId: shop.id),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add_business, color: Colors.white),
        label: const Text('Add Store', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddShopScreen(initialRouteId: _selectedRouteId),
            ),
          );
        },
      ),
    );
  }
}
