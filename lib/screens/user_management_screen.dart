import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../models/user_model.dart';
import '../utils/marathi_search_helper.dart';
import '../utils/theme.dart';
import 'live_staff_locations_screen.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  UserRole? _selectedRoleFilter; // null = All roles

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showQuickAssignRoutesDialog(BuildContext context, UserModel user) {
    final auth = context.read<AuthProvider>();
    final collectionProvider = context.read<CollectionProvider>();
    final allRoutes = collectionProvider.allRoutes;
    final allShops = collectionProvider.allShops;

    List<String> selectedRoutes = List<String>.from(user.assignedRouteIds);
    String routeSearchQuery = '';
    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final filteredRoutes = allRoutes.where((r) {
            if (routeSearchQuery.trim().isEmpty) return true;
            final q = routeSearchQuery.toLowerCase().trim();
            return MarathiSearchHelper.matches(r.name, q) ||
                r.name.toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15803D).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.alt_route_rounded, color: Color(0xFF15803D), size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assign Routes: ${user.plainName}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${user.roleDisplayName} • ${selectedRoutes.length} route(s) selected',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  // Search Box
                  Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search routes by name...',
                        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                        suffixIcon: routeSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setDlgState(() => routeSearchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (val) => setDlgState(() => routeSearchQuery = val),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Quick Actions (Select All / Clear All)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${filteredRoutes.length} routes available',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          InkWell(
                            onTap: () {
                              setDlgState(() {
                                for (final r in filteredRoutes) {
                                  if (!selectedRoutes.contains(r.id)) selectedRoutes.add(r.id);
                                }
                              });
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Text('Select All', style: TextStyle(fontSize: 11, color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const Text('•', style: TextStyle(color: Colors.grey)),
                          InkWell(
                            onTap: () {
                              setDlgState(() {
                                for (final r in filteredRoutes) {
                                  selectedRoutes.remove(r.id);
                                }
                              });
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Text('Clear All', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  // Route Checkbox List
                  Expanded(
                    child: filteredRoutes.isEmpty
                        ? const Center(
                            child: Text('No routes matching search', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          )
                        : ListView.separated(
                            itemCount: filteredRoutes.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final route = filteredRoutes[idx];
                              final isChecked = selectedRoutes.contains(route.id);
                              final shopCount = allShops.where((s) => s.routeId == route.id).length;

                              return CheckboxListTile(
                                dense: true,
                                value: isChecked,
                                activeColor: const Color(0xFF15803D),
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  route.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isChecked ? FontWeight.bold : FontWeight.w500,
                                    color: isChecked ? const Color(0xFF15803D) : const Color(0xFF0F172A),
                                  ),
                                ),
                                subtitle: Text(
                                  '$shopCount outlets',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                                onChanged: (val) {
                                  setDlgState(() {
                                    if (val == true) {
                                      selectedRoutes.add(route.id);
                                    } else {
                                      selectedRoutes.remove(route.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Save Routes', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF15803D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  Navigator.pop(dlgCtx);
                  final updated = user.copyWith(assignedRouteIds: selectedRoutes);
                  await auth.saveUser(updated);
                  if (auth.currentUser?.id == user.id) {
                    collectionProvider.setCurrentUser(updated);
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Assigned ${selectedRoutes.length} route(s) to ${user.name}!')),
                          ],
                        ),
                        backgroundColor: const Color(0xFF15803D),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddOrEditUserDialog(BuildContext context, {UserModel? userToEdit}) {
    final auth = context.read<AuthProvider>();
    final collectionProvider = context.read<CollectionProvider>();
    final allRoutes = collectionProvider.allRoutes;
    final allShops = collectionProvider.allShops;
    final isEditing = userToEdit != null;

    final nameCtrl = TextEditingController(text: userToEdit?.name ?? '');
    final phoneCtrl = TextEditingController(text: userToEdit?.phone ?? '');
    final passCtrl = TextEditingController(text: userToEdit?.actualPassword ?? 'pass123');
    UserRole selectedRole = userToEdit?.role ?? UserRole.salesman;
    List<String> assignedRouteIds = List<String>.from(userToEdit?.assignedRouteIds ?? []);
    bool obscurePassword = true;
    String routeSearchQuery = '';
    final routeSearchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final filteredRoutes = allRoutes.where((r) {
            if (routeSearchQuery.trim().isEmpty) return true;
            final q = routeSearchQuery.toLowerCase().trim();
            return MarathiSearchHelper.matches(r.name, q) ||
                r.name.toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              isEditing ? 'Edit Staff Member' : 'Add New Staff Member',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Staff Name / Username',
                        hintText: 'e.g. Akash, Atharva, or Order 1',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      decoration: InputDecoration(
                        labelText: 'Login ID / Mobile Number',
                        hintText: 'e.g. 76209 95547 or order1',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'e.g. pass123',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Assigned Role:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<UserRole>(
                      initialValue: selectedRole,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: UserRole.superAdmin,
                          child: Text('👑 Super Admin'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.office,
                          child: Text('🏢 Office Staff'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.salesman,
                          child: Text('🛵 Sales & Collection'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.driver,
                          child: Text('🚚 Delivery Driver'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.order,
                          child: Text('🛒 Order Booking (Order Man)'),
                        ),
                      ],
                      onChanged: (newRole) {
                        if (newRole != null) {
                          setModalState(() {
                            selectedRole = newRole;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Route Assignment Card (Available for all staff!)
                    if (selectedRole == UserRole.superAdmin) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Color(0xFF1D4ED8), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Super Admin automatically has master access across all routes and both firms.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF), fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
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
                              children: [
                                const Icon(Icons.alt_route_rounded, color: Color(0xFF15803D), size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Assigned Route(s) (${assignedRouteIds.length} selected):',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              selectedRole == UserRole.driver
                                  ? 'Driver will ONLY see pending delivery bills and shops for selected routes.'
                                  : selectedRole == UserRole.order
                                      ? 'Order man will ONLY see assigned route outlets and book orders on map.'
                                      : 'Salesman will ONLY see assigned route outlets, pending bills & collections.',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF166534)),
                            ),
                            const SizedBox(height: 8),
                            // Quick Filter & Select All / Clear All
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: TextField(
                                      controller: routeSearchCtrl,
                                      decoration: const InputDecoration(
                                        hintText: 'Filter routes...',
                                        hintStyle: TextStyle(fontSize: 11, color: Colors.grey),
                                        prefixIcon: Icon(Icons.search, size: 14, color: Colors.grey),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                                      ),
                                      onChanged: (val) => setModalState(() => routeSearchQuery = val),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                TextButton(
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                  onPressed: () {
                                    setModalState(() {
                                      for (final r in filteredRoutes) {
                                        if (!assignedRouteIds.contains(r.id)) assignedRouteIds.add(r.id);
                                      }
                                    });
                                  },
                                  child: const Text('All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                  onPressed: () {
                                    setModalState(() {
                                      for (final r in filteredRoutes) {
                                        assignedRouteIds.remove(r.id);
                                      }
                                    });
                                  },
                                  child: const Text('Clear', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: filteredRoutes.isEmpty
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Text('No routes found', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: filteredRoutes.length,
                                      separatorBuilder: (_, _) => const Divider(height: 1),
                                      itemBuilder: (_, idx) {
                                        final route = filteredRoutes[idx];
                                        final isChecked = assignedRouteIds.contains(route.id);
                                        final shopCount = allShops.where((s) => s.routeId == route.id).length;

                                        return CheckboxListTile(
                                          dense: true,
                                          visualDensity: VisualDensity.compact,
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                            route.name,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                                              color: isChecked ? const Color(0xFF15803D) : const Color(0xFF0F172A),
                                            ),
                                          ),
                                          subtitle: Text('$shopCount outlets', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                                          value: isChecked,
                                          activeColor: const Color(0xFF15803D),
                                          onChanged: (val) {
                                            setModalState(() {
                                              if (val == true) {
                                                assignedRouteIds.add(route.id);
                                              } else {
                                                assignedRouteIds.remove(route.id);
                                              }
                                            });
                                          },
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final cleanPhone = UserModel.normalizePhone(phoneCtrl.text.trim());
                  final cleanName = nameCtrl.text.trim();
                  final cleanPass = passCtrl.text.trim();

                  if (cleanPhone.isEmpty || cleanName.isEmpty || cleanPass.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill all fields')),
                    );
                    return;
                  }

                  final user = UserModel(
                    id: userToEdit?.id ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
                    phone: cleanPhone,
                    name: cleanName,
                    role: selectedRole,
                    password: cleanPass,
                    assignedRouteIds: selectedRole == UserRole.superAdmin ? const [] : assignedRouteIds,
                    isActive: userToEdit?.isActive ?? true,
                    createdAt: userToEdit?.createdAt ?? DateTime.now(),
                  );

                  await auth.saveUser(user);
                  if (auth.currentUser?.id == user.id) {
                    collectionProvider.setCurrentUser(user);
                  }

                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Staff member "${user.name}" saved successfully!')),
                          ],
                        ),
                        backgroundColor: Colors.green.shade700,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Save Staff'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteUser(BuildContext context, UserModel user) {
    final auth = context.read<AuthProvider>();

    if (user.isSuperAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Super Admin account cannot be deleted!')),
      );
      return;
    }

    if (auth.currentUser?.id == user.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete your own active login session!')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Delete Staff Member?'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${user.name}" (${user.roleDisplayName})?\n\nThis will remove their login access immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dlgCtx);
              await auth.deleteUser(user.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Staff member "${user.name}" deleted.'),
                    backgroundColor: const Color(0xFFDC2626),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final collectionProvider = context.watch<CollectionProvider>();
    final allUsers = auth.users;

    // Filter by role and search query
    final filteredUsers = allUsers.where((u) {
      if (_selectedRoleFilter != null && u.role != _selectedRoleFilter) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final matchName = MarathiSearchHelper.matches(u.name, q) || u.name.toLowerCase().contains(q);
        final matchPhone = u.phone.toLowerCase().contains(q);
        final matchRole = u.roleDisplayName.toLowerCase().contains(q);
        // Also check if any assigned route name matches!
        final matchRoute = collectionProvider.allRoutes
            .where((r) => u.assignedRouteIds.contains(r.id))
            .any((r) => MarathiSearchHelper.matches(r.name, q) || r.name.toLowerCase().contains(q));

        if (!matchName && !matchPhone && !matchRole && !matchRoute) {
          return false;
        }
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Staff & Role Management',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              'Assign individual routes & manage staff logins',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Sync Users from Cloud',
            onPressed: () async {
              await auth.refreshUsers();
              await collectionProvider.syncAllWithCloud(notify: true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Staff list refreshed from cloud!'), duration: Duration(seconds: 1)),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.location_on_outlined),
            tooltip: 'Live Staff Tracking',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LiveStaffLocationsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Add Staff Member',
            onPressed: () => _showAddOrEditUserDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Top Search & Filter Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              children: [
                // Search Field
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search staff by name, login ID, or route...',
                      hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(height: 10),

                // Role Filter Chips Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildRoleFilterChip('All Staff (${allUsers.length})', null),
                      const SizedBox(width: 6),
                      _buildRoleFilterChip('👑 Admin', UserRole.superAdmin),
                      const SizedBox(width: 6),
                      _buildRoleFilterChip('🛵 Sales', UserRole.salesman),
                      const SizedBox(width: 6),
                      _buildRoleFilterChip('🛒 Order', UserRole.order),
                      const SizedBox(width: 6),
                      _buildRoleFilterChip('🚚 Driver', UserRole.driver),
                      const SizedBox(width: 6),
                      _buildRoleFilterChip('🏢 Office', UserRole.office),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 2. Staff List
          Expanded(
            child: filteredUsers.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.people_outline_rounded, size: 56, color: Color(0xFFCBD5E1)),
                          const SizedBox(height: 12),
                          const Text('No staff members found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF64748B))),
                          const SizedBox(height: 4),
                          const Text('Try adjusting your search query or role filter.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add New Staff Member'),
                            onPressed: () => _showAddOrEditUserDialog(context),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    itemCount: filteredUsers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (ctx, index) {
                      final user = filteredUsers[index];
                      final isCurrent = auth.currentUser?.id == user.id;

                      Color badgeColor;
                      IconData roleIcon;
                      switch (user.role) {
                        case UserRole.superAdmin:
                          badgeColor = const Color(0xFF2563EB);
                          roleIcon = Icons.admin_panel_settings_rounded;
                          break;
                        case UserRole.office:
                          badgeColor = const Color(0xFF0F766E);
                          roleIcon = Icons.business_center_rounded;
                          break;
                        case UserRole.salesman:
                          badgeColor = const Color(0xFFD97706);
                          roleIcon = Icons.two_wheeler_rounded;
                          break;
                        case UserRole.driver:
                          badgeColor = const Color(0xFF0284C7);
                          roleIcon = Icons.local_shipping_rounded;
                          break;
                        case UserRole.order:
                          badgeColor = const Color(0xFF7C3AED);
                          roleIcon = Icons.shopping_bag_rounded;
                          break;
                      }

                      // Assigned route names
                      final assignedRoutes = collectionProvider.allRoutes
                          .where((r) => user.assignedRouteIds.contains(r.id))
                          .toList();

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isCurrent ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                            width: isCurrent ? 1.8 : 1.0,
                          ),
                          boxShadow: const [
                            BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Avatar Circle
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(roleIcon, color: badgeColor, size: 24),
                                  ),
                                  const SizedBox(width: 12),

                                  // Staff Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                user.name,
                                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F172A)),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isCurrent) ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFDBEAFE),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'YOU',
                                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            // Active / Inactive Switch
                                            Switch.adaptive(
                                              value: user.isActive,
                                              activeTrackColor: const Color(0xFF16A34A),
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              onChanged: (val) async {
                                                if (user.isSuperAdmin && !val) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('Cannot deactivate Super Admin!')),
                                                  );
                                                  return;
                                                }
                                                final updated = user.copyWith(isActive: val);
                                                await auth.saveUser(updated);
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),

                                        // Role Badge & Mobile Number
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: badgeColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                user.roleDisplayName,
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            InkWell(
                                              onTap: () {
                                                Clipboard.setData(ClipboardData(text: user.phone));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Copied ${user.phone}'), duration: const Duration(milliseconds: 900)),
                                                );
                                              },
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.phone_outlined, size: 12, color: Color(0xFF64748B)),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    user.phone,
                                                    style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            InkWell(
                                              onTap: () {
                                                Clipboard.setData(ClipboardData(text: user.actualPassword));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Copied password: ${user.actualPassword}'), duration: const Duration(milliseconds: 900)),
                                                );
                                              },
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.key_rounded, size: 12, color: Color(0xFF64748B)),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    user.actualPassword,
                                                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                                  ),
                                                ],
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

                            // 2. Assigned Routes Section
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF8FAFC),
                                border: Border(
                                  top: BorderSide(color: Color(0xFFF1F5F9)),
                                  bottom: BorderSide(color: Color(0xFFF1F5F9)),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(Icons.alt_route_rounded, size: 15, color: Color(0xFF15803D)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: user.isSuperAdmin
                                        ? const Text(
                                            '👑 Full Master Access (All Routes & Firms)',
                                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                                          )
                                        : assignedRoutes.isEmpty
                                            ? const Text(
                                                'No route assigned (All routes accessible)',
                                                style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                                              )
                                            : Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  ...assignedRoutes.take(3).map((r) {
                                                    final count = collectionProvider.allShops.where((s) => s.routeId == r.id).length;
                                                    return Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFDCFCE7),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: const Color(0xFF86EFAC)),
                                                      ),
                                                      child: Text(
                                                        '${r.name} ($count)',
                                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                                      ),
                                                    );
                                                  }),
                                                  if (assignedRoutes.length > 3)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFEFF6FF),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: const Color(0xFFBFDBFE)),
                                                      ),
                                                      child: Text(
                                                        '+${assignedRoutes.length - 3} more',
                                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                  ),
                                  if (!user.isSuperAdmin) ...[
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.edit_road_rounded, size: 14),
                                      label: Text(
                                        assignedRoutes.isEmpty ? 'Assign' : 'Change',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF15803D),
                                        side: const BorderSide(color: Color(0xFF15803D)),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () => _showQuickAssignRoutesDialog(context, user),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // 3. Bottom Action Bar (Edit, Delete, Location)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              child: Row(
                                children: [
                                  if (user.hasLocation) ...[
                                    InkWell(
                                      onTap: () async {
                                        final uri = Uri.parse(user.mapsUrl);
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                        child: Row(
                                          children: [
                                            Icon(Icons.location_on_rounded, size: 14, color: user.isOnline ? const Color(0xFF15803D) : Colors.blueGrey),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${user.locationLandmark ?? "GPS Active"} • ${user.locationTimeAgo}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: user.isOnline ? const Color(0xFF15803D) : Colors.blueGrey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.edit_note_rounded, size: 20, color: Color(0xFF1E40AF)),
                                    tooltip: 'Edit Staff Details',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _showAddOrEditUserDialog(context, userToEdit: user),
                                  ),
                                  if (!user.isSuperAdmin && !isCurrent)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Color(0xFFDC2626)),
                                      tooltip: 'Delete Staff Member',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _confirmDeleteUser(context, user),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleFilterChip(String label, UserRole? role) {
    final isSelected = _selectedRoleFilter == role;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : const Color(0xFF334155),
      ),
      selectedColor: const Color(0xFF1E3A8A),
      backgroundColor: const Color(0xFFF1F5F9),
      side: BorderSide(color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFFE2E8F0)),
      onSelected: (_) => setState(() => _selectedRoleFilter = role),
    );
  }
}
