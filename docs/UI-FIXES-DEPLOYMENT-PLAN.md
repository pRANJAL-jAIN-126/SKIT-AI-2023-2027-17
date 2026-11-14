# UI fixes – deployment plan and execution record

## Execution record (2026-11-14, Developer Edition org "SKIT" / CollegeProject)

| Step | Result |
|---|---|
| Backups | `D:\CarRental-backups\2026-11-14\` – `vehicle-images-before.csv`, `vehicle-images-after.csv`, `site-before/` (live site bundle), `site-deploy/` (the 3 changed site files) |
| 1. LWC + static resource | Deploy `0AfgK00000ZtS4LSAV` Succeeded, 13/13; follow-up fix to `carFleetSearch` (Clear filters with unparseable number text) deploy `0AfgK00000ZtV3pSAF` Succeeded, 1/1 |
| 2. Vehicle images | 21 updated, 0 skipped; before/after CSV diff shows only `Image_URL__c` changed |
| 3. Site | Bundle deploy `0AfgK00000ZtSdpSAF` Succeeded (43/43): header added, empty Image + unconfigured chat removed, hero padding 48→24 px, Error page → `c-site-not-found`. Published twice (`sf community publish`). Self-registration left **off** (no registration account/profile configured); the header's Sign up stays hidden |
| 4. Apex jobs | Not needed (no Apex deployed); jobs untouched |

The original plan follows.

Branch `Nitin`. Everything below changes the **CollegeProject** org.
Local checks already done: LWC Jest 55/55, ESLint clean, Apex tests 144/144 (94% coverage),
and a check-only `sf project deploy validate` of the LWC + static-resource changes (13/13 components, nothing saved).

## Step 1 – Deploy code (LWC + static resource)

```bash
sf project deploy start -o CollegeProject \
  --source-dir force-app/main/default/lwc \
  --source-dir force-app/main/default/staticresources
```

| Component | Change |
|---|---|
| `staticresources/VehicleImages` (new, 2.2 MB, Public cache) | 20 licensed vehicle photos, 960 × 600 |
| `lwc/vehiclePhoto` (new) | Shared photo + licence credit + fallback (cards and detail page) |
| `lwc/siteHeader` (new) | Customer navigation (guest vs logged-in, mobile menu) |
| `lwc/siteNotFound` (new) | Friendly 404 with Back to search / Home |
| `lwc/vehicleCard` | Uses `c-vehicle-photo` |
| `lwc/bookingForm` | Uses `c-vehicle-photo`; unavailable-car panel with Back to search; date messages; login wording |
| `lwc/carFleetSearch` | Clear filters resets everything; invalid filters block search; URL date fix; More filters on phones; alignment |
| `lwc/rentalUtils` | `resolveImageUrl`, `getUrlDateParam`, `dateBadInputMessage` |

No Apex is deployed, so the scheduled-job lock (see Step 4) does not block this step.
**Rollback:** `git checkout ca6bbb5 -- force-app/main/default/lwc` and deploy the same folders again
(new components can stay; they are not used by anything until Step 3).

## Step 2 – Point vehicles at the new photos (data change: 21 records, `Image_URL__c` only)

```bash
sf apex run -o CollegeProject -f scripts/apex/update-vehicle-images.apex
```

- Updates a record only when its registration **and** make/model match; anything else is skipped and logged.
- No flow or trigger runs on `Vehicle__c` update; the two Vehicle validation rules (rate > 0, seats 2–9) are unaffected.
- VEH-0020 (`RJ14-DEMO-0001`, Jaipur Demo Branch, 2025) is a **separate demo Kia Carens**, not a duplicate of VEH-0004
  (`RJ14 JK 1357`). It had no image; it gets the Kia Carens photo. Neither record is deleted.

**Rollback:** previous values were `https://placehold.co/640x400/0B5CAB/FFFFFF?text=<Make>%20<Model>` for 20 records
and blank for VEH-0020.

## Step 3 – Experience Builder (site "Smart Car Rental", manual, then Publish)

Found by retrieving the live site metadata (read-only):

| Page / area | Current state | Change | Fixes |
|---|---|---|---|
| Home → hero section | Empty **Image** component (`dxp_base:image`, 350 px, no image) under the title | Delete it | Large empty gap (#7) |
| Home → hero section | **Embedded Messaging** component with *no deployment / site endpoint* (a second, configured one sits next to the search) | Delete the unconfigured one; keep `Service_Agent_Channel` | Console errors "bootstrap.min.js failed to load" |
| Home → hero rich text | `padding:48px 16px` | Optional: reduce to `24px 16px` | Tighter hero (#7) |
| Theme → Theme Header region (layout *Scoped Header and Footer*) | Empty | Add **Rental Site Header** | Missing site menu (#5) |
| Navigation menu | Only default "Topics" | No change needed (the header component has its own links) | – |
| Error page | Rich text "Invalid Page" | Replace with **Rental Page Not Found** | 404 experience (#6) |
| Administration → Login & Registration | Self-registration **off** | Optional: enable, choose profile/account, then set the header's *Show Sign up* = on | Sign up link |

## Step 4 – Org setting needed for future Apex deployments

Full-project validation fails because 18 scheduled jobs (Rental Hold Expiry ×12, Overdue Check, Licence Retention, …)
lock the Apex classes. Before the next Apex deploy, either enable
**Setup → Deployment Settings → Allow deployments of components when corresponding Apex jobs are pending or in progress**,
or pause the jobs and re-schedule them afterwards with `RentalJobScheduler.scheduleAll()`. Both need approval.
