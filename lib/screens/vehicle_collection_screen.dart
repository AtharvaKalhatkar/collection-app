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
import 'profile_screen.dart';

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

  late String _selectedVehicle;
  final TextEditingController _customVehicleCtrl = TextEditingController();
  bool _isCustomVehicle = false;

  // Multi-select fuel expenses (CNG, Petrol, Diesel, Toll / Other)
  static const List<String> _availableExpenseTypes = ['CNG', 'Petrol', 'Diesel', 'Toll / Other'];
  final Set<String> _selectedExpenseTypes = {'CNG'};
  final Map<String, TextEditingController> _expenseAmountControllers = {
    'CNG': TextEditingController(text: '0'),
    'Petrol': TextEditingController(text: '0'),
    'Diesel': TextEditingController(text: '0'),
    'Toll / Other': TextEditingController(text: '0'),
  };

  // Cash Denomination Counter controllers
  static const List<String> _noteDenominations = ['500', '200', '100', '50', '20', '10'];
  final Map<String, TextEditingController> _denomControllers = {
    '500': TextEditingController(text: '0'),
    '200': TextEditingController(text: '0'),
    '100': TextEditingController(text: '0'),
    '50': TextEditingController(text: '0'),
    '20': TextEditingController(text: '0'),
    '10': TextEditingController(text: '0'),
    'coins': TextEditingController(text: '0'),
  };

  // Employee Name & Handover
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

    // Default: initialize with 2 blank bill rows
    _billRows.add(_BillRowController());
    _billRows.add(_BillRowController());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<CollectionProvider>();
      final auth = context.read<AuthProvider>();

      final registeredVehicles = provider.vehicles;
      if (widget.initialVehicleNo != null &&
          registeredVehicles.contains(widget.initialVehicleNo)) {
        _selectedVehicle = widget.initialVehicleNo!;
      } else if (registeredVehicles.isNotEmpty) {
        _selectedVehicle = registeredVehicles.first;
      } else {
        _selectedVehicle = 'MH 14 HG 2426';
      }

      final currentUserName = auth.currentUser?.name ?? provider.salesmanName;
      if (currentUserName.trim().isNotEmpty) {
        _employeeNameCtrl.text = currentUserName;
      } else if (provider.employees.isNotEmpty) {
        _employeeNameCtrl.text = provider.employees.first;
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
    for (final ctrl in _expenseAmountControllers.values) {
      ctrl.dispose();
    }
    for (final ctrl in _denomControllers.values) {
      ctrl.dispose();
    }
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
        if (provider.vehicles.contains(existing.vehicleNo)) {
          _selectedVehicle = existing.vehicleNo;
          _isCustomVehicle = false;
        } else {
          _isCustomVehicle = true;
          _customVehicleCtrl.text = existing.vehicleNo;
        }

        // Restore expenses
        _selectedExpenseTypes.clear();
        for (final ctrl in _expenseAmountControllers.values) {
          ctrl.text = '0';
        }

        if (existing.expenses.isNotEmpty) {
          for (final exp in existing.expenses) {
            _selectedExpenseTypes.add(exp.type);
            if (_expenseAmountControllers.containsKey(exp.type)) {
              _expenseAmountControllers[exp.type]!.text =
                  exp.amount > 0 ? exp.amount.toStringAsFixed(0) : '0';
            }
          }
        } else if (existing.expenseAmount > 0) {
          // Backward compatibility
          final type = existing.expenseType.isNotEmpty ? existing.expenseType : 'CNG';
          _selectedExpenseTypes.add(type);
          if (_expenseAmountControllers.containsKey(type)) {
            _expenseAmountControllers[type]!.text = existing.expenseAmount.toStringAsFixed(0);
          }
        }

        if (_selectedExpenseTypes.isEmpty) {
          _selectedExpenseTypes.add('CNG');
        }

        // Restore denominations if present
        if (existing.denominations != null) {
          existing.denominations!.forEach((k, v) {
            if (_denomControllers.containsKey(k)) {
              _denomControllers[k]!.text = v > 0 ? v.toString() : '0';
            }
          });
        }

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

  List<VehicleExpenseEntry> get _activeExpenses {
    final list = <VehicleExpenseEntry>[];
    for (final type in _selectedExpenseTypes) {
      final ctrl = _expenseAmountControllers[type];
      final amt = ctrl != null ? (double.tryParse(ctrl.text.trim()) ?? 0.0) : 0.0;
      if (amt > 0) {
        list.add(VehicleExpenseEntry(type: type, amount: amt));
      }
    }
    return list;
  }

  double get _totalExpensesAmount {
    double sum = 0.0;
    for (final type in _selectedExpenseTypes) {
      final ctrl = _expenseAmountControllers[type];
      if (ctrl != null) {
        sum += (double.tryParse(ctrl.text.trim()) ?? 0.0);
      }
    }
    return sum;
  }

  double get _netHandoverAmount {
    return _totalBillsAmount - _totalExpensesAmount;
  }

  int get _countedCashTotal {
    int sum = 0;
    for (final k in _noteDenominations) {
      final count = int.tryParse(_denomControllers[k]!.text.trim()) ?? 0;
      sum += count * int.parse(k);
    }
    final coins = int.tryParse(_denomControllers['coins']!.text.trim()) ?? 0;
    sum += coins;
    return sum;
  }

  Map<String, int> get _denominationsMap {
    final map = <String, int>{};
    for (final entry in _denomControllers.entries) {
      final count = int.tryParse(entry.value.text.trim()) ?? 0;
      if (count > 0) {
        map[entry.key] = count;
      }
    }
    return map;
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

  void _incrementDenom(String key) {
    final cur = int.tryParse(_denomControllers[key]!.text.trim()) ?? 0;
    setState(() {
      _denomControllers[key]!.text = (cur + 1).toString();
    });
  }

  void _decrementDenom(String key) {
    final cur = int.tryParse(_denomControllers[key]!.text.trim()) ?? 0;
    if (cur > 0) {
      setState(() {
        _denomControllers[key]!.text = (cur - 1).toString();
      });
    }
  }

  void _clearDenominations() {
    setState(() {
      for (final ctrl in _denomControllers.values) {
        ctrl.text = '0';
      }
    });
  }

  void _autoMatchDenominations() {
    // Helper to auto-distribute net handover amount into notes
    int remaining = _netHandoverAmount.round();
    if (remaining <= 0) return;

    final noteValues = [500, 200, 100, 50, 20, 10];
    final counts = <String, int>{};

    for (final v in noteValues) {
      final c = remaining ~/ v;
      counts[v.toString()] = c;
      remaining %= v;
    }
    counts['coins'] = remaining;

    setState(() {
      counts.forEach((k, v) {
        if (_denomControllers.containsKey(k)) {
          _denomControllers[k]!.text = v.toString();
        }
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Auto-filled notes breakdown to match Net Handover cash!'),
        duration: Duration(seconds: 2),
      ),
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
      expenses: _activeExpenses,
      bills: validBills,
      employeeName: empName,
      receivedByName: recName,
      remarks: _remarksCtrl.text.trim().isNotEmpty ? _remarksCtrl.text.trim() : null,
      denominations: _denominationsMap,
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
                          'Daily Vehicle Handover Slip',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Slip copied to clipboard! Share directly with Owner',
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
                constraints: const BoxConstraints(maxHeight: 220),
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
                      fontSize: 11.5,
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
                        'Daily Vehicle Slips History',
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
                          final expenseSummary = item.expenses.isNotEmpty
                              ? item.expenses.map((e) => '${e.type}: -₹${e.amount.toStringAsFixed(0)}').join(', ')
                              : (item.expenseAmount > 0
                                  ? '${item.expenseType}: -₹${item.expenseAmount.toStringAsFixed(0)}'
                                  : 'No Expenses');

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
                                '$dStr • ${item.billsCount} bills\n$expenseSummary • By: ${item.employeeName}',
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
    final provider = context.watch<CollectionProvider>();
    final registeredVehicles = provider.vehicles;
    final registeredEmployees = provider.employees;
    final dateStr = DateFormat('dd MMM yyyy').format(_selectedDate);

    // Ensure selected vehicle is valid
    if (!_isCustomVehicle && !registeredVehicles.contains(_selectedVehicle) && registeredVehicles.isNotEmpty) {
      _selectedVehicle = registeredVehicles.first;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Daily Vehicle Collection'),
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
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode Switcher: Denominations vs Daily Vehicle Collection
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
                              'Cash Counter',
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
                            'Daily Vehicle',
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ProfileScreen()),
                          );
                        },
                        child: const Text(
                          '⚙️ Manage in Settings',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                        ),
                      ),
                    ],
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
                                ...registeredVehicles.map((v) => DropdownMenuItem(
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

            // Row 2: Multi-select Fuel & Vehicle Expenses (CNG + Petrol + Diesel + Other)
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
                      const Row(
                        children: [
                          Icon(Icons.local_gas_station_rounded, size: 16, color: Color(0xFFF59E0B)),
                          SizedBox(width: 6),
                          Text(
                            'FUEL & VEHICLE EXPENSES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Total: -${CurrencyFormatter.format(_totalExpensesAmount)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Multi-select fuel filled today (commercial vans can fill both CNG & Petrol):',
                    style: TextStyle(fontSize: 11.5, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 10),

                  // Multi-select Expense Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _availableExpenseTypes.map((type) {
                      final isSelected = _selectedExpenseTypes.contains(type);
                      return FilterChip(
                        selected: isSelected,
                        label: Text(type),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : const Color(0xFF334155),
                        ),
                        selectedColor: type == 'CNG'
                            ? const Color(0xFF10B981)
                            : (type == 'Petrol' ? const Color(0xFFF59E0B) : const Color(0xFF0284C7)),
                        checkmarkColor: Colors.white,
                        backgroundColor: Colors.grey.shade100,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? Colors.transparent : Colors.grey.shade300,
                          ),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedExpenseTypes.add(type);
                            } else {
                              if (_selectedExpenseTypes.length > 1) {
                                _selectedExpenseTypes.remove(type);
                                _expenseAmountControllers[type]?.text = '0';
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('At least one fuel/expense category must be selected (set to ₹0 if none).'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // Amount Inputs for each active expense type
                  ..._selectedExpenseTypes.map((type) {
                    final ctrl = _expenseAmountControllers[type]!;
                    Color badgeColor = const Color(0xFF10B981);
                    IconData badgeIcon = Icons.local_gas_station_rounded;

                    if (type == 'Petrol') {
                      badgeColor = const Color(0xFFF59E0B);
                    } else if (type == 'Diesel') {
                      badgeColor = const Color(0xFF0284C7);
                    } else if (type == 'Toll / Other') {
                      badgeColor = const Color(0xFF64748B);
                      badgeIcon = Icons.toll_rounded;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Container(
                            width: 100,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(badgeIcon, size: 14, color: badgeColor),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    type,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      color: badgeColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: ctrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                              ],
                              decoration: InputDecoration(
                                labelText: '$type Amount (₹)',
                                prefixText: '₹ ',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          if (_selectedExpenseTypes.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                              tooltip: 'Remove $type',
                              onPressed: () {
                                setState(() {
                                  _selectedExpenseTypes.remove(type);
                                  ctrl.text = '0';
                                });
                              },
                            ),
                        ],
                      ),
                    );
                  }),
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
                  const Row(
                    children: [
                      Expanded(
                        flex: 11,
                        child: Text(
                          'Bill No.',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        flex: 11,
                        child: Text(
                          'Bill Amount (₹)',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                        ),
                      ),
                      SizedBox(width: 36),
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
                          // Bill Number Field (Hint changed from 'Bill #1' to 'Bill No.')
                          Expanded(
                            flex: 11,
                            child: TextField(
                              controller: row.billNoCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: 'Bill No.',
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
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('+ Add More Bills'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
                      ),
                      onPressed: () => _addBillRow(),
                    ),
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
                  // Breakdown of each expense
                  ..._selectedExpenseTypes.map((type) {
                    final ctrl = _expenseAmountControllers[type];
                    final amt = ctrl != null ? (double.tryParse(ctrl.text.trim()) ?? 0.0) : 0.0;
                    if (amt <= 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Expense ($type)',
                            style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5),
                          ),
                          Text(
                            '- ${CurrencyFormatter.format(amt)}',
                            style: const TextStyle(
                              color: Color(0xFFFCA5A5),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
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
                            'Target Physical Cash',
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

            // EMBEDDED CASH COUNTER UNDER THE TOTAL TO MATCH CASH
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.payments_rounded, color: Color(0xFF10B981), size: 18),
                          SizedBox(width: 6),
                          Text(
                            'CASH COUNTER (VERIFY & MATCH)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: Color(0xFF065F46),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          InkWell(
                            onTap: _autoMatchDenominations,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '⚡ Auto-Match',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: _clearDenominations,
                            child: const Text(
                              'Clear',
                              style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Count physical notes below to instantly match with Net Cash Handover:',
                    style: TextStyle(fontSize: 11.5, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 12),

                  // Denomination rows
                  ..._noteDenominations.map((denom) {
                    final ctrl = _denomControllers[denom]!;
                    final count = int.tryParse(ctrl.text.trim()) ?? 0;
                    final subtotal = count * int.parse(denom);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Container(
                            width: 64,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                '₹$denom',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('×', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 65,
                            child: TextField(
                              controller: ctrl,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.grey),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _decrementDenom(denom),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle, size: 18, color: Color(0xFF10B981)),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _incrementDenom(denom),
                          ),
                          const Spacer(),
                          Text(
                            CurrencyFormatter.format(subtotal.toDouble()),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }),

                  // Coins row
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Center(
                            child: Text(
                              'Coins',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('=', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _denomControllers['coins'],
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: 'Coins Total (₹)',
                              prefixText: '₹ ',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          CurrencyFormatter.format(
                              (double.tryParse(_denomControllers['coins']!.text.trim()) ?? 0.0)),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 16),

                  // Real-time verification match indicator
                  Builder(
                    builder: (context) {
                      final counted = _countedCashTotal;
                      final target = _netHandoverAmount.round();
                      final diff = counted - target;

                      if (counted == 0) {
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Enter notes count to verify physical cash against Net Handover of ${CurrencyFormatter.format(target.toDouble())}',
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (diff == 0) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF10B981)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '✅ PERFECT MATCH (₹0 DIFFERENCE)',
                                      style: TextStyle(
                                        color: Color(0xFF065F46),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    Text(
                                      'Counted ${CurrencyFormatter.format(counted.toDouble())} equals Net Handover.',
                                      style: const TextStyle(color: Color(0xFF047857), fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                CurrencyFormatter.format(counted.toDouble()),
                                style: const TextStyle(
                                  color: Color(0xFF059669),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final isShort = diff < 0;
                      final color = isShort ? const Color(0xFFDC2626) : const Color(0xFF2563EB);
                      final bgColor = isShort ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF);

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isShort ? Icons.warning_amber_rounded : Icons.info_outline,
                              color: color,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isShort
                                        ? '⚠️ CASH SHORTAGE: -${CurrencyFormatter.format(diff.abs().toDouble())}'
                                        : 'ℹ️ CASH SURPLUS: +${CurrencyFormatter.format(diff.toDouble())}',
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  Text(
                                    'Counted: ${CurrencyFormatter.format(counted.toDouble())} | Net Handover: ${CurrencyFormatter.format(target.toDouble())}',
                                    style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ProfileScreen()),
                          );
                        },
                        child: const Text(
                          '⚙️ Manage Staff',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Employee Name Field with Dropdown option if registered staff exist
                      Expanded(
                        child: registeredEmployees.isNotEmpty
                            ? Autocomplete<String>(
                                initialValue: TextEditingValue(text: _employeeNameCtrl.text),
                                optionsBuilder: (TextEditingValue val) {
                                  if (val.text.isEmpty) {
                                    return registeredEmployees;
                                  }
                                  return registeredEmployees.where((e) =>
                                      e.toLowerCase().contains(val.text.toLowerCase()));
                                },
                                onSelected: (String sel) {
                                  _employeeNameCtrl.text = sel;
                                },
                                fieldViewBuilder: (context, fieldCtrl, focusNode, onFieldSubmitted) {
                                  // Sync back
                                  fieldCtrl.addListener(() {
                                    _employeeNameCtrl.text = fieldCtrl.text;
                                  });
                                  return TextField(
                                    controller: fieldCtrl,
                                    focusNode: focusNode,
                                    decoration: InputDecoration(
                                      labelText: 'Employee Name',
                                      prefixIcon: const Icon(Icons.person_outline, size: 18),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  );
                                },
                              )
                            : TextField(
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
                      hintText: 'e.g. Route 4 collection, cash matched',
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
