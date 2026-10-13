## 2026-10-05T14:56:15Z
You are teamwork_preview_explorer_m1_2.
Your working directory is: /home/aathu/daily_collection_app/.agents/teamwork/teamwork_preview_explorer_m1_2/
The project root directory is: /home/aathu/daily_collection_app
You MUST read:
- /home/aathu/daily_collection_app/.agents/teamwork/ORIGINAL_REQUEST.md
- /home/aathu/daily_collection_app/.agents/teamwork/PROJECT.md

Task for Milestone 1 (M1):
Investigate and design the concrete implementation for StatementScreen filtering in `lib/screens/statement_screen.dart`:
1. R2 requires statement filtering by (date range, route, outlet, firm).
2. Currently, StatementScreen only supports single date, firm, and payment mode.
3. Design the UI controls and filtering logic for:
   - Date range selection (or "All Dates" / date-range toggle)
   - Route filter dropdown (populating from CollectionProvider.routes)
   - Outlet / Shop filter (dropdown or search bar, reactive to selected route)
4. Verify how the filtered collection list flows into:
   - UI summary cards & transaction list
   - Excel export (`_exportToExcel`)
   - PDF export (`_exportToPdf`)
5. Write your complete design, code diff proposals, and verification steps in /home/aathu/daily_collection_app/.agents/teamwork/teamwork_preview_explorer_m1_2/handoff.md.
6. When finished, send a message to orchestrator parent (conversation ID: 9c4f8811-06ec-42bc-922e-c45e8b7754dc).
