import 'package:flutter_test/flutter_test.dart';
import 'package:daily_collection_app/models/attendance_record.dart';

void main() {
  group('Daily Attendance & Salary Tests', () {
    test('Allowed roles strictly match user requirements', () {
      expect(AttendanceEmployee.allowedRoles, [
        'Sales & Collection',
        'Driver',
        'Helper',
        'Office Staff',
      ]);
    });

    test('AttendanceStatus enum has only 3 values: present, halfDay, absent', () {
      expect(AttendanceStatus.values.length, 3);
      expect(AttendanceStatus.present.payableValue, 1.0);
      expect(AttendanceStatus.halfDay.payableValue, 0.5);
      expect(AttendanceStatus.absent.payableValue, 0.0);
    });

    test('MonthlySalaryCalculation computes net salary without holidays/leaves', () {
      final emp = AttendanceEmployee(
        id: 'emp_test_1',
        name: 'Akash Test',
        role: 'Sales & Collection',
        monthlySalary: 30000.0,
      );

      final date1 = DateTime(2026, 11, 1);
      final date2 = DateTime(2026, 11, 2);
      final date3 = DateTime(2026, 11, 3);
      final date4 = DateTime(2026, 11, 4);

      final records = [
        AttendanceRecord(
          id: '1',
          userId: emp.id,
          staffName: emp.name,
          staffRole: emp.role,
          date: date1,
          status: AttendanceStatus.present,
        ),
        AttendanceRecord(
          id: '2',
          userId: emp.id,
          staffName: emp.name,
          staffRole: emp.role,
          date: date2,
          status: AttendanceStatus.halfDay,
        ),
        AttendanceRecord(
          id: '3',
          userId: emp.id,
          staffName: emp.name,
          staffRole: emp.role,
          date: date3,
          status: AttendanceStatus.absent,
        ),
      ];

      final calc = MonthlySalaryCalculation.compute(
        employee: emp,
        year: 2026,
        month: 11,
        monthRecords: records,
      );

      expect(calc.totalDaysInMonth, 30);
      expect(calc.presentCount, 1);
      expect(calc.halfDayCount, 1);
      expect(calc.absentCount, 1);
      expect(calc.payableDays, 1.5); // 1 + 0.5
      expect(calc.dailyRate, 1000.0); // 30000 / 30
      expect(calc.earnedSalary, 1500.0); // 1.5 * 1000
      expect(calc.netSalary, 1500.0);
      expect(calc.absentDates.length, 1);
      expect(calc.absentDates.first.day, 3);
    });
  });
}
