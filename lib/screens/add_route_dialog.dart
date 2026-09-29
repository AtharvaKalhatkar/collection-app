import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/collection_provider.dart';
import '../models/route_model.dart';
import '../utils/theme.dart';

class AddRouteDialog extends StatefulWidget {
  final RouteModel? existingRoute;

  const AddRouteDialog({super.key, this.existingRoute});

  @override
  State<AddRouteDialog> createState() => _AddRouteDialogState();
}

class _AddRouteDialogState extends State<AddRouteDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  bool _isSaving = false;

  bool get _isEdit => widget.existingRoute != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingRoute?.name ?? '');
    _descController = TextEditingController(text: widget.existingRoute?.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _deleteRoute() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Beat Route?'),
        content: Text(
          'Are you sure you want to delete "${widget.existingRoute!.name}"?\n\n'
          'Existing stores and collections attached to this route will remain intact.',
        ),
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
      setState(() => _isSaving = true);
      try {
        await context.read<CollectionProvider>().deleteRoute(widget.existingRoute!.id);
        if (mounted) {
          Navigator.pop(context, 'deleted');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Route "${widget.existingRoute!.name}" deleted'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting route: $e'), backgroundColor: AppTheme.error),
          );
        }
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final provider = context.read<CollectionProvider>();
    try {
      if (_isEdit) {
        final updated = widget.existingRoute!.copyWith(
          name: _nameController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
        );
        await provider.updateRoute(updated);
        if (mounted) {
          Navigator.pop(context, updated);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Route "${updated.name}" updated successfully!'),
              backgroundColor: AppTheme.secondary,
            ),
          );
        }
      } else {
        final newRoute = await provider.addRoute(
          name: _nameController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
        );
        if (mounted) {
          Navigator.pop(context, newRoute);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Route "${newRoute.name}" created successfully!'),
              backgroundColor: AppTheme.secondary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving route: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(_isEdit ? Icons.edit_road : Icons.alt_route, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(_isEdit ? 'Edit Beat Route' : 'Add New Route')),
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
              tooltip: 'Delete Route',
              onPressed: _isSaving ? null : _deleteRoute,
            ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Route / Area Name *',
                  hintText: 'e.g. Chakan, Bhosari, Talegaon',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a route name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Description / Landmark (Optional)',
                  hintText: 'e.g. Market Yard & Talegaon Chowk',
                  prefixIcon: Icon(Icons.info_outline),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isEdit ? 'Update Route' : 'Save Route'),
        ),
      ],
    );
  }
}
