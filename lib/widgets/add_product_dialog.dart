import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/order_model.dart';
import '../providers/collection_provider.dart';
import '../services/order_catalog_service.dart';
import '../utils/image_compress_helper.dart';
import '../utils/theme.dart';
import 'in_app_bill_camera_screen.dart';

class AddProductDialog extends StatefulWidget {
  final String? initialFirm;
  final String? initialCompany;
  final String? initialCategory;
  final String? initialSubcategory;

  const AddProductDialog({
    super.key,
    this.initialFirm,
    this.initialCompany,
    this.initialCategory,
    this.initialSubcategory,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();

  late String _firm;
  String? _selectedCompany;
  String? _selectedCategory;
  String? _selectedSubcategory;
  String _selectedUnit = 'Pcs';

  final _newCompanyController = TextEditingController();
  final _newCategoryController = TextEditingController();
  final _newSubcategoryController = TextEditingController();
  final _productNameController = TextEditingController();
  final _unitsPerCaseController = TextEditingController(text: '24');
  final _photoUrlController = TextEditingController();

  bool _isNewCompany = false;
  bool _isNewCategory = false;
  bool _isNewSubcategory = false;
  bool _showUrlField = false;
  bool _isSaving = false;
  String? _photoBase64;
  late final String _draftId = 'cust-${DateTime.now().millisecondsSinceEpoch}';

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
    } else {
      _selectedCompany = null;
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
    _updateSubcategories();
  }

  void _updateSubcategories() {
    final comp = _isNewCompany ? null : _selectedCompany;
    final cat = _isNewCategory ? null : _selectedCategory;
    final subcategories = OrderCatalogService.getSubcategories(_firm, comp, cat);
    if (widget.initialSubcategory != null && subcategories.contains(widget.initialSubcategory)) {
      _selectedSubcategory = widget.initialSubcategory;
    } else if (subcategories.isNotEmpty) {
      _selectedSubcategory = subcategories.first;
    } else {
      _selectedSubcategory = null;
    }
  }

  @override
  void dispose() {
    _newCompanyController.dispose();
    _newCategoryController.dispose();
    _newSubcategoryController.dispose();
    _productNameController.dispose();
    _unitsPerCaseController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const InAppBillCameraScreen(),
          fullscreenDialog: true,
        ),
      );
      if (result != null && mounted) {
        String? captured;
        if (result is List<String> && result.isNotEmpty) {
          captured = result.first;
        } else if (result is String && result.isNotEmpty) {
          captured = result;
        }
        if (captured != null) {
          final bytes = ImageCompressHelper.safeBase64Decode(captured);
          setState(() {
            _photoBase64 = bytes != null
                ? ImageCompressHelper.compressToBase64(bytes, maxDimension: 800, quality: 82)
                : captured;
          });
        }
      }
    } catch (_) {
      await _pickFromDevice(ImageSource.camera);
    }
  }

  Future<void> _pickFromDevice(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        final bytes = await picked.readAsBytes();
        final compressed = ImageCompressHelper.compressToBase64(
          bytes,
          maxDimension: 800,
          quality: 82,
        );
        setState(() {
          _photoBase64 = compressed;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not select photo: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    var popped = false;
    try {
      final company = _isNewCompany
          ? _newCompanyController.text.trim()
          : (_selectedCompany ?? _newCompanyController.text.trim());

      final category = _isNewCategory
          ? _newCategoryController.text.trim()
          : (_selectedCategory ?? _newCategoryController.text.trim());

      final rawSub = _isNewSubcategory
          ? _newSubcategoryController.text.trim()
          : (_selectedSubcategory ?? _newSubcategoryController.text.trim());
      final subcategory = rawSub.isNotEmpty ? rawSub : 'General';

      final name = _productNameController.text.trim();
      final parsedUpc = int.tryParse(_unitsPerCaseController.text.trim()) ?? 24;
      final unitsPerCase = parsedUpc > 0 ? parsedUpc : 24;
      final photoUrl = _photoUrlController.text.trim().isNotEmpty ? _photoUrlController.text.trim() : null;

      final newProduct = CatalogProduct(
        id: _draftId,
        name: name,
        category: category,
        subcategory: subcategory,
        company: company,
        firm: _firm,
        packing: _selectedUnit,
        rate: 0.0,
        mrp: 0.0,
        defaultUnit: _selectedUnit,
        unitsPerCase: unitsPerCase,
        weightKg: 0.0,
        photoUrl: photoUrl,
        photoBase64: _photoBase64,
      );

      final provider = Provider.of<CollectionProvider>(context, listen: false);
      await provider.addCustomProduct(newProduct);

      if (mounted) {
        popped = true;
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
    } finally {
      if (mounted && !popped) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingCompanies = OrderCatalogService.getCompanies(_firm);
    final existingCategories = (_selectedCompany != null && !_isNewCompany)
        ? OrderCatalogService.getCategories(_firm, _selectedCompany!)
        : <String>[];
    final existingSubcategories = OrderCatalogService.getSubcategories(
      _firm,
      _isNewCompany ? null : _selectedCompany,
      _isNewCategory ? null : _selectedCategory,
    );

    final Uint8List? previewBytes = _photoBase64 != null
        ? ImageCompressHelper.safeBase64Decode(_photoBase64)
        : null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
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
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

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
                              _isNewSubcategory = false;
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
                              _isNewSubcategory = false;
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
                  const SizedBox(height: 14),

                  // 2. Company Selection
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          '2. Company / Brand',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isNewCompany = !_isNewCompany;
                            if (_isNewCompany) {
                              _isNewCategory = true;
                            } else {
                              _isNewCategory = false;
                              _updateCategories();
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
                          _isNewSubcategory = false;
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
                      const Expanded(
                        child: Text(
                          '3. Category',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isNewCategory = !_isNewCategory;
                            _updateSubcategories();
                          });
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
                      onChanged: (val) => setState(() {
                        _selectedCategory = val;
                        _isNewSubcategory = false;
                        _updateSubcategories();
                      }),
                      validator: (val) {
                        if (!_isNewCategory && (val == null || val.isEmpty)) {
                          return 'Please select a category';
                        }
                        return null;
                      },
                    ),
                  const SizedBox(height: 14),

                  // 4. Subcategory Selection (+ New Subcategory toggle)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          '4. Subcategory',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() => _isNewSubcategory = !_isNewSubcategory);
                        },
                        child: Text(
                          _isNewSubcategory ? 'Choose Existing' : '+ New Subcategory',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_isNewSubcategory || existingSubcategories.isEmpty)
                    TextFormField(
                      controller: _newSubcategoryController,
                      decoration: InputDecoration(
                        hintText: 'e.g. NSB, NSP, or General',
                        prefixIcon: const Icon(Icons.subdirectory_arrow_right_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey('add_prod_sub_${_firm}_${_selectedCompany}_${_selectedCategory}_${existingSubcategories.contains(_selectedSubcategory) ? _selectedSubcategory : "none"}'),
                      initialValue: existingSubcategories.contains(_selectedSubcategory) ? _selectedSubcategory : null,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.subdirectory_arrow_right_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: existingSubcategories.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (val) => setState(() => _selectedSubcategory = val),
                    ),
                  const SizedBox(height: 14),

                  // 5. Product Name (include MRP/pack size directly in name if desired)
                  const Text('5. Product Name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _productNameController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Santoor White 100g (MRP 40)',
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

                  // 6. Packaging Unit & Units Per Case (CS)
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('6. Packaging Unit', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Units Per Case (CS)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _unitsPerCaseController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: '24',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 7. Add Photo (Camera / Gallery / Optional URL)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          '7. Product Photo (Optional)',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setState(() => _showUrlField = !_showUrlField),
                        child: Text(
                          _showUrlField ? 'Hide URL' : 'Use Image URL',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _capturePhoto,
                          icon: const Icon(Icons.camera_alt_outlined, size: 17),
                          label: const Text('Camera', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickFromDevice(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined, size: 17),
                          label: const Text('Gallery', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_showUrlField) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _photoUrlController,
                      decoration: InputDecoration(
                        hintText: 'https://... image link or direct photo URL',
                        prefixIcon: const Icon(Icons.link_rounded, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  if (previewBytes != null || _photoUrlController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      height: 96,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: previewBytes != null
                                  ? Image.memory(previewBytes, fit: BoxFit.contain, height: 92)
                                  : Image.network(
                                      _photoUrlController.text.trim(),
                                      fit: BoxFit.contain,
                                      height: 92,
                                      errorBuilder: (context, error, stackTrace) => const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.broken_image_outlined, size: 18, color: Colors.red),
                                          SizedBox(width: 6),
                                          Text('Cannot load image preview', style: TextStyle(color: Colors.red, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _photoBase64 = null;
                                  _photoUrlController.clear();
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
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
                          onPressed: _isSaving ? null : _onSave,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                          label: Text(
                            _isSaving ? 'Saving...' : 'Save Product',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.7),
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
