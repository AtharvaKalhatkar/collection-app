import 'package:flutter_test/flutter_test.dart';
import 'package:daily_collection_app/models/attendance_record.dart';
import 'package:daily_collection_app/models/user_model.dart';
import 'package:daily_collection_app/screens/attendance_screen.dart';

void main() {
  group('Attendance & Payroll Smart Feature Tests', () {
    test('Access Control: Only SuperAdmin, Office, and Akash have access', () {
      final superAdmin = UserModel(
        id: 'u1',
        name: 'Super Admin',
        phone: '9999999999',
        role: UserRole.superAdmin,
        password: 'pass',
      );
      final office = UserModel(
        id: 'u2',
        name: 'Office Staff 1',
        phone: '8888888888',
        role: UserRole.office,
        password: 'pass',
      );
      final akash = UserModel(
        id: 'u3',
        name: 'Akash',
        phone: '7777777777',
        role: UserRole.salesman,
        password: 'pass',
      );
      final otherSalesman = UserModel(
        id: 'u4',
        name: 'Rahul',
        phone: '6666666666',
        role: UserRole.salesman,
        password: 'pass',
      );
      final driver = UserModel(
        id: 'u5',
        name: 'user1',
        phone: '5555555555',
        role: UserRole.driver,
        password: 'pass',
      );

      expect(canViewAttendance(superAdmin), isTrue);
      expect(canViewAttendance(office), isTrue);
      expect(canViewAttendance(akash), isTrue);
      expect(canViewAttendance(otherSalesman), isFalse);
      expect(canViewAttendance(driver), isFalse);
    });

    test('Monthly Salary Calculation: Full days, Half days, Holidays, and Deductions', () {
      final employee = AttendanceEmployee(
        id: 'emp_akash',
        name: 'Akash',
        role: 'Sales & Collection',
        phone: '9876543210',
        monthlySalary: 21000.0,
      );

      // 30 days in November 2026:
      // 20 Present
      // 2 Half Days (= 1.0 day)
      // 4 Sundays / Holidays (= 4.0 days)
      // 2 Paid Leaves (= 2.0 days)
      // 2 Absents (= 0.0 days)
      // Total payable days = 20 + (2 * 0.5) + 4 + 2 = 27.0 days out of 30
      final records = <AttendanceRecord>[];
      for (int i = 1; i <= 20; i++) {
        records.add(AttendanceRecord(
          id: 'r_p_$i',
          userId: employee.id,
          staffName: employee.name,
          staffRole: employee.role,
          date: DateTime(2026, 11, i),
          status: AttendanceStatus.present,
        ));
      }
      for (int i = 21; i <= 22; i++) {
        records.add(AttendanceRecord(
          id: 'r_hd_$i',
          userId: employee.id,
          staffName: employee.name,
          staffRole: employee.role,
          date: DateTime(2026, 11, i),
          status: AttendanceStatus.halfDay,
        ));
      }
      for (int i = 23; i <= 26; i++) {
        records.add(AttendanceRecord(
          id: 'r_h_$i',
          userId: employee.id,
          staffName: employee.name,
          staffRole: employee.role,
          date: DateTime(2026, 11, i),
          status: AttendanceStatus.holiday,
        ));
      }
      for (int i = 27; i <= 28; i++) {
        records.add(AttendanceRecord(
          id: 'r_l_$i',
          userId: employee.id,
          staffName: employee.name,
          staffRole: employee.role,
          date: DateTime(2026, 11, i),
          status: AttendanceStatus.leave,
        ));
      }
      for (int i = 29; i <= 30; i++) {
        records.add(AttendanceRecord(
          id: 'r_a_$i',
          userId: employee.id,
          staffName: employee.name,
          staffRole: employee.role,
          date: DateTime(2026, 11, i),
          status: AttendanceStatus.absent,
        ));
      }

      final adjustment = SalaryMonthlyAdjustment(
        employeeId: employee.id,
        year: 2026,
        month: 11,
        bonus: 1000.0,
        advanceDeduction: 500.0,
      );

      final calc = MonthlySalaryCalculation.compute(
        employee: employee,
        year: 2026,
        month: 11,
        monthRecords: records,
        adjustment: adjustment,
      );

      expect(calc.totalDaysInMonth, equals(30));
      expect(calc.presentCount, equals(20));
      expect(calc.halfDayCount, equals(2));
      expect(calc.holidayCount, equals(4));
      expect(calc.leaveCount, equals(2));
      expect(calc.absentCount, equals(2));
      expect(calc.payableDays, equals(27.0));

      // Daily rate = 21000 / 30 = 700.0
      expect(calc.dailyRate, equals(700.0));

      // Earned = 27.0 * 700 = 18900.0
      expect(calc.earnedSalary, equals(18900.0));

      // Net = 18900 + 1000 (bonus) - 500 (advance) = 19400.0
      expect(calc.netSalary, equals(19400.0));

      // Check WhatsApp slip format contains key figures
      final slip = calc.formatWhatsAppSlip();
      expect(slip.contains('MONTHLY SALARY SLIP'), isTrue);
      expect(slip.contains('Akash'), isTrue);
      expect(slip.contains('₹19400'), isTrue);
      expect(slip.contains('27.0 / 30 Days'), isTrue);
    });
  });
}
