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

    test('Advance salary deduction correctly subtracts from net salary and shows on slip', () {
      final emp = AttendanceEmployee(
        id: 'emp_advance_test',
        name: 'Rahul Advance',
        role: 'Driver',
        monthlySalary: 24000.0,
      );

      final records = [
        for (int i = 1; i <= 10; i++)
          AttendanceRecord(
            id: 'rec_$i',
            userId: emp.id,
            staffName: emp.name,
            staffRole: emp.role,
            date: DateTime(2026, 11, i),
            status: AttendanceStatus.present,
          ),
      ];

      // 10 days present at 800/day = 8000 earned. Advance given = 2500.
      final adjustment = SalaryMonthlyAdjustment(
        employeeId: emp.id,
        year: 2026,
        month: 11,
        advanceDeduction: 2500.0,
      );

      final calc = MonthlySalaryCalculation.compute(
        employee: emp,
        year: 2026,
        month: 11,
        monthRecords: records,
        adjustment: adjustment,
      );

      expect(calc.payableDays, 10.0);
      expect(calc.dailyRate, 800.0);
      expect(calc.earnedSalary, 8000.0);
      expect(calc.advanceDeduction, 2500.0);
      expect(calc.netSalary, 5500.0); // 8000 - 2500

      final slip = calc.formatWhatsAppSlip();
      expect(slip.contains('➖ Advance Deducted: ₹2500'), isTrue);
      expect(slip.contains('NET SALARY PAYABLE: ₹5500'), isTrue);
    });
  });
}
