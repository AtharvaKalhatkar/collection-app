import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/collection_provider.dart';
import '../models/route_model.dart';
import '../utils/theme.dart';
import 'add_route_dialog.dart';

import '../models/shop_model.dart';

class AddShopScreen extends StatefulWidget {
  final String? initialRouteId;
  final ShopModel? existingShop;

  const AddShopScreen({
    super.key,
    this.initialRouteId,
    this.existingShop,
  });

  @override
  State<AddShopScreen> createState() => _AddShopScreenState();
}

class _AddShopScreenState extends State<AddShopScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _ownerController = TextEditingController();

  String? _selectedRouteId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingShop != null) {
      final s = widget.existingShop!;
      _nameController.text = s.name;
      _mobileController.text = s.mobileNumber;
      _addressController.text = s.address;
      _ownerController.text = s.ownerName ?? '';
      _selectedRouteId = s.routeId;
    } else {
      _selectedRouteId = widget.initialRouteId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _ownerController.dispose();
    super.dispose();
  }

  Future<void> _deleteShop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.balanceDueColor),
            SizedBox(width: 8),
            Text('Delete Store?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${widget.existingShop!.name}"?\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.balanceDueColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Store', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final provider = context.read<CollectionProvider>();
      await provider.deleteShop(widget.existingShop!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Store "${widget.existingShop!.name}" deleted.'),
            backgroundColor: AppTheme.balanceDueColor,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRouteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or create a beat route first')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final provider = context.read<CollectionProvider>();
    final route = provider.routes.firstWhere(
      (r) => r.id == _selectedRouteId,
      orElse: () => RouteModel(id: _selectedRouteId!, name: 'General'),
    );

    if (widget.existingShop != null) {
      final updatedShop = widget.existingShop!.copyWith(
        name: _nameController.text.trim(),
        routeId: route.id,
        routeName: route.name,
        mobileNumber: _mobileController.text.trim(),
        address: _addressController.text.trim(),
        ownerName: _ownerController.text.trim().isEmpty ? null : _ownerController.text.trim(),
      );
      await provider.updateShop(updatedShop);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Store "${updatedShop.name}" updated successfully!'),
            backgroundColor: AppTheme.secondary,
          ),
        );
        Navigator.pop(context, updatedShop);
      }
    } else {
      final newShop = await provider.addShop(
        name: _nameController.text.trim(),
        routeId: route.id,
        routeName: route.name,
        mobileNumber: _mobileController.text.trim(),
        address: _addressController.text.trim(),
        ownerName: _ownerController.text.trim().isEmpty ? null : _ownerController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Store "${newShop.name}" added to ${route.name}!'),
            backgroundColor: AppTheme.secondary,
          ),
        );
        Navigator.pop(context, newShop);
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

    final isEdit = widget.existingShop != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Outlet' : 'Add Outlet'),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: 'Delete Store',
              onPressed: _isSaving ? null : _deleteShop,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Route Selection Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ASSIGN TO SALES BEAT / ROUTE *',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
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
                                setState(() {
                                  _selectedRouteId = newRoute.id;
                                });
                              }
                            },
                            child: Row(
                              children: const [
                                Icon(Icons.add, size: 14, color: AppTheme.secondary),
                                SizedBox(width: 4),
                                Text(
                                  'New Beat',
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
                      const SizedBox(height: 10),
                      if (routes.isEmpty)
                        const Text(
                          'No routes created yet. Click "+ New Beat" to create one (e.g. Chakan).',
                          style: TextStyle(color: AppTheme.balanceDueColor, fontSize: 13),
                        )
                      else
                        DropdownButtonFormField<String>(
                          key: ValueKey(_selectedRouteId),
                          initialValue: _selectedRouteId,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.alt_route, size: 20),
                            labelText: 'Beat Route',
                          ),
                          items: routes.map((r) {
                            return DropdownMenuItem<String>(
                              value: r.id,
                              child: Text('${r.name} (${provider.getShopsForRoute(r.id).length} registered stores)'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedRouteId = val;
                            });
                          },
                          validator: (val) => val == null ? 'Please select a beat' : null,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Shop Details Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STORE / CUSTOMER PROFILE',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 0.8,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Store / Business Name *',
                          hintText: 'e.g. ATA Kirana',
                          prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter store name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _mobileController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Contact / Mobile Number *',
                          hintText: 'e.g. 9822012345',
                          prefixIcon: Icon(Icons.phone_outlined, size: 20),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter contact number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _addressController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Store Address / Location *',
                          hintText: 'e.g. Shop No 12, Main Bazaar, Chakan',
                          prefixIcon: Icon(Icons.place_outlined, size: 20),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter store address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _ownerController,
                        decoration: const InputDecoration(
                          labelText: 'Proprietor / Contact Person (Optional)',
                          hintText: 'e.g. Altaf Bhai',
                          prefixIcon: Icon(Icons.person_outline, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: Text(_isSaving
                    ? (widget.existingShop != null ? 'Updating...' : 'Registering...')
                    : (widget.existingShop != null ? 'Update Store Details' : 'Save Store Details')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isSaving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
