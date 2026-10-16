import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/vehicle_collection_model.dart';
import '../providers/collection_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import 'cash_handover_screen.dart';

class VehicleCollectionScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialVehicleNo;

  const VehicleCollectionScreen({
    super.key,
    this.initialDate,
    this.initialVehicleNo,
  });

  @override
  State<VehicleCollectionScreen> createState() => _VehicleCollectionScreenState();
}

class _BillRowController {
  final TextEditingController billNoCtrl;
  final TextEditingController amountCtrl;
  final TextEditingController shopNameCtrl;

  _BillRowController({String billNo = '', String amount = '', String shopName = ''})
      : billNoCtrl = TextEditingController(text: billNo),
        amountCtrl = TextEditingController(text: amount),
        shopNameCtrl = TextEditingController(text: shopName);

  void dispose() {
    billNoCtrl.dispose();
    amountCtrl.dispose();
    shopNameCtrl.dispose();
  }
}

class _VehicleCollectionScreenState extends State<VehicleCollectionScreen> {
  late DateTime _selectedDate;

  // The 3 predefined vehicles requested by user
  static const List<String> _defaultVehicles = [
    'MH 14 HG 2426',
    'MH 14 GD 6212',
    'MH 14 KA 2059',
  ];

  late String _selectedVehicle;
  final TextEditingController _customVehicleCtrl = TextEditingController();
  bool _isCustomVehicle = false;

  // Expense dropdown: CNG, Petrol, Diesel, None
  static const List<String> _expenseTypes = ['CNG', 'Petrol', 'Diesel', 'None'];
  String _selectedExpenseType = 'CNG';
  final TextEditingController _expenseAmountCtrl = TextEditingController(text: '0');

  // Employee Name
  final TextEditingController _employeeNameCtrl = TextEditingController();
  final TextEditingController _receivedByCtrl = TextEditingController(text: 'Office / Owner');
  final TextEditingController _remarksCtrl = TextEditingController();

  // Dynamic Bill Entries
  final List<_BillRowController> _billRows = [];

  final Uuid _uuid = const Uuid();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();

    if (widget.initialVehicleNo != null &&
        _defaultVehicles.contains(widget.initialVehicleNo)) {
      _selectedVehicle = widget.initialVehicleNo!;
    } else {
      _selectedVehicle = _defaultVehicles.first;
    }

    // Default: initialize with 2 blank bill rows
    _billRows.add(_BillRowController());
    _billRows.add(_BillRowController());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final provider = context.read<CollectionProvider>();
      final currentUserName = auth.currentUser?.name ?? provider.salesmanName;
      if (currentUserName.trim().isNotEmpty) {
        _employeeNameCtrl.text = currentUserName;
      } else {
        _employeeNameCtrl.text = 'Akash';
      }

