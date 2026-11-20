import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/attendance_record.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';

/// Access restriction: SuperAdmin, Office staff, and Akash (salesman)
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
  String? _selectedEmployeeId; // null = "All Staff Overview" (admin only)
  bool _isLoading = false;

  Timer? _ticker;
  Timer? _syncTimer;
  final ValueNotifier<DateTime> _clock = ValueNotifier(DateTime.now());
  AttendanceRecord? _myTodayRecord;
  AttendanceEmployee? _myEmployee; // roster entry linked to logged-in user
  bool _busy = false;
  int _loadSeq = 0;
  int _pending = 0;
  bool _openedFromRoster = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Only the clock widget rebuilds each second (not the whole screen)
    _ticker = Timer.periodic(
        const Duration(seconds: 1), (_) => _clock.value = DateTime.now());
    // Cross-device auto-sync (fallback every 3 minutes; immediate sync occurs on user actions & refresh)
    _syncTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (mounted) _loadAll(silent: true);
    });
    _loadAll();
  }

  void _onTabChanged() {
    if (mounted) {
      if (_tabController.index == 1) {
        _openedFromRoster = false;
      }
      setState(() {});
    }
  }

  bool get _canPopDirectly {
    final me = context.read<AuthProvider>().currentUser;
    final bool isAdmin = me != null && (me.isSuperAdmin || me.isOffice);
    if (_tabController.index != 0) return false;
    if (isAdmin && _selectedEmployeeId != null) return false;
    return true;
  }

  void _handleBack() {
    final me = context.read<AuthProvider>().currentUser;
    final bool isAdmin = me != null && (me.isSuperAdmin || me.isOffice);

    if (_tabController.index == 0 && isAdmin && _selectedEmployeeId != null) {
      if (_openedFromRoster) {
        setState(() {
          _selectedEmployeeId = null;
          _openedFromRoster = false;
        });
        _tabController.animateTo(1);
      } else {
        setState(() {
          _selectedEmployeeId = null;
        });
      }
      return;
    }

    if (_tabController.index != 0) {
      _tabController.animateTo(0);
      return;
    }

    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _ticker?.cancel();
    _syncTimer?.cancel();
    _clock.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _toast(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  AttendanceEmployee? _matchMyEmployee(
      List<AttendanceEmployee> emps, UserModel? me) {
    if (me == null) return null;
    final name = me.name.toLowerCase().trim();
    final phone = me.phone.trim();
    for (final e in emps) {
      if (e.id == me.id) return e;
      if (phone.isNotEmpty && e.phone.trim() == phone) return e;
      if (name.isNotEmpty && e.name.toLowerCase().trim() == name) return e;
    }
    if (name.contains('akash')) {
      for (final e in emps) {
        if (e.name.toLowerCase().contains('akash')) return e;
      }
    }
    return null;
  }

  Future<void> _loadAll({bool silent = false, bool sync = true}) async {
    final seq = ++_loadSeq; // newer load wins; stale results are dropped
    if (!silent) setState(() => _isLoading = true);
    final me = context.read<AuthProvider>().currentUser;
    final isAdmin = me != null && (me.isSuperAdmin || me.isOffice);
    final y = _selectedMonth.year, m = _selectedMonth.month;

    try {
      final emps =
          await AttendanceService.loadEmployees(activeOnly: true, sync: sync);
      final records = await AttendanceService.loadForMonth(y, m, sync: sync);
      final adjs = await AttendanceService.loadAdjustments(y, m, sync: sync);
      final mine =
          (me == null || me.isSuperAdmin) ? null : _matchMyEmployee(emps, me);
      final today = mine == null
          ? null
          : await AttendanceService.loadForUserAndDate(mine.id, DateTime.now());
      final pending = await AttendanceService.pendingSyncCount();

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        // Non-admins only ever see their own row (never the whole roster)
        _employees = isAdmin ? emps : (mine == null ? [] : [mine]);
        _records = records;
        _adjustments = adjs;
        _myEmployee = mine;
        _myTodayRecord = today;
        _pending = pending;

        if (_selectedEmployeeId != null &&
            !_employees.any((e) => e.id == _selectedEmployeeId)) {
          _selectedEmployeeId = null;
        }
        if (!isAdmin && _selectedEmployeeId == null && _employees.isNotEmpty) {
          _selectedEmployeeId = _employees.first.id;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Attendance load error: $e');
      if (mounted && seq == _loadSeq) setState(() => _isLoading = false);
    }
  }

  // Self check-in (staff, NOT Super Admin)
  Future<void> _doCheckIn() async {
    final emp = _myEmployee;
    if (emp == null || _busy) return;
    setState(() => _busy = true);
    try {
      await AttendanceService.checkIn(emp.id, emp.name, emp.role);
      await _loadAll(silent: true, sync: false);
      _toast('✅ Checked in successfully! Have a productive day.',
          color: const Color(0xFF10B981));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doCheckOut() async {
    final emp = _myEmployee;
    if (emp == null || _busy) return;
    setState(() => _busy = true);
    try {
      final r = await AttendanceService.checkOut(emp.id);
      await _loadAll(silent: true, sync: false);
      if (r == null) {
        _toast('No check-in found for today.');
      } else if (r.status == AttendanceStatus.halfDay) {
        _toast('👋 Checked out. Marked Half Day (worked under 4 hrs).',
            color: Colors.orange);
      } else {
        _toast('👋 Checked out successfully. Good work!',
            color: const Color(0xFF0F172A));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MARK ATTENDANCE DIALOG
  // ───────────────────────────────────────────────────────────────────────────
  void _openMarkAttendanceDialog({AttendanceEmployee? targetEmp, DateTime? targetDate}) {
    final me = context.read<AuthProvider>().currentUser;
    final bool isAdmin = me != null && (me.isSuperAdmin || me.isOffice);
    if (!isAdmin) return;
    if (_employees.isEmpty) {
      _toast('Please add an employee first in Staff Roster.');
      return;
    }

    AttendanceEmployee currentEmp = targetEmp ??
        (_selectedEmployeeId != null
            ? _employees.firstWhere((e) => e.id == _selectedEmployeeId,
                orElse: () => _employees.first)
            : _employees.first);

    DateTime chosenDate = targetDate ?? DateTime.now();

    AttendanceRecord? findRecord(String empId, DateTime date) {
      final dKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      for (final r in _records) {
        if (r.userId == empId && r.dateKey == dKey) return r;
      }
      return null;
    }

    final existing = findRecord(currentEmp.id, chosenDate);
    AttendanceStatus chosenStatus = existing?.status ?? AttendanceStatus.present;

    TimeOfDay checkInTime = existing?.checkInTime != null
        ? TimeOfDay.fromDateTime(existing!.checkInTime!)
        : TimeOfDay.fromDateTime(DateTime.now());

    TimeOfDay? checkOutTime = existing?.checkOutTime != null
        ? TimeOfDay.fromDateTime(existing!.checkOutTime!)
        : null;

    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) {
          final isCheckOutSet = checkOutTime != null;

          void syncFieldsFor(String empId, DateTime date) {
            final rec = findRecord(empId, date);
            chosenStatus = rec?.status ?? AttendanceStatus.present;
            checkInTime = rec?.checkInTime != null
                ? TimeOfDay.fromDateTime(rec!.checkInTime!)
                : TimeOfDay.fromDateTime(DateTime.now());
            checkOutTime = rec?.checkOutTime != null
                ? TimeOfDay.fromDateTime(rec!.checkOutTime!)
                : null;
            noteCtrl.text = rec?.note ?? '';
          }

          Widget statusTile(AttendanceStatus s, String label, IconData icon,
              Color bg, Color border, Color fg) {
            final sel = chosenStatus == s;
            return Expanded(
              child: InkWell(
                onTap: () => setLocal(() => chosenStatus = s),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? bg : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? border : Colors.grey.shade300,
                      width: sel ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(icon, color: sel ? fg : Colors.grey, size: 20),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: sel ? fg : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Mark Attendance',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Employee Selector
                  const Text('Select Employee',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: currentEmp.id,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: _employees.map((e) {
                      return DropdownMenuItem(
                        value: e.id,
                        child: Text(e.plainName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setLocal(() {
                          currentEmp = _employees.firstWhere((e) => e.id == val);
                          syncFieldsFor(currentEmp.id, chosenDate);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // 2. Date Selector (no future dates)
                  const Text('Date',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: chosenDate.isAfter(DateTime.now()) ? DateTime.now() : chosenDate,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setLocal(() {
                          chosenDate = picked;
                          syncFieldsFor(currentEmp.id, chosenDate);
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.grey.shade50,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16, color: Color(0xFF0F172A)),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('EEE, dd MMMM yyyy').format(chosenDate),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                            ],
                          ),
                          const Icon(Icons.edit_calendar, size: 16, color: Colors.blueGrey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Status: Present, Half Day, Absent
                  const Text('Attendance Status',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      statusTile(AttendanceStatus.present, 'Present', Icons.check_circle,
                          const Color(0xFFDCFCE7), const Color(0xFF16A34A), const Color(0xFF15803D)),
                      const SizedBox(width: 8),
                      statusTile(AttendanceStatus.halfDay, 'Half Day', Icons.timelapse,
                          const Color(0xFFFEF3C7), const Color(0xFFD97706), const Color(0xFFB45309)),
                      const SizedBox(width: 8),
                      statusTile(AttendanceStatus.absent, 'Absent', Icons.cancel,
                          const Color(0xFFFEE2E2), const Color(0xFFDC2626), const Color(0xFFB91C1C)),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 4. Check-in & Check-out times (Present & Half Day)
                  if (chosenStatus != AttendanceStatus.absent) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Check-In Time',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                  InkWell(
                                    onTap: () => setLocal(() => checkInTime = TimeOfDay.fromDateTime(DateTime.now())),
                                    child: const Text('Now', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: checkInTime,
                                  );
                                  if (picked != null) setLocal(() => checkInTime = picked);
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade400),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        checkInTime.format(context),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const Icon(Icons.access_time, size: 16, color: Color(0xFF10B981)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Leaving Time',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                  Row(
                                    children: [
                                      InkWell(
                                        onTap: () => setLocal(() => checkOutTime = TimeOfDay.fromDateTime(DateTime.now())),
                                        child: const Text('Now', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
                                      ),
                                      if (isCheckOutSet) ...[
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () => setLocal(() => checkOutTime = null),
                                          child: const Text('Clear', style: TextStyle(fontSize: 11, color: Colors.red)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: checkOutTime ?? TimeOfDay.fromDateTime(DateTime.now()),
                                  );
                                  if (picked != null) setLocal(() => checkOutTime = picked);
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isCheckOutSet ? Colors.grey.shade400 : Colors.blue.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    color: isCheckOutSet ? Colors.transparent : Colors.blue.shade50,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        isCheckOutSet ? checkOutTime!.format(context) : 'Set Checkout',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isCheckOutSet ? Colors.black87 : Colors.blue.shade700,
                                        ),
                                      ),
                                      Icon(Icons.logout,
                                          size: 16,
                                          color: isCheckOutSet ? Colors.orange : Colors.blue),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 5. Optional Note
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Note (Optional)',
                      hintText: 'e.g. Field visit, Half-day personal work',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (chosenStatus != AttendanceStatus.absent &&
                      checkOutTime != null &&
                      checkOutTime!.hour * 60 + checkOutTime!.minute <=
                          checkInTime.hour * 60 + checkInTime.minute) {
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Leaving time must be after check-in time.')));
                    return;
                  }
                  Navigator.pop(ctx);

                  DateTime? inDateTime;
                  DateTime? outDateTime;

                  if (chosenStatus != AttendanceStatus.absent) {
                    inDateTime = DateTime(
                      chosenDate.year,
                      chosenDate.month,
                      chosenDate.day,
                      checkInTime.hour,
                      checkInTime.minute,
                    );
                    if (checkOutTime != null) {
                      outDateTime = DateTime(
                        chosenDate.year,
                        chosenDate.month,
                        chosenDate.day,
                        checkOutTime!.hour,
                        checkOutTime!.minute,
                      );
                    }
                  }

                  await AttendanceService.markStatus(
                    userId: currentEmp.id,
                    staffName: currentEmp.name,
                    staffRole: currentEmp.role,
                    date: chosenDate,
                    status: chosenStatus,
                    checkInTime: inDateTime,
                    checkOutTime: outDateTime,
                    note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                  );
                  await _loadAll(silent: true, sync: false);
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Saved: ${currentEmp.name} marked ${chosenStatus.label}'),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  }
                },
                child: const Text('Save Entry', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // ADD / EDIT EMPLOYEE
  // ───────────────────────────────────────────────────────────────────────────
  void _openAddEmployeeDialog({AttendanceEmployee? toEdit}) {
    final isEditing = toEdit != null;
    final nameCtrl = TextEditingController(text: toEdit?.name ?? '');
    final phoneCtrl = TextEditingController(text: toEdit?.phone ?? '');
    final salaryCtrl = TextEditingController(
      text: toEdit != null ? toEdit.monthlySalary.toStringAsFixed(0) : '',
    );

    final allowedRoles = AttendanceEmployee.allowedRoles;
    String selectedRole = toEdit != null && allowedRoles.contains(toEdit.role)
        ? toEdit.role
        : 'Sales & Collection';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isEditing ? 'Edit Employee' : 'Add Employee',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Full Name *',
                    hintText: 'Employee Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Select Role *',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
                const SizedBox(height: 6),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 2.2,
                  children: allowedRoles.map((role) {
                    final isSelected = selectedRole == role;
                    IconData icon;
                    switch (role) {
                      case 'Driver':
                        icon = Icons.local_shipping;
                        break;
                      case 'Sales & Collection':
                        icon = Icons.two_wheeler;
                        break;
                      case 'Helper':
                        icon = Icons.handshake_outlined;
                        break;
                      case 'Office Staff':
                      default:
                        icon = Icons.business_center_outlined;
                    }

                    return InkWell(
                      onTap: () => setLocal(() => selectedRole = role),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primary.withValues(alpha: 0.12) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? AppTheme.primary : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(icon, size: 18, color: isSelected ? AppTheme.primary : Colors.blueGrey),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                role,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                  color: isSelected ? AppTheme.primary : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    hintText: 'e.g. 9876543210 (WhatsApp Slip)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: salaryCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Monthly Base Salary (₹)',
                    hintText: 'e.g. 18000',
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
                final salary = double.tryParse(salaryCtrl.text.trim()) ?? 0.0;
                if (name.isEmpty) {
                  _toast('Please enter the employee name.');
                  return;
                }

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

                await AttendanceService.saveEmployee(emp);
                await _loadAll(silent: true, sync: false);
                _toast(
                  isEditing ? 'Updated ${emp.name}\'s profile' : 'Added ${emp.name} to roster',
                  color: const Color(0xFF10B981),
                );
              },
              child: Text(isEditing ? 'Save Changes' : 'Add Employee'),
            ),
          ],
        ),
      ),
    );
  }

  // Remove employee (soft delete: history is preserved, never reappears)
  Future<void> _confirmRemoveEmployee(AttendanceEmployee emp) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${emp.name}?'),
        content: Text(
          'Are you sure you want to remove ${emp.name} from the employee roster? Past logs are preserved.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AttendanceService.deleteEmployee(emp.id);
      await _loadAll(silent: true, sync: false);
      _toast('Removed ${emp.name} from roster', color: const Color(0xFFDC2626));
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // ADVANCE SALARY DIALOG
  // ───────────────────────────────────────────────────────────────────────────
  void _openAdvanceSalaryDialog({AttendanceEmployee? targetEmp}) {
    final me = context.read<AuthProvider>().currentUser;
    if (me == null || !(me.isSuperAdmin || me.isOffice)) return;
    if (_employees.isEmpty) {
      _toast('Please add an employee first in Staff Roster.');
      return;
    }

    AttendanceEmployee currentEmp = targetEmp ??
        (_selectedEmployeeId != null
            ? _employees.firstWhere((e) => e.id == _selectedEmployeeId,
                orElse: () => _employees.first)
            : _employees.first);

    final advCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    // Advance is stored under the selected month, so its date must fall in it
    final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final nowD = DateTime.now();
    DateTime advanceDate =
        nowD.isBefore(monthStart) ? monthStart : (nowD.isAfter(monthEnd) ? monthEnd : nowD);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) {
          SalaryMonthlyAdjustment? curAdj;
          for (final a in _adjustments) {
            if (a.employeeId == currentEmp.id) curAdj = a;
          }
          final totalAdv = curAdj?.totalAdvanceDeduction ?? 0.0;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.price_change_outlined, color: Color(0xFFDC2626), size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text('Advance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Month: ${DateFormat("MMMM yyyy").format(_selectedMonth)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700),
                  ),
                  const SizedBox(height: 12),

                  const Text('Select Employee *',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: currentEmp.id,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: _employees.map((e) {
                      return DropdownMenuItem(
                        value: e.id,
                        child: Text(e.plainName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setLocal(() {
                          currentEmp = _employees.firstWhere((e) => e.id == val);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.grey.shade50,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: Color(0xFFDC2626)),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('d MMM yyyy').format(advanceDate),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: advanceDate,
                              firstDate: monthStart,
                              lastDate: monthEnd,
                            );
                            if (picked != null) setLocal(() => advanceDate = picked);
                          },
                          child: const Text('Change', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF2563EB))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (totalAdv > 0)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: Color(0xFFDC2626)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Total Advances This Month: ₹${totalAdv.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFB91C1C)),
                            ),
                          ),
                        ],
                      ),
                    ),

                  TextField(
                    controller: advCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'Advance Amount (₹) *',
                      hintText: 'e.g. 2000, 5000',
                      prefixIcon: const Icon(Icons.currency_rupee, color: Color(0xFFDC2626)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Reason / Note (Optional)',
                      hintText: 'e.g. Festival advance, Emergency, Medical',
                      prefixIcon: const Icon(Icons.note_alt_outlined, color: Colors.blueGrey),
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
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final adv = double.tryParse(advCtrl.text.trim()) ?? 0.0;
                  if (adv <= 0) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Please enter a valid advance amount.')),
                    );
                    return;
                  }

                  Navigator.pop(ctx);
                  await AttendanceService.addAdvance(
                    employeeId: currentEmp.id,
                    year: _selectedMonth.year,
                    month: _selectedMonth.month,
                    amount: adv,
                    date: advanceDate,
                    note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                  );
                  await _loadAll(silent: true, sync: false);
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Saved advance of ₹${adv.toStringAsFixed(0)} for ${currentEmp.name}'),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  }
                },
                child: const Text('Save Advance', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteAdvance(AttendanceEmployee emp, SalaryAdvanceEntry adv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Advance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'Delete advance of ₹${adv.amount.toStringAsFixed(0)} given on ${DateFormat("d MMM yyyy").format(adv.date)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await AttendanceService.deleteAdvance(
                employeeId: emp.id,
                advanceId: adv.id,
                year: _selectedMonth.year,
                month: _selectedMonth.month,
              );
              await _loadAll(silent: true, sync: false);
              _toast('Advance removed');
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
    final me = auth.currentUser;
    final bool isAdmin = me != null && (me.isSuperAdmin || me.isOffice);

    return PopScope(
      canPop: _canPopDirectly,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
          title: const Text(
            'Daily Attendance',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            if (isAdmin) ...[
              IconButton(
                icon: const Icon(Icons.price_change_outlined),
                tooltip: 'Give Advance',
                onPressed: () => _openAdvanceSalaryDialog(),
              ),
              IconButton(
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: 'Add Employee',
                onPressed: () => _openAddEmployeeDialog(),
              ),
            ],
            if (_pending > 0)
              Tooltip(
                message: '$_pending change(s) waiting to sync',
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.cloud_off, size: 20, color: Colors.amber),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => _loadAll(),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF38BDF8),
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            tabs: [
              const Tab(icon: Icon(Icons.calendar_month, size: 20), text: 'Attendance'),
              if (isAdmin)
                const Tab(icon: Icon(Icons.groups, size: 20), text: 'Staff Roster')
              else
                const Tab(icon: Icon(Icons.person, size: 20), text: 'My Attendance'),
            ],
          ),
        ),
        floatingActionButton: (isAdmin && _employees.isNotEmpty)
            ? FloatingActionButton.extended(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Mark Attendance', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => _openMarkAttendanceDialog(),
              )
            : null,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildSelfCheckInCard(me),
                  _buildMonthSelectorHeader(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAttendanceTab(isAdmin),
                        if (isAdmin) _buildStaffRosterTab() else _buildMyProfileTab(me),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Self Check-In Card (hidden for Super Admin) ─────────────────────────────
  Widget _buildSelfCheckInCard(UserModel? me) {
    if (me == null || me.isSuperAdmin) return const SizedBox.shrink();

    if (_myEmployee == null) {
      return Container(
        width: double.infinity,
        color: const Color(0xFF7C2D12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: const Text(
          'You are not linked to the staff roster. Ask the admin to add you '
          '(same name or mobile number) to enable check-in.',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      );
    }

    final rec = _myTodayRecord;
    final checkedIn = rec?.checkInTime != null;
    final checkedOut = rec?.checkOutTime != null;

    ButtonStyle style(Color c) => ElevatedButton.styleFrom(
          backgroundColor: c,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
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
                  Flexible(
                    child: Text(
                      me.plainName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                  ),
                ]),
                const SizedBox(height: 2),
                ValueListenableBuilder<DateTime>(
                  valueListenable: _clock,
                  builder: (context, now, child) {
                    var txt =
                        '${DateFormat('EEE, dd MMM yyyy').format(now)} · ${DateFormat('hh:mm:ss a').format(now)}';
                    if (checkedIn && !checkedOut) {
                      final d = now.difference(rec!.checkInTime!);
                      if (!d.isNegative) txt += ' · ${d.inHours}h ${d.inMinutes % 60}m on duty';
                    }
                    return Text(txt,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!checkedIn)
            ElevatedButton.icon(
              style: style(const Color(0xFF10B981)),
              icon: const Icon(Icons.login, size: 14),
              label: const Text('Check In',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
              onPressed: _busy ? null : _doCheckIn,
            )
          else if (!checkedOut)
            ElevatedButton.icon(
              style: style(const Color(0xFFEF4444)),
              icon: const Icon(Icons.logout, size: 14),
              label: const Text('Check Out',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
              onPressed: _busy ? null : _doCheckOut,
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 13),
                const SizedBox(width: 4),
                Text('Done: ${rec?.workDurationFormatted ?? ''}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
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
                setState(() => _selectedMonth = DateTime(picked.year, picked.month));
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
  // TAB 1: ATTENDANCE & MONTHLY SALARY
  // =========================================================================
  Widget _buildAttendanceTab(bool isAdmin) {
    if (_employees.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.group_off_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                isAdmin ? 'No employees in roster yet.' : 'You are not linked to the staff roster.',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                isAdmin
                    ? 'Add employees to track daily attendance and calculate monthly salary.'
                    : 'Ask the admin to add you with the same name or mobile number.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              const SizedBox(height: 16),
              if (isAdmin)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add Employee'),
                  onPressed: () => _openAddEmployeeDialog(),
                ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      children: [
        // Employee selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedEmployeeId,
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
              items: [
                if (isAdmin)
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Row(
                      children: [
                        Icon(Icons.groups, size: 18, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text('All Staff Overview',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      ],
                    ),
                  ),
                ..._employees.map((emp) => DropdownMenuItem<String?>(
                      value: emp.id,
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline, size: 18, color: Colors.blueGrey),
                          const SizedBox(width: 8),
                          Text(emp.plainName,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        ],
                      ),
                    )),
              ],
              onChanged: (val) => setState(() {
                _selectedEmployeeId = val;
                _openedFromRoster = false;
              }),
            ),
          ),
        ),
        const SizedBox(height: 14),

        if (_selectedEmployeeId != null)
          _buildSingleEmployeeSection(
            _employees.firstWhere((e) => e.id == _selectedEmployeeId,
                orElse: () => _employees.first),
            isAdmin,
          )
        else
          ..._employees.map((emp) => _buildEmployeeOverviewCard(emp, isAdmin)),
      ],
    );
  }

  SalaryMonthlyAdjustment? _adjFor(String empId) {
    for (final a in _adjustments) {
      if (a.employeeId == empId) return a;
    }
    return null;
  }

  Widget _buildSingleEmployeeSection(AttendanceEmployee emp, bool isAdmin) {
    final adj = _adjFor(emp.id);
    final calc = MonthlySalaryCalculation.compute(
      employee: emp,
      year: _selectedMonth.year,
      month: _selectedMonth.month,
      monthRecords: _records,
      adjustment: adj,
    );

    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_selectedMonth.year, _selectedMonth.month, 1).weekday; // 1=Mon

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. Summary Metrics Card ─────────────────────────────────────────
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
                        emp.plainName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        'Base ₹${emp.monthlySalary.toStringAsFixed(0)}/month',
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Total Salary: ${CurrencyFormatter.format(calc.netSalary)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF15803D),
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${calc.payableDays.toStringAsFixed(1)} / $daysInMonth Days',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatBadge('Present', '${calc.presentCount}', const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
                  _buildStatBadge('Half Day', '${calc.halfDayCount}', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
                  _buildStatBadge('Absent', '${calc.absentCount}', const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
                  _buildStatBadge('Payable Days', calc.payableDays.toStringAsFixed(1), const Color(0xFF1E293B), const Color(0xFFF1F5F9)),
                ],
              ),
              if (calc.unmarkedDays > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '⚠️ ${calc.unmarkedDays} day(s) not marked yet. Unmarked days are unpaid.',
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                ),
              ],
              if (isAdmin) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.payments_outlined,
                            size: 16,
                            color: calc.advanceDeduction > 0 ? const Color(0xFFDC2626) : Colors.blueGrey),
                        const SizedBox(width: 6),
                        Text(
                          calc.advanceDeduction > 0
                              ? 'Total Advance: ₹${calc.advanceDeduction.toStringAsFixed(0)}'
                              : 'No Advance Given',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: calc.advanceDeduction > 0 ? const Color(0xFFDC2626) : Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () => _openAdvanceSalaryDialog(targetEmp: emp),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: const Text(
                          '+ Advance',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (adj != null && adj.advances.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...adj.advances.map((adv) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today, size: 13, color: Color(0xFFDC2626)),
                                  const SizedBox(width: 6),
                                  Text(
                                    DateFormat('d MMM yyyy').format(adv.date),
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                                  ),
                                  if (adv.note != null && adv.note!.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text('(${adv.note})',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '₹${adv.amount.toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFFDC2626)),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => _confirmDeleteAdvance(emp, adv),
                                  child: const Padding(
                                    padding: EdgeInsets.all(2.0),
                                    child: Icon(Icons.close, size: 15, color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ],
          ),
        ),

        // ── 2. Absent dates ─────────────────────────────────────────────────
        if (calc.absentDates.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.event_busy, color: Color(0xFFDC2626), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
                      children: [
                        const TextSpan(
                          text: 'Absent on: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text: calc.absentDates
                              .map((d) => DateFormat('d MMM').format(d))
                              .join(', '),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: ' (Total ${calc.absentCount} day${calc.absentCount > 1 ? 's' : ''})',
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),

        // ── 3. Calendar ─────────────────────────────────────────────────────
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
                    'Daily Attendance Calendar',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  if (isAdmin)
                    Text(
                      'Tap any date to mark/edit',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              _buildCalendarDaysGrid(emp, daysInMonth, firstWeekday, isAdmin),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _buildLegendItem('Present (P)', const Color(0xFF16A34A)),
                  _buildLegendItem('Half Day (½)', const Color(0xFFD97706)),
                  _buildLegendItem('Absent (A)', const Color(0xFFDC2626)),
                  _buildLegendItem('Unmarked (-)', Colors.grey.shade400),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildCalendarDaysGrid(
      AttendanceEmployee emp, int daysInMonth, int firstWeekday, bool isAdmin) {
    final now = DateTime.now();
    final todayD = DateTime(now.year, now.month, now.day);
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final int emptySlots = firstWeekday - 1; // 1=Mon
    final totalCells = emptySlots + daysInMonth;
    final byKey = {
      for (final r in _records)
        if (r.userId == emp.id) r.dateKey: r
    };

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
        if (index < emptySlots) return const SizedBox.shrink();

        final day = index - emptySlots + 1;
        final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
        final dateKey =
            '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        final isToday = isCurrentMonth && day == now.day;
        final isFuture = date.isAfter(todayD); // also correct for future months
        final record = byKey[dateKey];

        Color bgColor;
        Color textColor;
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
            case AttendanceStatus.absent:
              bgColor = const Color(0xFFFEE2E2);
              textColor = const Color(0xFFB91C1C);
              badge = 'A';
              break;
          }
        } else {
          bgColor = Colors.white;
          textColor = Colors.blueGrey.shade700;
          badge = '-';
        }

        return InkWell(
          onTap: (isAdmin && !isFuture)
              ? () => _openMarkAttendanceDialog(targetEmp: emp, targetDate: date)
              : null,
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
                  '$day',
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
                      fontSize: 9.5,
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
    final calc = MonthlySalaryCalculation.compute(
      employee: emp,
      year: _selectedMonth.year,
      month: _selectedMonth.month,
      monthRecords: _records,
      adjustment: _adjFor(emp.id),
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
        onTap: () => setState(() {
          _selectedEmployeeId = emp.id;
          _openedFromRoster = false;
        }),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
          foregroundColor: AppTheme.primary,
          child: Text(emp.name.isNotEmpty ? emp.name[0].toUpperCase() : 'E'),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(emp.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
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
            Text('Base ₹${emp.monthlySalary.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600)),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildMiniBadge('P: ${calc.presentCount}', const Color(0xFF15803D)),
                const SizedBox(width: 6),
                _buildMiniBadge('½: ${calc.halfDayCount}', const Color(0xFFB45309)),
                const SizedBox(width: 6),
                _buildMiniBadge('A: ${calc.absentCount}', const Color(0xFFB91C1C)),
                const Spacer(),
                Text(
                  'Net: ${CurrencyFormatter.format(calc.netSalary)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFF0F172A)),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.blueGrey),
      ),
    );
  }

  // =========================================================================
  // TAB 2: STAFF ROSTER
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
                  'Staff Roster',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                Text(
                  'Manage employees tracked in daily attendance',
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
        if (_employees.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: const Text('No staff added yet. Tap "+ Add Staff" to add employees.'),
          )
        else
          ..._employees.map((emp) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _selectedEmployeeId = emp.id;
                    _openedFromRoster = true;
                  });
                  _tabController.animateTo(0);
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                        foregroundColor: AppTheme.primary,
                        child: Text(emp.name.isNotEmpty ? emp.name[0].toUpperCase() : 'E',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(emp.plainName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            Text(
                              '${emp.role} · ${emp.phone.isNotEmpty ? emp.phone : 'No phone'}',
                              style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.price_change_outlined, size: 20, color: Color(0xFFDC2626)),
                        tooltip: 'Give Advance',
                        onPressed: () => _openAdvanceSalaryDialog(targetEmp: emp),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18, color: Colors.blueGrey),
                        tooltip: 'Edit Details',
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
              ),
            );
          }),
      ],
    );
  }

  // Tab 2 for non-admins (e.g. Akash)
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
                'Daily Attendance Access',
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bgCol, borderRadius: BorderRadius.circular(8)),
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

}