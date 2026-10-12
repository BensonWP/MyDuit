# AGENTS.md — MyDuit

Local-first Flutter personal finance app (Indonesian locale). All data in on-device SQLite via Drift. No backend, no accounts, no CI.

## Stack

Flutter + Drift (SQLite) + Riverpod (`flutter_riverpod`). Notifications (`flutter_local_notifications`), biometrics (`local_auth`). Design tokens: `lib/theme/app_theme.dart` (`class D`), spec: `DESIGN.md`.

## Commands

```bash
flutter pub get
flutter test                    # full suite (unit + widget)
flutter test test/database_test.dart   # single file; same pattern for others in test/
flutter analyze
flutter build apk --release    # output: build/app/outputs/flutter-apk/app-release.apk
```

Drift codegen — rerun after editing `lib/db/database.dart`:
```bash
dart run build_runner build --delete-conflicting-outputs   # regenerates database.g.dart
```
Never hand-edit `database.g.dart`. One-off asset script (already normalized to 96×96): `powershell -File tools\normalize_wallets.ps1`.

## Architecture

- Entrypoint `lib/main.dart`: `MyApp → SplashScreen → LockGate → MainShell`. `MainShell` is a `PageView` of 5 tabs (Beranda, Laporan, Dompet, Tagihan, Profil); FAB "Tambah" only on first 2 tabs.
- Single DB access: `dbProvider` in `lib/providers/database_provider.dart`. Bill list + balance projection both derive from `activeBillsDetailedProvider` — never add a second bills query.
- Dates stored as ISO-8601 strings (`toIso8601String()`); locale `id_ID` requires `initializeDateFormatting('id_ID')` before use (done in `main()`, tests do it in `setUpAll`).
- Amounts are `int` rupiah. Format via `lib/utils/currency.dart` (`formatRupiah`, `CurrencyInputFormatter` clamps 15 digits).

## Database invariants (`lib/db/database.dart`, schema v11)

