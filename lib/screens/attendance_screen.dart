import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/attendance_record.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';

/// Access restriction: Only SuperAdmin, Office staff, and Akash (salesman)
bool canViewAttendance(UserModel? user) {
  if (user == null) return false;
  return user.isSuperAdmin ||
      user.isOffice ||
      user.name.toLowerCase().trim() == 'akash' ||
      user.name.toLowerCase().trim().contains('akash');
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<AttendanceEmployee> _employees = [];
  List<AttendanceRecord> _records = [];
  List<SalaryMonthlyAdjustment> _adjustments = [];
  String? _selectedEmployeeId; // null = all staff
  bool _isLoading = false;

  // Live timer for self check-in card
  Timer? _ticker;
  DateTime _now = DateTime.now();
  AttendanceRecord? _myTodayRecord;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadAll();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final me = auth.currentUser;

    // Load attendance roster (merging from auth users if first time)
    final emps = await AttendanceService.loadEmployees(
      fallbackUsers: auth.users.where((u) => canViewAttendance(u) || u.isSalesman || u.isDriver).toList(),
    );

    // Filter roster if user is Akash (non-admin only sees themselves)
    final bool isAdmin = me != null && (me.isSuperAdmin || me.isOffice);
    List<AttendanceEmployee> visibleEmployees;
    if (isAdmin) {
      visibleEmployees = emps.where((e) => e.isActive).toList();
    } else {
      visibleEmployees = emps
          .where((e) =>
              e.id == me?.id ||
              e.name.toLowerCase().contains('akash') ||
              e.phone == me?.phone)
          .toList();
      if (visibleEmployees.isEmpty && me != null) {
        visibleEmployees = [
          AttendanceEmployee(
            id: me.id,
            name: me.name,
            role: me.roleDisplayName,
            phone: me.phone,
            monthlySalary: 20000,
          )
        ];
      }
    }

    final records = await AttendanceService.loadForMonth(
      _selectedMonth.year,
      _selectedMonth.month,
    );

    final adjs = await AttendanceService.loadAdjustments(
      _selectedMonth.year,
      _selectedMonth.month,
    );

    if (me != null) {
      _myTodayRecord =
          await AttendanceService.loadForUserAndDate(me.id, DateTime.now());
    }

    if (mounted) {
      setState(() {
        _employees = visibleEmployees;
        _records = records;
        _adjustments = adjs;
        if (_selectedEmployeeId == null && _employees.isNotEmpty) {
          // Default to first employee if not admin, or all if admin
          if (!isAdmin) {
            _selectedEmployeeId = _employees.first.id;
          }
        }
        _isLoading = false;
      });
    }
  }

  // Self check-in action
  Future<void> _doCheckIn() async {
    final me = context.read<AuthProvider>().currentUser;
    if (me == null) return;
    await AttendanceService.checkIn(me.id, me.name, me.roleDisplayName);
    await _loadAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Checked in successfully! Have a productive day.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  // Self check-out action
  Future<void> _doCheckOut() async {
    final me = context.read<AuthProvider>().currentUser;
    if (me == null) return;
    await AttendanceService.checkOut(me.id);
    await _loadAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('👋 Checked out successfully. Good work!'),
          backgroundColor: Color(0xFF0F172A),
        ),
      );
    }
  }

  // Admin marks attendance for a specific staff on a specific date
  void _openMarkStatusDialog(AttendanceEmployee staff, DateTime date) {
    final auth = context.read<AuthProvider>();
    final me = auth.currentUser;
    final bool isAdmin = me != null && (me.isSuperAdmin || me.isOffice);
    if (!isAdmin) return;

    final dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final existing = _records.cast<AttendanceRecord?>().firstWhere(
          (r) => r?.userId == staff.id && r?.dateKey == dateKey,
          orElse: () => null,
        );

    AttendanceStatus chosen = existing?.status ?? AttendanceStatus.present;
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Mark Attendance',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 2),
              Text(
                '${staff.name} · ${DateFormat("EEE, dd MMM yyyy").format(date)}',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...AttendanceStatus.values.map((s) {
                  Color col;
                  IconData ic;
                  switch (s) {
                    case AttendanceStatus.present:
                      col = const Color(0xFF16A34A);
                      ic = Icons.check_circle_outline;
                      break;
                    case AttendanceStatus.absent:
                      col = const Color(0xFFDC2626);
                      ic = Icons.cancel_outlined;
                      break;
                    case AttendanceStatus.halfDay:
                      col = const Color(0xFFD97706);
                      ic = Icons.timelapse;
                      break;
                    case AttendanceStatus.holiday:
                      col = const Color(0xFF7C3AED);
                      ic = Icons.celebration_outlined;
                      break;
                    case AttendanceStatus.leave:
                      col = const Color(0xFF0284C7);
                      ic = Icons.beach_access_outlined;
                      break;
                  }

                  final isSelected = chosen == s;
                  return InkWell(
                    onTap: () => setLocal(() => chosen = s),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? col.withValues(alpha: 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? col : Colors.grey.shade300,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(ic, color: col, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.label,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                color: isSelected ? col : Colors.black87,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check, color: col, size: 18),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: 'Optional Note / Reason',
                    hintText: 'e.g. Half-day personal work, Diwali off',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await AttendanceService.markStatus(
                  userId: staff.id,
                  staffName: staff.name,
                  staffRole: staff.role,
                  date: date,
                  status: chosen,
                  note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                );
                await _loadAll();
              },
              child: const Text('Save Entry'),
            ),
          ],
        ),
      ),
    );
  }

  // Quick mark Sundays as paid holidays
  Future<void> _autoMarkSundays() async {
    final auth = context.read<AuthProvider>();
    final me = auth.currentUser;
    final bool isAdmin = me != null && (me.isSuperAdmin || me.isOffice);
    if (!isAdmin) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark Sundays as Paid Off?'),
        content: Text(
          'This will automatically mark all Sundays in ${DateFormat("MMMM yyyy").format(_selectedMonth)} as Paid Holiday/Weekly Off for all active staff who don\'t already have an entry.\n\nSundays will be counted as paid in monthly salary.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark All Sundays'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final count = await AttendanceService.autoMarkSundaysAsHolidays(
        _selectedMonth.year,
        _selectedMonth.month,
        _employees,
      );
      await _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Marked $count Sunday entries as paid weekly off!'),
            backgroundColor: const Color(0xFF7C3AED),
          ),
        );
      }
    }
  }

  // Add new employee dialog
  void _openAddEmployeeDialog({AttendanceEmployee? toEdit}) {
    final isEditing = toEdit != null;
    final nameCtrl = TextEditingController(text: toEdit?.name ?? '');
    final phoneCtrl = TextEditingController(text: toEdit?.phone ?? '');
    final salaryCtrl = TextEditingController(
      text: toEdit != null ? toEdit.monthlySalary.toStringAsFixed(0) : '20000',
    );
    String selectedRole = toEdit?.role ?? 'Sales & Collection';

    final roles = [
      'Sales & Collection',
      'Delivery Driver',
      'Office Staff',
      'Super Admin',
      'Warehouse / Other',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isEditing ? 'Edit Employee Details' : 'Add Employee for Attendance',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Employee Name *',
                    hintText: 'e.g. Akash, Rahul, Ramesh',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: roles.contains(selectedRole) ? selectedRole : roles.first,
                  decoration: InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: roles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => selectedRole = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    hintText: 'e.g. 9876543210 (for WhatsApp slip)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: salaryCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Monthly Base Salary (₹) *',
                    hintText: 'e.g. 20000',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final salary = double.tryParse(salaryCtrl.text.trim()) ?? 15000.0;
                if (name.isEmpty) return;

                Navigator.pop(ctx);
                final emp = AttendanceEmployee(
                  id: toEdit?.id ?? 'emp_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  role: selectedRole,
                  phone: phoneCtrl.text.trim(),
                  monthlySalary: salary,
                  isActive: true,
                  isCustom: toEdit?.isCustom ?? true,
                  joinedAt: toEdit?.joinedAt ?? DateTime.now(),
                );
                final messenger = ScaffoldMessenger.of(context);
                await AttendanceService.saveEmployee(emp);
                await _loadAll();
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(isEditing
                          ? 'Updated ${emp.name}\'s profile'
                          : 'Added ${emp.name} to attendance roster'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                }
              },
              child: Text(isEditing ? 'Save Changes' : 'Add Employee'),
            ),
          ],
        ),
      ),
    );
  }

  // Remove employee
  Future<void> _confirmRemoveEmployee(AttendanceEmployee emp) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${emp.name}?'),
        content: Text(
          'Are you sure you want to remove ${emp.name} from the active attendance roster? Past attendance logs will be preserved.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AttendanceService.deleteEmployee(emp.id);
      await _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${emp.name} from roster'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  // Edit salary adjustment (bonus/advance)
  void _openSalaryAdjustmentDialog(AttendanceEmployee emp) {
    final adj = _adjustments.cast<SalaryMonthlyAdjustment?>().firstWhere(
          (a) => a?.employeeId == emp.id,
          orElse: () => null,
        );

    final bonusCtrl = TextEditingController(
      text: (adj?.bonus ?? 0.0) > 0 ? (adj!.bonus.toStringAsFixed(0)) : '',
    );
    final advCtrl = TextEditingController(
      text: (adj?.advanceDeduction ?? 0.0) > 0 ? (adj!.advanceDeduction.toStringAsFixed(0)) : '',
    );
    final noteCtrl = TextEditingController(text: adj?.note ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Bonus / Advance: ${emp.name}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Month: ${DateFormat("MMMM yyyy").format(_selectedMonth)}',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: bonusCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Incentive / Bonus (₹)',
                  hintText: 'e.g. 1000 for good collection',
                  prefixIcon: const Icon(Icons.card_giftcard, color: Colors.green),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: advCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Advance Taken (₹)',
                  hintText: 'e.g. 2000 taken during month',
                  prefixIcon: const Icon(Icons.money_off, color: Colors.red),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: InputDecoration(
                  labelText: 'Note',
                  hintText: 'e.g. Festival advance',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final bonus = double.tryParse(bonusCtrl.text.trim()) ?? 0.0;
              final adv = double.tryParse(advCtrl.text.trim()) ?? 0.0;
              final newAdj = SalaryMonthlyAdjustment(
                employeeId: emp.id,
                year: _selectedMonth.year,
                month: _selectedMonth.month,
                bonus: bonus,
                advanceDeduction: adv,
                isDisbursed: adj?.isDisbursed ?? false,
                disbursedAt: adj?.disbursedAt,
                paymentMode: adj?.paymentMode,
                note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              );
              await AttendanceService.saveAdjustment(newAdj);
              await _loadAll();
            },
            child: const Text('Save Adjustments'),
          ),
        ],
      ),
    );
  }

  // Toggle disbursed status
  Future<void> _toggleDisbursed(AttendanceEmployee emp, MonthlySalaryCalculation calc) async {
    final adj = _adjustments.cast<SalaryMonthlyAdjustment?>().firstWhere(
          (a) => a?.employeeId == emp.id,
          orElse: () => null,
        );

    final currentlyDisbursed = adj?.isDisbursed ?? false;
    String paymentMode = adj?.paymentMode ?? 'Cash';

    if (!currentlyDisbursed) {
      final selectedMode = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Mark Salary Disbursed to ${emp.name}'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'Cash'),
              child: const Row(children: [Icon(Icons.payments_outlined, color: Colors.green), SizedBox(width: 10), Text('Paid via Cash')]),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'Bank Transfer / UPI'),
              child: const Row(children: [Icon(Icons.account_balance, color: Colors.blue), SizedBox(width: 10), Text('Paid via Bank / UPI')]),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'Cash Handover'),
              child: const Row(children: [Icon(Icons.handshake_outlined, color: Colors.orange), SizedBox(width: 10), Text('Cash Handover Adjustment')]),
            ),
          ],
        ),
      );
      if (selectedMode == null) return;
      paymentMode = selectedMode;
    }

    final newAdj = SalaryMonthlyAdjustment(
      employeeId: emp.id,
      year: _selectedMonth.year,
      month: _selectedMonth.month,
      bonus: adj?.bonus ?? 0.0,
      advanceDeduction: adj?.advanceDeduction ?? 0.0,
      isDisbursed: !currentlyDisbursed,
      disbursedAt: !currentlyDisbursed ? DateTime.now() : null,
      paymentMode: !currentlyDisbursed ? paymentMode : null,
      note: adj?.note,
    );

    await AttendanceService.saveAdjustment(newAdj);
    await _loadAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!currentlyDisbursed
              ? '✅ Salary marked as Disbursed ($paymentMode)'
              : 'Salary marked as Pending Payment'),
          backgroundColor: !currentlyDisbursed ? const Color(0xFF10B981) : Colors.blueGrey,
        ),
      );
    }
  }

  // Share salary slip via WhatsApp or clipboard
  Future<void> _shareSalarySlip(MonthlySalaryCalculation calc) async {
    final text = calc.formatWhatsAppSlip();
    final phone = calc.employee.phone.replaceAll(RegExp(r'\D'), '');

    final url = phone.isNotEmpty
        ? Uri.parse('https://api.whatsapp.com/send?phone=91$phone&text=${Uri.encodeComponent(text)}')
        : Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}');

    try {
      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched) {
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('📋 Salary Slip copied to clipboard!')),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📋 Salary Slip copied to clipboard!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final me = auth.currentUser;
    final bool isAdmin = me != null && (me.isSuperAdmin || me.isOffice);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Staff Attendance & Salary',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1),
              tooltip: 'Add Employee',
              onPressed: () => _openAddEmployeeDialog(),
            ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.celebration_outlined),
              tooltip: 'Auto-mark Sundays',
              onPressed: _autoMarkSundays,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF38BDF8),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            const Tab(icon: Icon(Icons.calendar_month, size: 20), text: 'Attendance'),
            const Tab(icon: Icon(Icons.account_balance_wallet, size: 20), text: 'Salary & Payroll'),
            if (isAdmin)
              const Tab(icon: Icon(Icons.groups, size: 20), text: 'Staff Roster')
            else
              const Tab(icon: Icon(Icons.person, size: 20), text: 'My Profile'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Top Self Check-In Card (Always visible) ───────────────
                _buildSelfCheckInCard(me),

                // ── Month Selector Header ─────────────────────────────────
                _buildMonthSelectorHeader(),

                // ── Tab Views ─────────────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Attendance Register & Calendar
                      _buildAttendanceTab(isAdmin),

                      // Tab 2: Salary & Payroll
                      _buildSalaryTab(isAdmin),

                      // Tab 3: Staff Roster or My Profile
                      if (isAdmin)
                        _buildStaffRosterTab()
                      else
                        _buildMyProfileTab(me),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ── Top Self Check-In Card ────────────────────────────────────────────────
  Widget _buildSelfCheckInCard(UserModel? me) {
    if (me == null) return const SizedBox.shrink();

    final timeStr = DateFormat('hh:mm:ss a').format(_now);
    final todayDateStr = DateFormat('EEE, dd MMM yyyy').format(_now);
    final checkedIn = _myTodayRecord?.checkInTime != null;
    final checkedOut = _myTodayRecord?.checkOutTime != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: checkedIn && !checkedOut
                          ? const Color(0xFF10B981)
                          : (checkedOut ? Colors.orange : Colors.grey),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${me.name} (${me.roleDisplayName})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$todayDateStr · $timeStr',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
            ],
          ),
          if (!checkedIn)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.login, size: 14),
              label: const Text('Check In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
              onPressed: _doCheckIn,
            )
          else if (!checkedOut)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.logout, size: 14),
              label: Text(
                'Check Out (${_myTodayRecord?.workDurationFormatted ?? ''})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
              ),
              onPressed: _doCheckOut,
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 13),
                  const SizedBox(width: 4),
                  Text(
                    'Done: ${_myTodayRecord?.workDurationFormatted ?? ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Month Selector Header ─────────────────────────────────────────────────
  Widget _buildMonthSelectorHeader() {
    final monthName = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            visualDensity: VisualDensity.compact,
            tooltip: 'Previous Month',
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
              });
              _loadAll();
            },
          ),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedMonth,
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                setState(() {
                  _selectedMonth = DateTime(picked.year, picked.month);
                });
                _loadAll();
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 15, color: Color(0xFF0F172A)),
                  const SizedBox(width: 6),
                  Text(
                    monthName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            visualDensity: VisualDensity.compact,
            tooltip: 'Next Month',
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
              });
              _loadAll();
            },
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: ATTENDANCE REGISTER & CALENDAR
  // =========================================================================
  Widget _buildAttendanceTab(bool isAdmin) {
    if (_employees.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No employees found in attendance roster.'),
            const SizedBox(height: 12),
            if (isAdmin)
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Employee'),
                onPressed: () => _openAddEmployeeDialog(),
              ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Employee Selector Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (isAdmin)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: _selectedEmployeeId == null,
                    label: const Text('All Staff Overview'),
                    avatar: const Icon(Icons.groups, size: 16),
                    selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                    onSelected: (_) => setState(() => _selectedEmployeeId = null),
                  ),
                ),
              ..._employees.map((emp) {
                final isSelected = _selectedEmployeeId == emp.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text('${emp.name} (${emp.role})'),
                    selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                    checkmarkColor: AppTheme.primary,
                    onSelected: (_) => setState(() => _selectedEmployeeId = emp.id),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // If specific employee selected -> Show their detailed calendar & summary
        if (_selectedEmployeeId != null) ...[
          _buildSingleEmployeeAttendanceSection(
            _employees.firstWhere((e) => e.id == _selectedEmployeeId,
                orElse: () => _employees.first),
            isAdmin,
          ),
        ] else ...[
          // All staff overview cards
          ..._employees.map((emp) => _buildEmployeeOverviewCard(emp, isAdmin)),
        ],
      ],
    );
  }

  Widget _buildSingleEmployeeAttendanceSection(
      AttendanceEmployee emp, bool isAdmin) {
    final adj = _adjustments.cast<SalaryMonthlyAdjustment?>().firstWhere(
          (a) => a?.employeeId == emp.id,
          orElse: () => null,
        );
    final calc = MonthlySalaryCalculation.compute(
      employee: emp,
      year: _selectedMonth.year,
      month: _selectedMonth.month,
      monthRecords: _records,
      adjustment: adj,
    );

    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_selectedMonth.year, _selectedMonth.month, 1).weekday; // 1=Mon, 7=Sun

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Summary Metrics Card ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        emp.name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        '${emp.role} · Base: ₹${emp.monthlySalary.toStringAsFixed(0)}/mo',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Text(
                      '${calc.payableDays.toStringAsFixed(1)} / $daysInMonth Days',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF15803D),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),
              // Counters Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatBadge('Present', '${calc.presentCount}', const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
                  _buildStatBadge('Half Day', '${calc.halfDayCount}', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
                  _buildStatBadge('Holidays', '${calc.holidayCount}', const Color(0xFF7C3AED), const Color(0xFFF3E8FF)),
                  _buildStatBadge('Leaves', '${calc.leaveCount}', const Color(0xFF0284C7), const Color(0xFFE0F2FE)),
                  _buildStatBadge('Absent', '${calc.absentCount}', const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Monthly Calendar Grid ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Monthly Attendance Calendar',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  if (isAdmin)
                    Text(
                      'Tap any past day to edit',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // Weekday Headers (Mon - Sun)
              Row(
                children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day) {
                  final isSun = day == 'S';
                  return Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isSun ? Colors.red.shade400 : Colors.blueGrey.shade700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),

              // Calendar Days Grid
              _buildCalendarDaysGrid(emp, daysInMonth, firstWeekday, isAdmin),

              const SizedBox(height: 12),
              // Legend
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _buildLegendItem('Present (P)', const Color(0xFF16A34A)),
                  _buildLegendItem('Half Day (½)', const Color(0xFFD97706)),
                  _buildLegendItem('Holiday (H)', const Color(0xFF7C3AED)),
                  _buildLegendItem('Leave (L)', const Color(0xFF0284C7)),
                  _buildLegendItem('Absent (A)', const Color(0xFFDC2626)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarDaysGrid(
      AttendanceEmployee emp, int daysInMonth, int firstWeekday, bool isAdmin) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final int emptySlots = firstWeekday - 1; // 1=Mon means 0 empty slots
    final totalCells = emptySlots + daysInMonth;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalCells,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.0,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemBuilder: (ctx, index) {
        if (index < emptySlots) {
          return const SizedBox.shrink();
        }

        final day = index - emptySlots + 1;
        final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
        final dateKey =
            '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        final isToday = isCurrentMonth && day == now.day;
        final isFuture = isCurrentMonth && day > now.day;
        final isSunday = date.weekday == DateTime.sunday;

        final record = _records.cast<AttendanceRecord?>().firstWhere(
              (r) => r?.userId == emp.id && r?.dateKey == dateKey,
              orElse: () => null,
            );

        Color bgColor;
        Color textColor;
        String label = '$day';
        String badge = '';

        if (isFuture) {
          bgColor = const Color(0xFFF8FAFC);
          textColor = Colors.blueGrey.shade300;
        } else if (record != null) {
          switch (record.status) {
            case AttendanceStatus.present:
              bgColor = const Color(0xFFDCFCE7);
              textColor = const Color(0xFF15803D);
              badge = 'P';
              break;
            case AttendanceStatus.halfDay:
              bgColor = const Color(0xFFFEF3C7);
              textColor = const Color(0xFFB45309);
              badge = '½';
              break;
            case AttendanceStatus.holiday:
              bgColor = const Color(0xFFF3E8FF);
              textColor = const Color(0xFF6D28D9);
              badge = 'H';
              break;
            case AttendanceStatus.leave:
              bgColor = const Color(0xFFE0F2FE);
              textColor = const Color(0xFF0369A1);
              badge = 'L';
              break;
            case AttendanceStatus.absent:
              bgColor = const Color(0xFFFEE2E2);
              textColor = const Color(0xFFB91C1C);
              badge = 'A';
              break;
          }
        } else if (isSunday) {
          bgColor = const Color(0xFFF1F5F9);
          textColor = Colors.blueGrey.shade500;
          badge = 'Off';
        } else {
          // Past working day unmarked
          bgColor = Colors.white;
          textColor = Colors.blueGrey.shade700;
          badge = '-';
        }

        return InkWell(
          onTap: (isAdmin && !isFuture) ? () => _openMarkStatusDialog(emp, date) : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isToday ? AppTheme.primary : Colors.grey.shade200,
                width: isToday ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isToday ? FontWeight.w900 : FontWeight.bold,
                    color: textColor,
                  ),
                ),
                if (badge.isNotEmpty)
                  Text(
                    badge,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmployeeOverviewCard(AttendanceEmployee emp, bool isAdmin) {
    final adj = _adjustments.cast<SalaryMonthlyAdjustment?>().firstWhere(
          (a) => a?.employeeId == emp.id,
          orElse: () => null,
        );
    final calc = MonthlySalaryCalculation.compute(
      employee: emp,
      year: _selectedMonth.year,
      month: _selectedMonth.month,
      monthRecords: _records,
      adjustment: adj,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        onTap: () => setState(() => _selectedEmployeeId = emp.id),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
          foregroundColor: AppTheme.primary,
          child: Text(emp.name.isNotEmpty ? emp.name[0].toUpperCase() : 'E'),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(emp.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${calc.payableDays.toStringAsFixed(1)} / ${calc.totalDaysInMonth}d',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Color(0xFF15803D)),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${emp.role} · Base ₹${emp.monthlySalary.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11.5)),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildMiniBadge('P: ${calc.presentCount}', const Color(0xFF15803D)),
                const SizedBox(width: 6),
                _buildMiniBadge('½: ${calc.halfDayCount}', const Color(0xFFB45309)),
                const SizedBox(width: 6),
                _buildMiniBadge('H: ${calc.holidayCount}', const Color(0xFF6D28D9)),
                const SizedBox(width: 6),
                _buildMiniBadge('A: ${calc.absentCount}', const Color(0xFFB91C1C)),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.blueGrey),
      ),
    );
  }

  // =========================================================================
  // TAB 2: SALARY & PAYROLL
  // =========================================================================
  Widget _buildSalaryTab(bool isAdmin) {
    if (_employees.isEmpty) {
      return const Center(child: Text('No employees found.'));
    }

    double totalPayroll = 0;
    int disbursedCount = 0;

    final calculations = _employees.map((emp) {
      final adj = _adjustments.cast<SalaryMonthlyAdjustment?>().firstWhere(
            (a) => a?.employeeId == emp.id,
            orElse: () => null,
          );
      final calc = MonthlySalaryCalculation.compute(
        employee: emp,
        year: _selectedMonth.year,
        month: _selectedMonth.month,
        monthRecords: _records,
        adjustment: adj,
      );
      totalPayroll += calc.netSalary;
      if (calc.isDisbursed) disbursedCount++;
      return calc;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Payroll Grand Summary Card ─────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Estimated Monthly Payroll',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      DateFormat('MMMM yyyy').format(_selectedMonth),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                CurrencyFormatter.format(totalPayroll),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Staff: ${_employees.length}  ·  Disbursed: $disbursedCount / ${_employees.length}',
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Employee Salary Cards ──────────────────────────────────────────
        ...calculations.map((calc) => _buildSalaryEmployeeCard(calc, isAdmin)),
      ],
    );
  }

  Widget _buildSalaryEmployeeCard(MonthlySalaryCalculation calc, bool isAdmin) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: calc.isDisbursed ? const Color(0xFF86EFAC) : AppTheme.border,
          width: calc.isDisbursed ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Name & Disbursed badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                      foregroundColor: AppTheme.primary,
                      child: Text(calc.employee.name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          calc.employee.name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        Text(
                          calc.employee.role,
                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: calc.isDisbursed ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    calc.isDisbursed ? 'DISBURSED' : 'PENDING',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: calc.isDisbursed ? const Color(0xFF15803D) : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 18),

            // Days Breakdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Days: ${calc.payableDays.toStringAsFixed(1)} / ${calc.totalDaysInMonth}d payable',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                Text(
                  '₹${calc.dailyRate.toStringAsFixed(1)}/day rate',
                  style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildMiniBadge('${calc.presentCount} Present', const Color(0xFF15803D)),
                if (calc.halfDayCount > 0)
                  _buildMiniBadge('${calc.halfDayCount} Half-day (${(calc.halfDayCount * 0.5).toStringAsFixed(1)}d)', const Color(0xFFB45309)),
                if (calc.holidayCount > 0)
                  _buildMiniBadge('${calc.holidayCount} Off/Holiday', const Color(0xFF6D28D9)),
                if (calc.absentCount > 0)
                  _buildMiniBadge('${calc.absentCount} Absent', const Color(0xFFB91C1C)),
              ],
            ),
            const SizedBox(height: 10),

            // Salary Calculation Formula
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _buildSalaryLine('Base Monthly Salary', '₹${calc.baseMonthlySalary.toStringAsFixed(0)}'),
                  _buildSalaryLine('Earned (${calc.payableDays.toStringAsFixed(1)} days)', '₹${calc.earnedSalary.toStringAsFixed(0)}', isBold: true),
                  if (calc.bonus > 0)
                    _buildSalaryLine('Bonus / Incentive', '+₹${calc.bonus.toStringAsFixed(0)}', color: const Color(0xFF15803D)),
                  if (calc.advanceDeduction > 0)
                    _buildSalaryLine('Advance Deduction', '-₹${calc.advanceDeduction.toStringAsFixed(0)}', color: const Color(0xFFDC2626)),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Net Salary to Pay:',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                      ),
                      Text(
                        CurrencyFormatter.format(calc.netSalary),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                // WhatsApp Slip
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF15803D),
                      side: const BorderSide(color: Color(0xFF86EFAC)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.share, size: 14),
                    label: const Text('WhatsApp Slip', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    onPressed: () => _shareSalarySlip(calc),
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  // Bonus / Advance
                  IconButton(
                    icon: const Icon(Icons.edit_note, size: 20),
                    tooltip: 'Adjust Bonus / Advance',
                    onPressed: () => _openSalaryAdjustmentDialog(calc.employee),
                  ),
                  const SizedBox(width: 4),
                  // Mark Disbursed Toggle
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: calc.isDisbursed ? Colors.blueGrey.shade700 : const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _toggleDisbursed(calc.employee, calc),
                    child: Text(
                      calc.isDisbursed ? 'Mark Pending' : 'Mark Paid',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 3: STAFF ROSTER (ADD / REMOVE)
  // =========================================================================
  Widget _buildStaffRosterTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attendance Roster',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                Text(
                  'Manage employees tracked in attendance & payroll',
                  style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                ),
              ],
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Staff', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: () => _openAddEmployeeDialog(),
            ),
          ],
        ),
        const SizedBox(height: 12),

        ..._employees.map((emp) {
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                    foregroundColor: AppTheme.primary,
                    child: Text(emp.name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(emp.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        Text('${emp.role} · ${emp.phone.isNotEmpty ? emp.phone : 'No phone'}', style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Salary: ₹${emp.monthlySalary.toStringAsFixed(0)} / month',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF15803D)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18, color: Colors.blueGrey),
                    tooltip: 'Edit Details & Salary',
                    onPressed: () => _openAddEmployeeDialog(toEdit: emp),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    tooltip: 'Remove Employee',
                    onPressed: () => _confirmRemoveEmployee(emp),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // Fallback Tab 3 for non-admins (e.g. Akash)
  Widget _buildMyProfileTab(UserModel? me) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(me?.name ?? 'User', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 4),
              Text('Role: ${me?.roleDisplayName ?? ''}', style: TextStyle(color: Colors.blueGrey.shade600)),
              Text('Phone: ${me?.phone ?? ''}', style: TextStyle(color: Colors.blueGrey.shade600)),
              const Divider(height: 24),
              const Text(
                'Attendance & Salary Access',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              const Text(
                'You have dedicated access to check in/out, view your monthly attendance calendar, and see your calculated salary.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _buildStatBadge(String label, String value, Color textCol, Color bgCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bgCol, borderRadius: BorderRadius.circular(6)),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textCol)),
          Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: textCol)),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(String text, Color col) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: col)),
    );
  }

  Widget _buildLegendItem(String label, Color col) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: col, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10.5, color: Colors.blueGrey.shade700, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildSalaryLine(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade700, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 11.5, color: color ?? const Color(0xFF0F172A), fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}
