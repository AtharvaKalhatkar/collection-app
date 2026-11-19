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

    test('Multiple advances with exact dates correctly aggregate totalAdvanceDeduction', () {
      final emp = AttendanceEmployee(
        id: 'emp_multi_adv',
        name: 'Suresh Helper',
        role: 'Helper',
        monthlySalary: 15000.0,
      );

      final adv1 = SalaryAdvanceEntry(
        id: 'adv_1',
        employeeId: emp.id,
        year: 2026,
        month: 11,
        amount: 2000.0,
        date: DateTime(2026, 11, 5),
        note: 'Diwali expense',
      );
      final adv2 = SalaryAdvanceEntry(
        id: 'adv_2',
        employeeId: emp.id,
        year: 2026,
        month: 11,
        amount: 3000.0,
        date: DateTime(2026, 11, 15),
        note: 'Emergency medical',
      );

      final adjustment = SalaryMonthlyAdjustment(
        employeeId: emp.id,
        year: 2026,
        month: 11,
        advances: [adv1, adv2],
      );

      expect(adjustment.totalAdvanceDeduction, 5000.0);
      expect(adjustment.advances.length, 2);
      expect(adjustment.advances[0].date.day, 5);
      expect(adjustment.advances[1].date.day, 15);

      final calc = MonthlySalaryCalculation.compute(
        employee: emp,
        year: 2026,
        month: 11,
        monthRecords: [
          for (int i = 1; i <= 20; i++)
            AttendanceRecord(
              id: 'rec_s_$i',
              userId: emp.id,
              staffName: emp.name,
              staffRole: emp.role,
              date: DateTime(2026, 11, i),
              status: AttendanceStatus.present,
            ),
        ],
        adjustment: adjustment,
      );

      expect(calc.earnedSalary, 10000.0); // 20 * (15000 / 30) = 10000
      expect(calc.advanceDeduction, 5000.0); // 2000 + 3000
      expect(calc.netSalary, 5000.0); // 10000 - 5000
    });
  });
}