- Tables never dropped (except v8 `DROP plans`); migrations only `createTable`/`addColumn`/`createIndex`. Follow that pattern for v12+.
- Brands are FULL master data in `customBrands`. Only the **"top" built-ins** are seeded (4 e-wallet: gopay/ovo/dana/shopeepay; 4 bank: bca/bri/mandiri/bni; 5 card: visa/mastercard/jcb/gpn/amex) at v11/migration + `onCreate` (`builtin=1`, `sortOrder`); other brands (LinkAja, BSI, Bank Jago, …) are added by the user via Kelola Brand. `WalletBrand.seed` in `lib/utils/wallet_brand.dart` is ONLY the seed/logo source — runtime reads the table via `brandsProvider` / `brandsByKindProvider`. `seedBuiltinBrands` uses `insertOrIgnore`, so old users who still hold legacy built-in rows keep them (not deleted). Kinds: `bank`/`ewallet`/`card`. `deleteBrand` throws when any wallet uses it (warning lists wallets + balances via `brandWallets`). Logos are PNG blobs in-DB (192px via `normalizeLogoBytes`); built-in asset PNGs are backfilled to blobs once at startup by `lib/services/brand_logo_backfill.dart` (DB layer can't `rootBundle`, so seed only writes rows). Partial updates must use `UPDATE…WHERE…write`, not `insertOnConflictUpdate` (it demands required cols like `createdAt`). Kelola Brand UI: `BrandKindScreen` (pilih jenis, entry from Profil) → `BrandListScreen(kind:)` filtered list; `BrandFormScreen(initialKind:)` pre-selects the kind from the filtered FAB.
- Wallets must never go negative. Always use `insertTransaction` / `updateTransaction` / `payBillWithTransaction` — they throw `InsufficientBalanceException`. Never `into(transactions).insert` directly in app code.
- Wallet delete is archive-first: `archiveAccount` / `unarchiveAccount` (soft delete, `accountBalance` still reads last balance for archived rows; `totalBalance` excludes them). `deleteAccountCascade` is the permanent path behind an explicit menu — never long-press.
- Always use cascade deletes: `deleteAccountCascade`, `deleteTransactionCascade` (reactivates a completed installment), `deleteBillCascade`. Raw deletes violate FKs (`PRAGMA foreign_keys = ON`).
- Undo: `captureTransactionUndo` / `captureBillUndo` must run *before* the cascade delete, `restore*Undo` after.
- Bills: `durationMonths == 0` = perpetual subscription; `N` = installment auto-completing (`active=false, completed=true`) on Nth payment. Projection math lives in `billHitsMonth` / `billsForMonth` / `billsThroughMonth` — reuse, don't reimplement.
- Categories are user-managed master data: `insertCategory` / `updateCategory` / `archiveCategory` / `unarchiveCategory` (soft delete, history intact). Two fallback presets can't be archived — `archiveCategory` throws for `cat_other` (expense) and `cat_other_income` (income). Pickers use `activeCategoriesProvider`; name resolution keeps full `categoriesStreamProvider`.
- Budgets are per-expense-category monthly soft limits (warning-only, never block). `setBudget(id, amount)` upserts, `≤ 0` deletes; throws `ArgumentError` for income/unknown categories. Status math is pure (`budgetState` ≥80% warning, >100% over, `spentByCategory`, `budgetAlerts`) — unit-test those, not the providers. `watchBudgets` hides archived categories (restored on unarchive).
- Reports math is pure in `lib/utils/report_math.dart`: `computeReportTotals(List<Transaction>) → ReportTotals` (income/expense totals + `CategoryTotal` rows per category, sorted desc), `monthShortName(int)`, `expenseDeltaText(...)`. Unit-test those (`test/report_math_test.dart`), not the widgets.
- Screens (`lib/screens/`) are split by feature: `home_screen.dart` is a thin composition shell over `lib/screens/home/*` (`home_common.dart`, `home_hero_card.dart`, `home_unpaid_bills.dart`, `home_week_summary.dart`, `home_wallet_rail.dart`, `home_day_sheet.dart`); `reports_screen.dart` is a `DefaultTabController` shell over `lib/screens/reports/*` (`reports_summary_tab.dart`, `reports_stats.dart`, `reports_donut_card.dart`, `reports_flow_trend.dart`, `reports_budget_section.dart`). Shared public widgets live in `lib/widgets/` (`FlowToggle` in `flow_toggle.dart`, `SectionHeader` in `section_header.dart`). Public API kept stable: `HomeScreen`, `ReportsScreen`, `FlowToggle`, `showDayTransactionsSheet`, `HistoryTab`/`HistoryTabState`; the single `summaryToHistoryKey` `GlobalKey<HistoryTabState>` links the summary donut legend to the Transaksi tab.
- Tests use `MyDuitDatabase.testing()` (in-memory). Widget tests must unmount + settle to avoid pending-Timer failure:
  ```dart
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  ```

## Gotchas (verified, non-obvious)

- Date-range queries are string ranges `[from, to)` on `YYYY-MM-DD`. For "today inclusive" set `to` = tomorrow: `"…T14:30" > "…"` lexicographically, so `to=today` silently drops today's transactions (see `last7DaysFlowProvider`, test '7 hari').
- `watchTransactionsFiltered` search escapes LIKE wildcards — `%`/`_` match literally.
- Backup/restore (`lib/services/backup_service.dart`): `FilePicker.saveFile` **requires `bytes:`** on Android/iOS; `validateBackupFile` requires `{accounts, transactions, bills, custom_brands}` — add any new core table there. Rejects `user_version > currentSchemaVersion`; restore snapshots current DB to `myduit_pre_restore_*`, deletes `-wal`/`-shm` sidecars, then `ref.invalidate(dbProvider)`.
- Notifications (`lib/services/notification_service.dart`): idempotent `rescheduleAll` (cancelAll + reschedule) is already wired to `activeBillsDetailedProvider` in `MainShell` — call it after any bill mutation path that bypasses that listener. Inexact alarms, 08:00 on due day, day 29–31 clamped to month length (mirrored by `daysUntilDue` in `lib/utils/dates.dart`).
- Nav loop guard in `MainShell` (`_navAnimating`/`_swiping`) prevents multi-tab jumps landing mid-way — don't remove.
- `MediaQuery.disableAnimations` must gate every animation (reduced-motion rule, incl. splash hold 1400ms).
- Cinematic unlock: `LockGate` exit phase (fade + 1.06 zoom, 280ms) then bumps `unlockNonceProvider`; `HomeScreen` replays entrance via `KeyedSubtree('home-$nonce')` (one-shot, no test impact). `LockScreen` takes optional `authenticate` override — real `local_auth` channel hangs in flutter_test, so widget tests must inject `() async => true/false`.
- Category colors: manual hash in `lib/utils/category_color.dart`, not `String.hashCode` (must stay stable across sessions/platforms).
- `MyDuitDatabase.testing()` still runs `onCreate` seed — the preset categories (incl. `cat_other`) AND the 13 seeded top brands exist in tests; don't re-insert them. Built-in brand logos are null in tests (backfill needs an asset bundle, skipped there).
- `README.md` was stale (schema v6 / 31 tests); it now reads v11. Trust `currentSchemaVersion` (= 11) in code.
