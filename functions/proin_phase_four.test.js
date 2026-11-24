const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, "..", relativePath), "utf8");
}

test("Phase 4 Proin corrections and settlement records are privileged", () => {
  const indexSource = source("functions/index.js");
  const backendSource = source("functions/proin_backend.js");
  const rulesSource = source("firestore.rules");

  for (const callable of [
    "revokeProinAsAdmin",
    "markProinReimbursementSettledAsAdmin",
  ]) {
    assert.match(indexSource, new RegExp(`exports\\.${callable} = onCall`));
  }
  assert.match(indexSource, /requirePlatformAdministrator\(request\)/);
  assert.match(indexSource, /requiredAdminReason\(request\.data\?\.reason\)/);
  assert.match(backendSource, /Only active, unexpired and unused Proin/);
  assert.match(backendSource, /proinIdempotencyKeys/);
  assert.match(backendSource, /proinSettlementPaymentReferences/);
  assert.match(backendSource, /paymentReferenceHash/);
  assert.match(backendSource, /proin\.available_lot_revoked/);
  assert.match(backendSource, /proin\.reimbursement_settled/);
  assert.match(
    rulesSource,
    /match \/proinSettlementPaymentReferences\/\{referenceHash\}/,
  );
});

test("Phase 4 gives customers a server-filtered Proin statement", () => {
  const indexSource = source("functions/index.js");
  const backendSource = source("functions/proin_backend.js");
  const stateSource = source("lib/state/app_state.dart");
  const profileSource = source(
    "lib/screens/customer/customer_profile_screen.dart",
  );

  assert.match(indexSource, /exports\.getCustomerProinActivity = onMobileCall/);
  assert.match(backendSource, /where\("walletId", "==", walletId\)/);
  assert.match(backendSource, /orderBy\("createdAt", "desc"\)/);
  assert.match(stateSource, /refreshCustomerProinActivity/);
  assert.match(profileSource, /customer-proin-view-activity/);
  assert.match(profileSource, /customer-proin-activity-sheet/);
  assert.match(profileSource, /Unused promotional Proin removed by SalonFe/);
  assert.match(profileSource, /Upcoming expiries/);
  assert.match(profileSource, /Valid until/);
});

test("legacy salon credit APIs remain available while the owner UI shows Balance", () => {
  const indexSource = source("functions/index.js");
  const backendSource = source("functions/proin_backend.js");
  const stateSource = source("lib/state/app_state.dart");
  const dashboardSource = source(
    "lib/screens/salon/salon_dashboard_screen.dart",
  );

  assert.match(indexSource, /exports\.getSalonProinWallet = onMobileCall/);
  assert.match(indexSource, /exports\.claimSalonProinCoupon = onMobileCall/);
  assert.match(indexSource, /salonSnapshot\.data\(\)\?\.ownerUid/);
  assert.match(backendSource, /salonWalletData/);
  assert.match(backendSource, /salon_promotion_credits/);
  assert.match(stateSource, /refreshSalonProinWallet/);
  assert.match(stateSource, /claimSalonProinCoupon/);
  assert.match(dashboardSource, /SalonBalanceScreen/);
  assert.doesNotMatch(dashboardSource, /salon-proin-coupon-field/);
  assert.match(indexSource, /exports\.getSalonBalanceSummary = onMobileCall/);
  const balanceSource = source("lib/screens/salon/salon_balance_screen.dart");
  for (const label of ["Deposit amount", "Discount", "Balance", "SalonFe earning"]) {
    assert.ok(balanceSource.includes(label));
  }
});

test("Phase 4 reconciliation includes settled reimbursement evidence", () => {
  const backendSource = source("functions/proin_backend.js");

  assert.match(backendSource, /settledFromReimbursements/);
  assert.match(backendSource, /invalidSettlementReferences/);
  assert.match(backendSource, /settlementReferenceScanTruncated/);
  assert.match(
    backendSource,
    /settledFromReimbursements === finance\.settledExpenseInr/,
  );
});

test("salon-funded discounts keep the Proin ledger in step", () => {
  const indexSource = source("functions/index.js");
  const backendSource = source("functions/proin_backend.js");
  const discountSource = source("functions/discount_logic.js");

  assert.match(indexSource, /proinBackend\.redeemSalonCreditLotsInTransaction\(/);
  assert.match(indexSource, /let remainingLotBackedAmount = payoutAmount;/);
  assert.match(indexSource, /refreshWalletExpiry\(salonCreditWalletToRefresh\)/);
  assert.doesNotMatch(indexSource, /function discountSalonPromotionCreditLimit/);
  assert.match(discountSource, /function discountSalonPromotionCreditLimit/);
  assert.match(backendSource, /unallocatedBudgetInr: fieldValue\.increment\(redeemedProin\)/);
});
