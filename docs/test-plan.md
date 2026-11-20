# Yusra Pharmacy — manual test plan

Run this against the real Supabase project with one demo user per role. Use
`tool/seed_demo.dart` first if the project is empty. Record the date, the
tester, the app build (APK or web) and the result of every step.

> **Prerequisite:** all **RUN IN SUPABASE SQL EDITOR** scripts in
> `supabase/README.md` must have been applied, including `0012`, `0013`,
> `0014` and `0015`, and `supabase/checks/schema_check.sql` must return no
> `MISSING` rows.

## Test data

| Role | Demo user | Purpose |
| --- | --- | --- |
| Super admin | `superadmin@yusra.test` | Branch switching, all permissions |
| Admin | `admin@yusra.test` | Catalogue, suppliers, users, settings |
| Pharmacist | `pharmacist@yusra.test` | Dispensing, voids, returns |
| Cashier | `cashier@yusra.test` | POS, own shift |
| Store keeper | `storekeeper@yusra.test` | Stock receipt, stocktake |
| Accountant | `accountant@yusra.test` | Read-only finance and reports |

Demo password is whatever was passed as `SEED_DEMO_PASSWORD` when seeding.

## Golden path

1. **Admin signs in.** Confirm the dashboard loads and the side menu shows
   every module. Sign out.
2. **Admin → catalogue.** Add a category, then add a medicine with a cost
   price, a selling price, VAT enabled and a reorder level. Confirm it appears
   in the medicines list and can be found by name and SKU.
3. **Admin → suppliers.** Add a supplier with a name, contact and phone.
4. **Purchasing.** Create a purchase order with two lines. Confirm the draft
   cannot be received yet. Approve it, then receive both lines with a batch
   number and a future expiry date. Confirm stock appears in the batch list
   and that a stock movement was recorded.
5. **Cashier signs in.** Open a cash shift with a known opening float, e.g.
   ETB 100. Confirm the open-shift banner appears on `/pos`.
6. **POS → sale.** Add the received medicine, set quantity 2, apply an
   allowed discount, select a walk-in customer, and pay with a split:
   ETB 20 cash + ETB 10 mobile money. Confirm:
   - the change is calculated only from the cash tender;
   - the receipt prints in 80 mm layout with invoice number, item lines,
     VAT, totals, payment lines, branch, cashier and date/time in
     `Africa/Addis_Ababa`;
   - stock falls by exactly 2 and the nearest-expiry batch is consumed first.
7. **POS → printed receipt.** Reprint the receipt from the sale detail page
   and confirm the `REPRINT` marker.
8. **Sale return.** As the pharmacist, return one of the two items with
   `restock = true` and a reason. Confirm the return note prints and stock
   increases by 1.
9. **Void.** As the pharmacist, void a different completed sale with a
   reason. Confirm the status becomes voided and stock is restored.
10. **Close shift.** As the cashier, count the drawer and close the shift.
    Confirm the Z report shows opening cash, sale count, totals by payment
    method, expected cash, counted cash and the difference.
11. **Accountant.** Sign in and confirm the dashboard and reports show the
    day's sales and expenses, and that no forbidden edit actions are visible.
12. **Reports.** As the super admin, open all twelve reports. Confirm each
    returns rows or a clean empty state (never an error about a missing view),
    that money columns show ETB, and that filtering by branch works.
13. **Team access.** As the super admin, open `/admin/team`, select two
    teammates and use **Share my access**. Confirm both now show the super
    admin role/branch, an audit row was written, and each can sign in with the
    new permissions. Use **Edit role / branch** to give one of them the
    pharmacist role again and confirm the change survives a sign-out/in.
14. **Publish settings.** In **Settings**, change the receipt footer and save;
    in **Team access**, use **Publish settings to team**. Sign in as a cashier
    and confirm the new footer prints immediately (cache invalidation works).

## Rules and edge cases

| # | Check | Expected |
| --- | --- | --- |
| 1 | Expired stock | An expired batch cannot be sold; a valid batch is used instead. |
| 2 | FEFO | With two valid batches, the earliest expiry is consumed first. |
| 3 | Discount limit | A cashier above the configured percentage gets a readable error and cannot complete the sale. |
| 4 | Pharmacist discount | A pharmacist can grant the same discount. |
| 5 | Prescription-only | An Rx-only medicine cannot be sold without a selected prescription. Selecting one at POS dispenses it. |
| 6 | Quantity limits | Quantity above available stock is rejected; stock never goes negative. |
| 7 | Whole units | Fractional quantities are rejected everywhere. |
| 8 | Payment rules | A sale cannot be completed when the tender is below the total; change is only valid with cash. |
| 9 | Held carts | Hold a cart, restart the app, resume it, and confirm lines and discount survive. |
| 10 | Draft persistence | Start a sale, restart the app, and confirm the draft is restored. |
| 11 | Shift guard | With no open shift, `/pos` blocks selling and offers a link to `/shifts`. |
| 12 | X report | An X report can be printed mid-shift without closing it. |
| 13 | Role menus | Cashier sees no admin, supplier, purchasing or audit entries. Store keeper sees no POS. Accountant sees no edit buttons. |
| 14 | Audit log | A cashier cannot read `audit_logs`; an admin can. |
| 15 | Super admin creation | An admin cannot set a user's role to `super_admin`. |
| 16 | Branch scope | A super admin can switch branches; every other role is confined to their branch. |
| 17 | Offline/empty states | With no data, each list shows an empty state rather than a blank page. |
| 18 | Web build | Log in on the web build, complete a small sale and print/save the receipt to PDF. |
| 19 | Error handling | With the network disabled, a data screen shows a friendly retryable message — never a raw SDK error or a red Flutter error screen. |
| 20 | Cache isolation | Sign out as super admin and sign in as a cashier; receipts, settings and catalogue data refresh for the new user instead of reusing cached values. |
| 21 | Team access guard | An admin can open Team access but cannot share or edit; a cashier has no menu entry and a direct URL is redirected to `forbidden`. |

## Automated equivalents

The checks that can be automated live in `tool/smoke_test.dart` (rules 1–3,
5, 8, 14, 15, plus return/void/close-shift). Run them with:

```bash
export SUPABASE_URL=... SUPABASE_ANON_KEY=...
export SMOKE_ADMIN_EMAIL=... SMOKE_ADMIN_PASSWORD=...
export SMOKE_CASHIER_EMAIL=... SMOKE_CASHIER_PASSWORD=...
export SMOKE_PHARMACIST_EMAIL=... SMOKE_PHARMACIST_PASSWORD=...
export SMOKE_EXPIRED_BATCH_ID=...   # printed by seed_demo.dart
dart run tool/smoke_test.dart
```

Or use the **Manual Supabase smoke test** workflow in the Actions tab and
add the matching repository secrets. The tool exits non-zero on any failure
and refuses to run against a URL containing `prod` unless the confirm input
is set.