      // Check if existing record exists for this date and vehicle
      _loadExistingIfAny();
    });
  }

  @override
  void dispose() {
    _customVehicleCtrl.dispose();
    _expenseAmountCtrl.dispose();
    _employeeNameCtrl.dispose();
    _receivedByCtrl.dispose();
    _remarksCtrl.dispose();
    for (final row in _billRows) {
      row.dispose();
    }
    super.dispose();
  }

  void _loadExistingIfAny() {
    final provider = context.read<CollectionProvider>();
    final existing = provider.getLatestVehicleCollectionForDate(
      _selectedDate,
      vehicleNo: _effectiveVehicleNo,
    );

    if (existing != null) {
      setState(() {
        if (_defaultVehicles.contains(existing.vehicleNo)) {
          _selectedVehicle = existing.vehicleNo;
          _isCustomVehicle = false;
        } else {
          _isCustomVehicle = true;
          _customVehicleCtrl.text = existing.vehicleNo;
        }

        _selectedExpenseType = existing.expenseType;
        _expenseAmountCtrl.text = existing.expenseAmount > 0
            ? existing.expenseAmount.toStringAsFixed(0)
            : '0';

        if (existing.employeeName.isNotEmpty) {
          _employeeNameCtrl.text = existing.employeeName;
        }
        if (existing.receivedByName.isNotEmpty) {
          _receivedByCtrl.text = existing.receivedByName;
        }
        _remarksCtrl.text = existing.remarks ?? '';

        // Clear and reload bill rows
        for (final row in _billRows) {
          row.dispose();
        }
        _billRows.clear();

        if (existing.bills.isNotEmpty) {
          for (final b in existing.bills) {
            _billRows.add(_BillRowController(
              billNo: b.billNumber,
              amount: b.amount > 0 ? b.amount.toStringAsFixed(0) : '',
              shopName: b.shopName ?? '',
            ));
          }
        } else {
          _billRows.add(_BillRowController());
        }
      });
    }
  }

  String get _effectiveVehicleNo {
    if (_isCustomVehicle && _customVehicleCtrl.text.trim().isNotEmpty) {
      return _customVehicleCtrl.text.trim().toUpperCase();
    }
    return _selectedVehicle;
  }

  double get _totalBillsAmount {
    double sum = 0.0;
    for (final row in _billRows) {
      final amt = double.tryParse(row.amountCtrl.text.trim()) ?? 0.0;
      sum += amt;
    }
    return sum;
  }

  double get _expenseAmount {
    if (_selectedExpenseType == 'None') return 0.0;
    return double.tryParse(_expenseAmountCtrl.text.trim()) ?? 0.0;
  }

  double get _netHandoverAmount {
    return _totalBillsAmount - _expenseAmount;
  }

  int get _validBillsCount {
    return _billRows.where((r) =>
        r.billNoCtrl.text.trim().isNotEmpty ||
        (double.tryParse(r.amountCtrl.text.trim()) ?? 0.0) > 0).length;
  }

  void _addBillRow({String billNo = '', String amount = '', String shopName = ''}) {
    setState(() {
      _billRows.add(_BillRowController(billNo: billNo, amount: amount, shopName: shopName));
    });
  }

  void _removeBillRow(int index) {
    if (_billRows.length <= 1) {
      // Clear instead of removing last row
      _billRows[0].billNoCtrl.clear();
      _billRows[0].amountCtrl.clear();
      _billRows[0].shopNameCtrl.clear();
      setState(() {});
      return;
    }
    setState(() {
      final removed = _billRows.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _loadExistingIfAny();
    }
  }

  void _pickFromExistingBills() {
    final provider = context.read<CollectionProvider>();
    final todayCollections = provider.getFilteredCollections(forDate: _selectedDate);

    if (todayCollections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No recorded collections found for this date. Enter bills manually.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pick From Today\'s Bills',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Text(
                'Tap any bill to add it to your vehicle collection entries:',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: todayCollections.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final item = todayCollections[idx];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${item.shopName} (Bill #${item.billNumber})',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                      subtitle: Text(
                        '${item.routeName} • ${item.businessName}',
                        style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                      ),
                      trailing: Text(
                        CurrencyFormatter.format(item.collectedAmount),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppTheme.primary,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _addBillRow(
                          billNo: item.billNumber,
                          amount: item.collectedAmount.toStringAsFixed(0),
                          shopName: item.shopName,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  VehicleCollectionModel _buildModel() {
    final validBills = <VehicleBillEntry>[];
    for (final row in _billRows) {
      final bNo = row.billNoCtrl.text.trim();
      final amt = double.tryParse(row.amountCtrl.text.trim()) ?? 0.0;
      final shop = row.shopNameCtrl.text.trim();
      if (bNo.isNotEmpty || amt > 0) {
        validBills.add(VehicleBillEntry(
          billNumber: bNo.isEmpty ? 'N/A' : bNo,
          amount: amt,
          shopName: shop.isNotEmpty ? shop : null,
        ));
      }
    }

    final empName = _employeeNameCtrl.text.trim().isNotEmpty
        ? _employeeNameCtrl.text.trim()
        : 'Akash';
    final recName = _receivedByCtrl.text.trim().isNotEmpty
        ? _receivedByCtrl.text.trim()
        : 'Office / Owner';

    return VehicleCollectionModel(
      id: _uuid.v4(),
      date: _selectedDate,
      vehicleNo: _effectiveVehicleNo,
      expenseType: _selectedExpenseType,
      expenseAmount: _expenseAmount,
      bills: validBills,
      employeeName: empName,
      receivedByName: recName,
      remarks: _remarksCtrl.text.trim().isNotEmpty ? _remarksCtrl.text.trim() : null,
    );
  }

  Future<void> _saveEntry({bool showToast = true}) async {
    setState(() => _isSaving = true);
    try {
      final model = _buildModel();
      await context.read<CollectionProvider>().saveVehicleCollection(model);

      if (mounted && showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Saved! Net Cash: ${CurrencyFormatter.format(model.netHandoverAmount)} (${model.vehicleNo})',
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handoverAndShareWhatsApp() async {
    await _saveEntry(showToast: false);
    final model = _buildModel();
    final text = model.generateWhatsAppText();

    // Copy to clipboard
    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.send_rounded, color: Color(0xFF25D366), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vehicle Collection Handover',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Copied to clipboard! Share directly with Owner',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy Slip'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard!')),
                        );
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('WhatsApp'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final encoded = Uri.encodeComponent(text);
                        final whatsappUrl = Uri.parse('whatsapp://send?text=$encoded');
                        final webUrl = Uri.parse('https://api.whatsapp.com/send?text=$encoded');

                        try {
                          if (await canLaunchUrl(whatsappUrl)) {
                            await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
                          } else {
                            await launchUrl(webUrl, mode: LaunchMode.externalApplication);
                          }
                        } catch (_) {
                          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showHistoryModal(BuildContext context) {
    final provider = context.read<CollectionProvider>();
    final history = provider.vehicleCollections;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.history_rounded, color: AppTheme.primary, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Vehicle Collection History',
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
              const Divider(height: 1),
              const SizedBox(height: 8),
              Expanded(
                child: history.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.local_shipping_outlined,
                                size: 48, color: Colors.blueGrey.shade200),
                            const SizedBox(height: 10),
                            Text(
                              'No vehicle collection slips recorded yet.',
                              style: TextStyle(color: Colors.blueGrey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: history.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final item = history[idx];
                          final dStr = DateFormat('dd MMM yyyy, hh:mm a').format(item.createdAt);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.local_shipping_rounded,
                                  color: Color(0xFF10B981), size: 22),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.vehicleNo,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.format(item.netHandoverAmount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                '$dStr • ${item.billsCount} bills • ${item.expenseType}: -${CurrencyFormatter.format(item.expenseAmount)} • By: ${item.employeeName}',
                                style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade700),
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18),
                              onSelected: (val) async {
                                if (val == 'share') {
                                  final txt = item.generateWhatsAppText();
                                  Clipboard.setData(ClipboardData(text: txt));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('WhatsApp slip copied!')),
                                  );
                                } else if (val == 'delete') {
                                  await provider.deleteVehicleCollection(item.id);
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                  }
                                  if (context.mounted) {
                                    _showHistoryModal(context);
                                  }
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'share',
                                  child: Row(
                                    children: [
                                      Icon(Icons.copy, size: 16),
                                      SizedBox(width: 8),
                                      Text('Copy WhatsApp Text'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, color: Colors.red, size: 16),
                                      SizedBox(width: 8),
                                      Text('Delete Slip', style: TextStyle(color: Colors.red)),
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd MMM yyyy').format(_selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Vehicle Collection'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Slip History',
            onPressed: () => _showHistoryModal(context),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_rounded),
            tooltip: 'Pick from Today\'s Bills',
            onPressed: _pickFromExistingBills,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode Switcher: Denominations vs Vehicle Collection
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CashHandoverScreen(
                              initialDate: _selectedDate,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.payments_outlined, color: Color(0xFF10B981), size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Denominations',
                              style: TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.local_shipping_outlined, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Vehicle Collection',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Row 1: Date & Vehicle Number (side by side in front of each other)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DATE & VEHICLE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Date Selector
                      Expanded(
                        flex: 11,
                        child: InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_month_outlined, size: 16, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Date', style: TextStyle(fontSize: 10, color: Colors.blueGrey)),
                                      Text(
                                        dateStr,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Vehicle Dropdown (in front of Date)
                      Expanded(
                        flex: 13,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _isCustomVehicle ? 'OTHER' : _selectedVehicle,
                              icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                              items: [
                                ..._defaultVehicles.map((v) => DropdownMenuItem(
                                      value: v,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.local_shipping_outlined,
                                              size: 15, color: Color(0xFF10B981)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              v,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12.5,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                                const DropdownMenuItem(
                                  value: 'OTHER',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_note_rounded, size: 15, color: Colors.blueGrey),
                                      SizedBox(width: 6),
                                      Text(
                                        '+ Other Vehicle',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  if (val == 'OTHER') {
                                    _isCustomVehicle = true;
                                  } else {
                                    _isCustomVehicle = false;
                                    _selectedVehicle = val;
                                  }
                                });
                                _loadExistingIfAny();
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isCustomVehicle) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _customVehicleCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Custom Vehicle Number',
                        hintText: 'e.g. MH 14 XX 1234',
                        isDense: true,
                        prefixIcon: const Icon(Icons.directions_car_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Row 2: Expenses Dropdown (CNG, Petrol, Diesel, None) & Expense Amount
            Container(
              padding: const EdgeInsets.all(14),
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
                      Icon(Icons.local_gas_station_rounded, size: 15, color: Color(0xFFF59E0B)),
                      SizedBox(width: 6),
                      Text(
                        'VEHICLE EXPENSES & FUEL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Fuel / Expense Dropdown
                      Expanded(
                        flex: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _selectedExpenseType,
                              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFF59E0B)),
                              items: _expenseTypes.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(
                                    type,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedExpenseType = val;
                                    if (val == 'None') {
                                      _expenseAmountCtrl.text = '0';
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Expense Amount Input
                      Expanded(
                        flex: 12,
                        child: TextField(
                          controller: _expenseAmountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                          decoration: InputDecoration(
                            labelText: 'Expense Amount',
                            prefixText: '₹ ',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Row 3: Multiple Entries of Bill No and Amount
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.receipt_long_outlined, size: 16, color: AppTheme.primary),
                          const SizedBox(width: 6),
                          const Text(
                            'BILL-WISE COLLECTIONS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$_validBillsCount Bills',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.add_circle_outline, size: 14, color: AppTheme.primary),
                        label: const Text(
                          '+ Add Row',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                        onPressed: () => _addBillRow(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Header for Bill list
                  Row(
                    children: [
                      const Expanded(
                        flex: 11,
                        child: Text(
                          'Bill No.',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        flex: 11,
                        child: Text(
                          'Bill Amount (₹)',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                        ),
                      ),
                      const SizedBox(width: 36),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Dynamic list of Bill Rows
                  ...List.generate(_billRows.length, (index) {
                    final row = _billRows[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          // Bill Number Field
                          Expanded(
                            flex: 11,
                            child: TextField(
                              controller: row.billNoCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: 'Bill #${index + 1}',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Amount Field
                          Expanded(
                            flex: 11,
                            child: TextField(
                              controller: row.amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                              ],
                              decoration: InputDecoration(
                                hintText: '₹ Amount',
                                prefixText: '₹ ',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),

                          // Delete / Remove Row Button
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                            tooltip: 'Remove Row',
                            onPressed: () => _removeBillRow(index),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('+ Add More Bills'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
                          ),
                          onPressed: () => _addBillRow(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.playlist_add_rounded, size: 16),
                        label: const Text('Pick Bills'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          foregroundColor: Colors.blueGrey.shade800,
                        ),
                        onPressed: _pickFromExistingBills,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Live Calculation Card: Auto Total of Bills minus Expenses
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Bills ($_validBillsCount)',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      Text(
                        '+ ${CurrencyFormatter.format(_totalBillsAmount)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Fuel Expense ($_selectedExpenseType)',
                        style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
                      ),
                      Text(
                        '- ${CurrencyFormatter.format(_expenseAmount)}',
                        style: const TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NET CASH HANDOVER',
                            style: TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            'Physical Cash to Submit',
                            style: TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ],
                      ),
                      Text(
                        CurrencyFormatter.format(_netHandoverAmount),
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Employee Name & Handover and Save Options
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EMPLOYEE & HANDOVER DETAILS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Employee Name Field
                      Expanded(
                        child: TextField(
                          controller: _employeeNameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Employee Name',
                            prefixIcon: const Icon(Icons.person_outline, size: 18),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Handover To (Office / Owner)
                      Expanded(
                        child: TextField(
                          controller: _receivedByCtrl,
                          decoration: InputDecoration(
                            labelText: 'Handover To',
                            prefixIcon: const Icon(Icons.business_center_outlined, size: 18),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _remarksCtrl,
                    decoration: InputDecoration(
                      labelText: 'Remarks / Notes (Optional)',
                      hintText: 'e.g. Route 4 collection, fuel bill attached',
                      prefixIcon: const Icon(Icons.notes_rounded, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Handover and Save Options (next to each other)
                  Row(
                    children: [
                      // Save Option
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(_isSaving ? 'Saving...' : 'Save Entry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isSaving ? null : () => _saveEntry(showToast: true),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Handover Option
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Handover & Share'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isSaving ? null : _handoverAndShareWhatsApp,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
