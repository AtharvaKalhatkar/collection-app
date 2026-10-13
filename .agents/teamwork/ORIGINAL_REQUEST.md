# Original User Request

## 2026-10-05T14:40:07Z

Comprehensive end-to-end testing, error detection, and bug fixing across the entire Daily Collection Flutter web application using a full multi-agent team.

Working directory: /home/aathu/daily_collection_app
Integrity mode: development

## Requirements

### R1. Comprehensive Automated Test Execution & Static Analysis
Execute all unit tests, widget tests, and static analysis across the entire project. Detect and document any failing assertions, uncaught runtime exceptions, deprecated APIs, or lint warnings.

### R2. Core User Flow & Module Verification
Perform systematic verification of each major functional module:
- **Overview Dashboard & Firm Info**: Verification of metrics display, minimal payment modes, quick QR triggers, and firm details modal (Purva Enterprises & Manas Sales).
- **Outlets & Routes**: Verification of route ordering, outlet filtering, search, and store details.
- **Pending Bills & Document Proof**: Verification of pending bill creation, photo capture, compression, persistent storage, and full-screen image inspection without memory/quota crashes.
- **Make Collection & Installment History**: Verification of single & partial payment recording, prior payment installment breakdown, balance due recalculation, and payment mode selection with bank assignment.
- **Statement & Export Engine**: Verification of statement filtering (date range, route, outlet, firm), PDF statement generation, and Excel (.xlsx) export including the deposit bank column.
- **Order Booking & Dispatch**: Verification of catalog lookups, custom product addition, multi-shop order booking, and billing PDF generation.

### R3. Targeted Bug Remediation & Regression Testing
Fix all discovered runtime errors, broken interactions, layout overflows, or data persistence anomalies. Preserve existing business rules (dual-firm separation, route priorities, and preserved invoice proofs).

### R4. Production Web Build & Deployment Validation
Validate that the web release builds cleanly without compilation errors or tree-shaking failures.

## Verification Resources
- Test suite: `test/widget_test.dart`, `test/orders_feature_test.dart`, `test/custom_date_and_crud_test.dart`, `test/dual_firm_tracking_test.dart`, `test/bill_tracking_test.dart`
- Analyzer: `dart analyze`
- Build script: `flutter build web --release --base-href /collection-app/`

## Acceptance Criteria

### Automated Verification
- [ ] `flutter test` executes all test files and reports 100% passing tests (zero test failures).
- [ ] `dart analyze` reports 0 errors and 0 warnings.
- [ ] `flutter build web --release --base-href /collection-app/` executes and generates `build/web` without build errors.

### Functional Integrity
- [ ] All payment modes (Cash, UPI, Cheque, NetBanking) record transactions correctly with their corresponding bank choices.
- [ ] Multi-installment payments accurately compute and show previous payments and remaining balance due.
- [ ] Document bill photos load, render thumbnails, and support pinch-to-zoom without base64 decoding crashes.
- [ ] Statement exports in PDF and Excel format contain valid formatting, correct totals, and deposit bank columns.
- [ ] No regression occurs in route priorities, shop ordering, or existing orders features.
