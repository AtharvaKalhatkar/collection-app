import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/attendance_record.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../utils/theme.dart';

// Only SuperAdmin + Office + Akash can see/use this screen.
bool canViewAttendance(UserModel? user) {
  if (user == null) return false;
  return user.isSuperAdmin || user.isOffice || user.name.toLowerCase().trim() == 'akash';
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<AttendanceRecord> _records = [];
  bool _isLoading = false;
  String? _todayCheckInFormatted;
  String? _todayCheckOutFormatted;
  AttendanceRecord? _myTodayRecord;
  List<UserModel> _eligibleStaff = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final me = auth.currentUser;
    if (me == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Build the staff list to show attendance for:
    // - If SuperAdmin/Office: show all eligible (SuperAdmin + Office + Akash)
    // - If Akash: show only their own record
    final allUsers = auth.users.where((u) => canViewAttendance(u)).toList();
    _eligibleStaff = me.isSuperAdmin || me.isOffice ? allUsers : [me];

    final records = await AttendanceService.loadForMonth(
      _selectedMonth.year,
      _selectedMonth.month,
    );
    _records = records;

    // Load today's record for the current user (for self check-in/out button)
    final today = DateTime.now();
    _myTodayRecord = await AttendanceService.loadForUserAndDate(me.id, today);
    _todayCheckInFormatted = _myTodayRecord?.checkInTime != null
        ? DateFormat('hh:mm a').format(_myTodayRecord!.checkInTime!)
        : null;
    _todayCheckOutFormatted = _myTodayRecord?.checkOutTime != null
        ? DateFormat('hh:mm a').format(_myTodayRecord!.checkOutTime!)
        : null;

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _doCheckIn() async {
    final auth = context.read<AuthProvider>();
    final me = auth.currentUser!;
    final record = await AttendanceService.checkIn(me.id, me.name, me.roleDisplayName);
    if (mounted) {
      _myTodayRecord = record;
      _todayCheckInFormatted = DateFormat('hh:mm a').format(record.checkInTime!);
      await _loadAll();
      _showSnack('✅ Checked in at $_todayCheckInFormatted!', Colors.green.shade700);
    }
  }

  Future<void> _doCheckOut() async {
    final auth = context.read<AuthProvider>();
    final me = auth.currentUser!;
    final record = await AttendanceService.checkOut(me.id);
    if (record != null && mounted) {
      _myTodayRecord = record;
      _todayCheckOutFormatted = DateFormat('hh:mm a').format(record.checkOutTime!);
      await _loadAll();
      _showSnack('👋 Checked out at $_todayCheckOutFormatted!', Colors.orange.shade700);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Admin quick-mark for specific date/user
  Future<void> _adminMarkStatus(UserModel user, DateTime date) async {
    AttendanceStatus? chosen;
    final noteCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.edit_calendar_outlined, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Mark ${user.name} — ${DateFormat("dd MMM").format(date)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: StatefulBuilder(
          builder: (ctx2, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...AttendanceStatus.values.map((s) {
                Color col;
                IconData ic;
                switch (s) {
                  case AttendanceStatus.present:
                    col = Colors.green.shade700;
                    ic = Icons.check_circle_outline;
                    break;
                  case AttendanceStatus.absent:
                    col = Colors.red.shade600;
                    ic = Icons.cancel_outlined;
                    break;
                  case AttendanceStatus.halfDay:
                    col = Colors.orange.shade700;
                    ic = Icons.timelapse_outlined;
                    break;
                  case AttendanceStatus.leave:
                    col = Colors.blue.shade600;
                    ic = Icons.beach_access_outlined;
                    break;
                }
                return RadioListTile<AttendanceStatus>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Icon(ic, size: 18, color: col),
                      const SizedBox(width: 6),
                      Text(s.name == 'halfDay' ? 'Half Day' : s.name[0].toUpperCase() + s.name.substring(1),
                          style: TextStyle(fontWeight: FontWeight.w700, color: col)),
                    ],
                  ),
                  value: s,
                  groupValue: chosen,
                  onChanged: (v) => setLocal(() => chosen = v),
                );
              }),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: InputDecoration(
                  hintText: 'Note (optional)',
                  isDense: true,
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: chosen == null
                ? null
                : () async {
                    Navigator.pop(ctx);
                    await AttendanceService.markStatus(
                      userId: user.id,
                      staffName: user.name,
                      staffRole: user.roleDisplayName,
                      date: date,
                      status: chosen!,
                      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                    );
                    await _loadAll();
                    if (mounted) _showSnack('Updated ${user.name}\'s attendance', AppTheme.primary);
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final me = auth.currentUser;
    if (me == null || !canViewAttendance(me)) {
      return const Scaffold(
        body: Center(child: Text('Access not permitted')),
      );
    }

    final isAdmin = me.isSuperAdmin || me.isOffice;
    final today = DateTime.now();
    final alreadyCheckedIn = _myTodayRecord?.checkInTime != null;
    final alreadyCheckedOut = _myTodayRecord?.checkOutTime != null;

    // Days in selected month
    final daysInMonth = DateUtils.getDaysInMonth(_selectedMonth.year, _selectedMonth.month);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Attendance',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadAll,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // ----- Self Check-In / Check-Out Card -----
                _buildSelfCard(me, today, alreadyCheckedIn, alreadyCheckedOut),
                const SizedBox(height: 16),

                // ----- Month Selector -----
                _buildMonthSelector(),
                const SizedBox(height: 14),

                // ----- Staff Attendance Tables -----
                ..._eligibleStaff.map((staff) {
                  return _buildStaffMonthCard(staff, daysInMonth, isAdmin);
                }),
              ],
            ),
    );
  }

  Widget _buildSelfCard(UserModel me, DateTime today, bool checkedIn, bool checkedOut) {
    final todayStr = DateFormat('EEEE, dd MMMM yyyy').format(today);
    final workDur = _myTodayRecord?.workDurationFormatted ?? '--';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                radius: 20,
                child: Text(
                  me.name.isNotEmpty ? me.name[0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      me.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    Text(
                      todayStr,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: checkedIn
                      ? (checkedOut ? Colors.orange.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2))
                      : Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: checkedIn
                        ? (checkedOut ? Colors.orange : Colors.green)
                        : Colors.grey.shade400,
                  ),
                ),
                child: Text(
                  checkedOut ? 'Done' : (checkedIn ? 'Working' : 'Not In'),
                  style: TextStyle(
                    color: checkedIn ? (checkedOut ? Colors.orange : Colors.greenAccent) : Colors.grey.shade300,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Check-in / Check-out times
          Row(
            children: [
              _buildTimeChip(
                icon: Icons.login_rounded,
                label: 'Check In',
                time: _todayCheckInFormatted ?? '--:--',
                color: Colors.green,
              ),
              const SizedBox(width: 10),
              _buildTimeChip(
                icon: Icons.logout_rounded,
                label: 'Check Out',
                time: _todayCheckOutFormatted ?? '--:--',
                color: Colors.orange,
              ),
              const SizedBox(width: 10),
              _buildTimeChip(
                icon: Icons.timer_outlined,
                label: 'Duration',
                time: workDur,
                color: Colors.blue,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: checkedIn ? Colors.grey.shade700 : Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.login_rounded, size: 17),
                  label: Text(
                    checkedIn ? 'Checked In ✓' : 'Check In',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: checkedIn ? null : _doCheckIn,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !checkedIn || checkedOut ? Colors.grey.shade700 : Colors.orange.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  label: Text(
                    checkedOut ? 'Checked Out ✓' : 'Check Out',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: (!checkedIn || checkedOut) ? null : _doCheckOut,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeChip({
    required IconData icon,
    required String label,
    required String time,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 1),
            FittedBox(
              child: Text(
                time,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 22),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
              });
              _loadAll();
            },
          ),
          Text(
            DateFormat('MMMM yyyy').format(_selectedMonth),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0F172A)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 22),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              final next = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
              if (!next.isAfter(DateTime.now())) {
                setState(() => _selectedMonth = next);
                _loadAll();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStaffMonthCard(UserModel staff, int daysInMonth, bool isAdmin) {
    // Get records for this staff in the selected month
    final staffRecords = _records.where((r) => r.userId == staff.id).toList();
    final Map<String, AttendanceRecord> byDate = {for (final r in staffRecords) r.dateKey: r};

    // Count stats
    int present = 0, absent = 0, halfDay = 0, leave = 0;
    for (final r in staffRecords) {
      switch (r.status) {
        case AttendanceStatus.present:
          present++;
          break;
        case AttendanceStatus.absent:
          absent++;
          break;
        case AttendanceStatus.halfDay:
          halfDay++;
          break;
        case AttendanceStatus.leave:
          leave++;
          break;
      }
    }

    final today = DateTime.now();
    final isThisMonth = _selectedMonth.year == today.year && _selectedMonth.month == today.month;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: staff.isSuperAdmin
                      ? const Color(0xFF0F172A)
                      : (staff.isOffice ? const Color(0xFF0284C7) : const Color(0xFF10B981)),
                  radius: 16,
                  child: Text(
                    staff.name.isNotEmpty ? staff.name[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        staff.name,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        staff.roleDisplayName,
                        style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
                // Summary badges
                _statBadge('$present P', Colors.green.shade600),
                const SizedBox(width: 4),
                _statBadge('$absent A', Colors.red.shade600),
                if (halfDay > 0) ...[
                  const SizedBox(width: 4),
                  _statBadge('$halfDay H', Colors.orange.shade600),
                ],
                if (leave > 0) ...[
                  const SizedBox(width: 4),
                  _statBadge('$leave L', Colors.blue.shade600),
                ],
              ],
            ),
          ),

          // Calendar Grid
          Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: List.generate(daysInMonth, (i) {
                final day = i + 1;
                final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
                final dateKey = '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                final record = byDate[dateKey];
                final isWeekend = date.weekday == DateTime.sunday;
                final isFuture = isThisMonth && day > today.day;
                final isToday = isThisMonth && day == today.day;

                // Determine cell state
                Color bgColor;
                Color textColor;
                String? subLabel;

                if (isFuture) {
                  bgColor = const Color(0xFFF8FAFC);
                  textColor = Colors.blueGrey.shade300;
                } else if (record == null) {
                  if (isWeekend) {
                    bgColor = const Color(0xFFF1F5F9);
                    textColor = Colors.blueGrey.shade400;
                  } else {
                    // No record for a past working day — treat as absent
                    bgColor = Colors.red.shade50;
                    textColor = Colors.red.shade700;
                    subLabel = 'A';
                  }
                } else {
                  switch (record.status) {
                    case AttendanceStatus.present:
                      bgColor = Colors.green.shade50;
                      textColor = Colors.green.shade800;
                      subLabel = record.checkInTime != null ? DateFormat('h:mm').format(record.checkInTime!) : 'P';
                      break;
                    case AttendanceStatus.absent:
                      bgColor = Colors.red.shade50;
                      textColor = Colors.red.shade700;
                      subLabel = 'A';
                      break;
                    case AttendanceStatus.halfDay:
                      bgColor = Colors.orange.shade50;
                      textColor = Colors.orange.shade800;
                      subLabel = '½';
                      break;
                    case AttendanceStatus.leave:
                      bgColor = Colors.blue.shade50;
                      textColor = Colors.blue.shade700;
                      subLabel = 'L';
                      break;
                  }
                }

                return GestureDetector(
                  onTap: (isAdmin && !isFuture)
                      ? () => _adminMarkStatus(staff, date)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 42,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isToday
                            ? AppTheme.primary
                            : (record != null && record.status == AttendanceStatus.present
                                ? Colors.green.shade200
                                : Colors.transparent),
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
                            fontWeight: isToday ? FontWeight.w900 : FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                        if (subLabel != null)
                          Text(
                            subLabel,
                            style: TextStyle(fontSize: 8, color: textColor, fontWeight: FontWeight.bold),
                          ),
                        if (isWeekend && record == null)
                          Text('—', style: TextStyle(fontSize: 8, color: Colors.blueGrey.shade300)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),

          // Legend
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              children: [
                _legendDot(Colors.green.shade600, 'Present'),
                const SizedBox(width: 10),
                _legendDot(Colors.red.shade600, 'Absent'),
                const SizedBox(width: 10),
                _legendDot(Colors.orange.shade600, 'Half Day'),
                const SizedBox(width: 10),
                _legendDot(Colors.blue.shade600, 'Leave'),
                const Spacer(),
                if (isAdmin)
                  Text(
                    'Tap a day to edit',
                    style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 9.5, color: Colors.blueGrey.shade600)),
      ],
    );
  }
}
