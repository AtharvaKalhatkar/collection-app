import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order_model.dart';
import '../providers/collection_provider.dart';
import '../services/order_catalog_service.dart';
import '../utils/theme.dart';

class AddProductDialog extends StatefulWidget {
  final String? initialFirm;
  final String? initialCompany;
  final String? initialCategory;

  const AddProductDialog({
    super.key,
    this.initialFirm,
    this.initialCompany,
    this.initialCategory,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();

  late String _firm;
  String? _selectedCompany;
  String? _selectedCategory;
  String _selectedUnit = 'Pcs';

  final _newCompanyController = TextEditingController();
  final _newCategoryController = TextEditingController();
  final _productNameController = TextEditingController();
  final _packingController = TextEditingController();
  final _rateController = TextEditingController();
  final _mrpController = TextEditingController();

  bool _isNewCompany = false;
  bool _isNewCategory = false;

  @override
  void initState() {
    super.initState();
    _firm = widget.initialFirm ?? OrderCatalogService.purva;
    _initCompanyAndCategory();
  }

  void _initCompanyAndCategory() {
    final companies = OrderCatalogService.getCompanies(_firm);
    if (widget.initialCompany != null && companies.contains(widget.initialCompany)) {
      _selectedCompany = widget.initialCompany;
    } else if (companies.isNotEmpty) {
      _selectedCompany = companies.first;
    }

    _updateCategories();
  }

  void _updateCategories() {
    if (_selectedCompany != null && !_isNewCompany) {
      final categories = OrderCatalogService.getCategories(_firm, _selectedCompany!);
      if (widget.initialCategory != null && categories.contains(widget.initialCategory)) {
        _selectedCategory = widget.initialCategory;
      } else if (categories.isNotEmpty) {
        _selectedCategory = categories.first;
      } else {
        _selectedCategory = null;
        _isNewCategory = true;
      }
    } else {
      _selectedCategory = null;
      _isNewCategory = true;
    }
  }

  @override
  void dispose() {
    _newCompanyController.dispose();
    _newCategoryController.dispose();
    _productNameController.dispose();
    _packingController.dispose();
    _rateController.dispose();
    _mrpController.dispose();
    super.dispose();
  }

  void _onSave() async {
    if (!_formKey.currentState!.validate()) return;

    final company = _isNewCompany
        ? _newCompanyController.text.trim()
        : (_selectedCompany ?? _newCompanyController.text.trim());

    final category = _isNewCategory
        ? _newCategoryController.text.trim()
        : (_selectedCategory ?? _newCategoryController.text.trim());

    final name = _productNameController.text.trim();
    final packing = _packingController.text.trim().isEmpty ? '1 Unit' : _packingController.text.trim();
    final rate = double.tryParse(_rateController.text.trim()) ?? 0.0;
    final mrp = double.tryParse(_mrpController.text.trim()) ?? rate;

    final customId = 'cust-${DateTime.now().millisecondsSinceEpoch}';

    final newProduct = CatalogProduct(
      id: customId,
      name: name,
      category: category,
      company: company,
      firm: _firm,
      packing: packing,
      rate: rate,
      mrp: mrp,
      defaultUnit: _selectedUnit,
    );

    final provider = Provider.of<CollectionProvider>(context, listen: false);
    await provider.addCustomProduct(newProduct);

    if (mounted) {
      Navigator.of(context).pop(newProduct);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Product "$name" added to catalog!')),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingCompanies = OrderCatalogService.getCompanies(_firm);
    final existingCategories = (_selectedCompany != null && !_isNewCompany)
        ? OrderCatalogService.getCategories(_firm, _selectedCompany!)
        : <String>[];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title Bar
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add_shopping_cart_rounded, color: AppTheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Add New Product / SKU',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // 1. Select Firm
                  const Text('1. Distributing Firm', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _firm = OrderCatalogService.purva;
                              _isNewCompany = false;
                              _isNewCategory = false;
                              _initCompanyAndCategory();
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _firm == OrderCatalogService.purva ? AppTheme.purvaPrimary : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _firm == OrderCatalogService.purva ? AppTheme.purvaPrimary : AppTheme.border,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'PURVA ENTERPRISES',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: _firm == OrderCatalogService.purva ? Colors.white : AppTheme.purvaText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _firm = OrderCatalogService.manas;
                              _isNewCompany = false;
                              _isNewCategory = false;
                              _initCompanyAndCategory();
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _firm == OrderCatalogService.manas ? AppTheme.manasPrimary : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _firm == OrderCatalogService.manas ? AppTheme.manasPrimary : AppTheme.border,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'MANAS SALES',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: _firm == OrderCatalogService.manas ? Colors.white : AppTheme.manasText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 2. Company Selection
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('2. Company / Brand', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isNewCompany = !_isNewCompany;
                            if (_isNewCompany) {
                              _isNewCategory = true;
                            }
                          });
                        },
                        child: Text(
                          _isNewCompany ? 'Choose Existing' : '+ New Company',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_isNewCompany)
                    TextFormField(
                      controller: _newCompanyController,
                      decoration: InputDecoration(
                        hintText: 'Enter new Company name (e.g. Parle, Nestle)',
                        prefixIcon: const Icon(Icons.business_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      validator: (val) {
                        if (_isNewCompany && (val == null || val.trim().isEmpty)) {
                          return 'Please enter company name';
                        }
                        return null;
                      },
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey('add_prod_company_${_firm}_${existingCompanies.contains(_selectedCompany) ? _selectedCompany : "none"}'),
                      initialValue: existingCompanies.contains(_selectedCompany) ? _selectedCompany : null,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.business_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: existingCompanies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedCompany = val;
                          _isNewCategory = false;
                          _updateCategories();
                        });
                      },
                      validator: (val) {
                        if (!_isNewCompany && (val == null || val.isEmpty)) {
                          return 'Please select a company';
                        }
                        return null;
                      },
                    ),
                  const SizedBox(height: 14),

                  // 3. Category Selection
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('3. Category', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                      InkWell(
                        onTap: () {
                          setState(() => _isNewCategory = !_isNewCategory);
                        },
                        child: Text(
                          _isNewCategory ? 'Choose Existing' : '+ New Category',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_isNewCategory || existingCategories.isEmpty)
                    TextFormField(
                      controller: _newCategoryController,
                      decoration: InputDecoration(
                        hintText: 'Enter new Category (e.g. Soap, Detergent, Ghee)',
                        prefixIcon: const Icon(Icons.category_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      validator: (val) {
                        if ((_isNewCategory || existingCategories.isEmpty) && (val == null || val.trim().isEmpty)) {
                          return 'Please enter category name';
                        }
                        return null;
                      },
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey('add_prod_category_${_firm}_${_selectedCompany}_${existingCategories.contains(_selectedCategory) ? _selectedCategory : "none"}'),
                      initialValue: existingCategories.contains(_selectedCategory) ? _selectedCategory : null,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.category_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: existingCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) => setState(() => _selectedCategory = val),
                      validator: (val) {
                        if (!_isNewCategory && (val == null || val.isEmpty)) {
                          return 'Please select a category';
                        }
                        return null;
                      },
                    ),
                  const SizedBox(height: 14),

                  // 4. Product Name
                  const Text('4. Product Name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _productNameController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Santoor White Soap, Dettol Original',
                      prefixIcon: const Icon(Icons.shopping_bag_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter product name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // 5. Packing & Unit
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('5. Packing Size', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _packingController,
                              decoration: InputDecoration(
                                hintText: 'e.g. 100g, 500ml, 1kg',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Packaging Unit', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              key: ValueKey('add_prod_unit_$_selectedUnit'),
                              initialValue: _selectedUnit,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                              items: OrderCatalogService.availableUnits
                                  .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontWeight: FontWeight.w600))))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedUnit = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 6. Rate & MRP
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Trade Rate (₹)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _rateController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                prefixText: '₹ ',
                                hintText: '0.00',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Enter rate';
                                if (double.tryParse(val.trim()) == null) return 'Invalid number';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('MRP (₹)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _mrpController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                prefixText: '₹ ',
                                hintText: '0.00',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _onSave,
                          icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                          label: const Text('Save Product', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
