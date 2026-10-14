const assert = require("node:assert/strict");
const test = require("node:test");

// Drives the real booking callables against the Firestore emulator, so the
// salon-credit and Proin ledger steps are checked inside the same
// transactions that run in production. No credentials or network are used.
// Every test here shares one emulator project, so each uses its own IDs.
function loadBookingFunctions(t) {
  process.env.GCLOUD_PROJECT = "demo-pritze-booking-ledger";
  const admin = require("firebase-admin");
  const {HttpsError} = require("firebase-functions/v2/https");
  const functions = require("./index");
  const {createProinBackend} = require("./proin_backend");
  const realMessaging = Object.getOwnPropertyDescriptor(admin, "messaging");
  Object.defineProperty(admin, "messaging", {
    configurable: true,
    value: () => ({sendEachForMulticast: async (message) => ({
      successCount: message.tokens.length,
      failureCount: 0,
      responses: message.tokens.map(() => ({success: true})),
    })}),
  });
  t.after(() => {
    if (realMessaging) Object.defineProperty(admin, "messaging", realMessaging);
    else delete admin.messaging;
  });
  return {
    admin,
    functions,
    firestore: admin.firestore(),
    backend: createProinBackend({admin, HttpsError}),
  };
}

test("a salon-funded booking keeps the Proin ledger balanced end to end", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async (t) => {
  const {admin, functions, firestore, backend} = loadBookingFunctions(t);
  const nowMillis = Date.now();
  const set = (path, data) => firestore.doc(path).set(data);
  await Promise.all([
    set("users/customer-1", {
      role: "customer",
      activeRole: "customer",
      name: "Ledger Customer",
      phone: "+919000000001",
      completedBookingCount: 0,
    }),
    set("users/owner-1", {role: "owner", activeRole: "owner"}),
    set("users/barber-1", {role: "barber", activeRole: "barber"}),
    set("platformAdmins/admin-1", {active: true}),
    set("salons/salon-1", {
      ownerUid: "owner-1",
      isOpen: true,
      approvalStatus: "approved",
      instantBookingsEnabled: true,
      openTime: "12:00 AM",
      closeTime: "11:59 PM",
      services: [
        {id: "haircut", name: "Haircut", price: 400, durationMinutes: 30},
      ],
    }),
    set("barbers/barber-1", {
      salonId: "salon-1",
      uid: "barber-1",
      serviceIds: ["haircut"],
    }),
    set("platformFinance/discountVault", {
      availableAmount: 5000,
      reservedAmount: 0,
      spentAmount: 0,
    }),
    set("discountCampaigns/salon-funded", {
      active: true,
      name: "Salon funded offer",
      fundingSource: "salon_promotion_credits",
      discountType: "fixed",
      fixedDiscountAmount: 50,
      totalPayoutBudget: 5000,
      maximumUsesPerCustomer: 10,
      salonIds: ["salon-1"],
    }),
  ]);

  await backend.setFinanceBudget({
    adminUid: "admin-1",
    data: {approvedBudgetInr: 5000},
    reason: "Approve isolated booking ledger test budget",
  });
  const program = (overrides) => backend.upsertProgram({
    adminUid: "admin-1",
    reason: "Create isolated booking ledger test program",
    data: {
      name: "Booking ledger test",
      sourceType: "manual",
      qualificationEvent: "manual_approval",
      active: true,
      rewardValidityDays: 14,
      totalBudgetProin: 5000,
      maximumTotalGrants: 10,
      maximumGrantsPerAccount: 1,
      minimumBookingAmount: 0,
      maximumRedemptionPercent: 100,
      stackableWithDiscount: true,
      startsAtMillis: nowMillis - 60_000,
      endsAtMillis: nowMillis + 24 * 60 * 60 * 1000,
      eligibleSalonIds: [],
      eligibleServiceIds: [],
      termsVersion: "booking-ledger-v1",
      ...overrides,
    },
  });
  await program({
    programId: "ledger_salon_credit",
    walletType: "salon_promotion_credits",
    rewardAmountProin: 120,
    maximumProinPerBooking: 120,
    maximumGrantsPerAccount: 2,
  });
  await program({
    programId: "ledger_customer_reward",
    walletType: "customer_rewards",
    rewardAmountProin: 30,
    maximumProinPerBooking: 30,
  });
  const grant = (programId, walletType, accountId, key = "first") =>
    backend.grantAsAdmin({
      adminUid: "admin-1",
      reason: "Grant isolated booking ledger test reward",
      data: {
        programId,
        walletType,
        accountId,
        idempotencyKey: `booking-ledger:${programId}:${key}`,
      },
    });
  const salonGrant = await grant(
    "ledger_salon_credit",
    "salon_promotion_credits",
    "salon-1",
  );
  await grant("ledger_customer_reward", "customer_rewards", "customer-1");

  const lotRef = firestore.collection("proinLots").doc(salonGrant.lotId);
  const walletRef = firestore.collection("proinWallets")
    .doc(salonGrant.walletId);
  const financeRef = firestore.doc("proinFinance/current");
  const read = async (ref) => (await ref.get()).data();
  const balanced = async () => {
    const report = await backend.reconcile();
    assert.equal(report.status, "balanced", JSON.stringify(report));
  };

  // A locked checkout quote for the salon-funded offer, as the quote callable
  // stores it. The payout is what the salon's promotional credit must cover.
  const book = async (quoteId, pritzePayoutAmount, requestedProin = 0) => {
    await set(`discountQuotes/${quoteId}`, {
      customerUid: "customer-1",
      salonId: "salon-1",
      serviceIds: ["haircut"],
      originalAmount: 400,
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 600_000),
      discountCampaignId: "salon-funded",
      discountCampaignName: "Salon funded offer",
      discountFundingSource: "salon_promotion_credits",
      discountType: "fixed",
      fixedDiscountAmount: 50,
      discountBaseAmount: 400,
      discountAmount: 50,
      customerPayableAmount: 350,
      pritzePayoutAmount,
      salonTotalEarning: 350 + pritzePayoutAmount,
    });
    const result = await functions.createBooking.run({
      auth: {uid: "customer-1"},
      data: {
        salonId: "salon-1",
        serviceId: "haircut",
        isInstant: true,
        arrivalMinutes: 15,
        quoteId,
        requestedProin,
      },
    });
    return result.bookingId;
  };
  const ownerSets = (bookingId, status) => functions.updateBookingStatus.run({
    auth: {uid: "owner-1"},
    data: {bookingId, status},
  });
  const adminSetsCreditLimit = (creditLimitProin) =>
    functions.setSalonPromotionCreditLimitAsAdmin.run({
      auth: {uid: "admin-1", token: {}},
      data: {
        salonId: "salon-1",
        creditLimitProin,
        reason: "Change isolated booking ledger test credit limit",
      },
    });

  // 1. Granted credit covers the whole payout and the customer also uses
  //    Proin, so both ledgers move in the same transactions.
  const first = await book("quote-1", 80, 30);
  const held = await read(firestore.collection("bookings").doc(first));
  assert.equal(held.discountStatus, "reserved");
  assert.equal(held.proinReservedAmount, 30);
  assert.equal(held.customerPayableAmount, 320);
  assert.deepEqual(
    [(await read(lotRef)).availableProin, (await read(lotRef)).reservedProin],
    [40, 80],
  );
  assert.equal((await read(financeRef)).reservedLiabilityInr, 30);
  assert.equal((await read(financeRef)).outstandingLiabilityInr, 150);
  await balanced();

  for (const status of ["confirmed", "inProgress", "completed"]) {
    assert.equal((await ownerSets(first, status)).status, status);
  }
  const completed = await read(firestore.collection("bookings").doc(first));
  assert.equal(completed.discountStatus, "redeemed");
  assert.equal(completed.proinRedeemedAmount, 30);
  const lotAfterFirst = await read(lotRef);
  assert.equal(lotAfterFirst.availableProin, 40);
  assert.equal(lotAfterFirst.reservedProin, 0);
  assert.equal(lotAfterFirst.redeemedProin, 80);
  const financeAfterFirst = await read(financeRef);
  // Customer Proin becomes a salon payable; spent salon credit returns to the
  // unallocated budget because its payout is a discount-vault settlement.
  assert.equal(financeAfterFirst.outstandingLiabilityInr, 40);
  assert.equal(financeAfterFirst.reservedLiabilityInr, 0);
  assert.equal(financeAfterFirst.redeemedPayableInr, 30);
  assert.equal(financeAfterFirst.unallocatedBudgetInr, 4930);
  assert.equal(
    (await read(firestore.doc(`proinSalonReimbursements/${first}`))).amountInr,
    30,
  );
  assert.equal(
    (await read(firestore.doc(`salonSettlements/${first}`))).pritzePayoutAmount,
    80,
  );
  await balanced();

  // 2. The payout is larger than the credit left: the lot is used first and
  //    the credit line covers the rest. Rejecting the booking undoes both.
  const second = await book("quote-2", 100);
  assert.deepEqual(
    [(await read(lotRef)).availableProin, (await read(lotRef)).reservedProin],
    [0, 40],
  );
  assert.equal((await read(walletRef)).availableProin, -60);
  assert.equal((await read(walletRef)).reservedProin, 100);
  await balanced();
  assert.equal((await ownerSets(second, "rejected")).status, "rejected");
  assert.equal((await read(lotRef)).availableProin, 40);
  assert.equal((await read(walletRef)).availableProin, 40);
  assert.equal((await read(walletRef)).reservedProin, 0);
  assert.equal((await read(financeRef)).outstandingLiabilityInr, 40);
  await balanced();

  // 3. The same split, completed: the lot is fully spent and only the
  //    lot-backed part leaves the Proin liability.
  const third = await book("quote-3", 100);
  for (const status of ["confirmed", "inProgress", "completed"]) {
    await ownerSets(third, status);
  }
  const lotAfterThird = await read(lotRef);
  assert.equal(lotAfterThird.availableProin, 0);
  assert.equal(lotAfterThird.redeemedProin, 120);
  const walletAfterThird = await read(walletRef);
  assert.equal(walletAfterThird.availableProin, -60);
  assert.equal(walletAfterThird.lifetimeRedeemedProin, 180);
  const financeAfterThird = await read(financeRef);
  assert.equal(financeAfterThird.outstandingLiabilityInr, 0);
  assert.equal(financeAfterThird.unallocatedBudgetInr, 4970);
  assert.equal(financeAfterThird.redeemedPayableInr, 30);
  await balanced();

  // 4. With the credit line at its limit the offer is withdrawn at checkout
  //    instead of the booking being refused when the credit is reserved.
  await adminSetsCreditLimit(60);
  await assert.rejects(
    book("quote-4", 100),
    /This discount is no longer available/,
  );
  const withoutOffer = await functions.createBooking.run({
    auth: {uid: "customer-1"},
    data: {
      salonId: "salon-1",
      serviceId: "haircut",
      isInstant: true,
      arrivalMinutes: 15,
    },
  });
  const plain = await read(
    firestore.collection("bookings").doc(withoutOffer.bookingId),
  );
  assert.equal(plain.customerPayableAmount, 400);
  await balanced();

  // 5. New credit lifts the balance above zero, but the Rs 60 already used on
  //    the credit line still stands. A limit below it would leave the new
  //    credit unable to expire, so it is refused.
  await grant(
    "ledger_salon_credit",
    "salon_promotion_credits",
    "salon-1",
    "second",
  );
  assert.equal((await read(walletRef)).availableProin, 60);
  await assert.rejects(
    adminSetsCreditLimit(0),
    /already used on its credit line/,
  );
  assert.equal((await adminSetsCreditLimit(60)).creditLimitProin, 60);
  await balanced();
});

// Shared fixtures for the deposit and checkout tests below.
async function bookingFixture(
  {admin, firestore, backend, functions},
  suffix,
  salons,
) {
  const set = (path, data) => firestore.doc(path).set(data);
  const nowMillis = Date.now();
  await set(`users/customer-${suffix}`, {
    role: "customer",
    activeRole: "customer",
    name: `Customer ${suffix}`,
    phone: `+9190000${String(suffix).padStart(5, "0")}`,
    completedBookingCount: 0,
  });
  for (const salonId of salons) {
    await Promise.all([
      set(`users/owner-${salonId}`, {role: "owner", activeRole: "owner"}),
      set(`users/barber-${salonId}`, {role: "barber", activeRole: "barber"}),
      set(`salons/${salonId}`, {
        ownerUid: `owner-${salonId}`,
        isOpen: true,
        approvalStatus: "approved",
        instantBookingsEnabled: true,
        openTime: "12:00 AM",
        closeTime: "11:59 PM",
        services: [{id: "cut", name: "Cut", price: 100, durationMinutes: 30}],
      }),
      set(`barbers/barber-${salonId}`, {
        salonId,
        uid: `barber-${salonId}`,
        serviceIds: ["cut"],
      }),
    ]);
  }
  await set("platformFinance/discountVault", {
    availableAmount: 50000,
    reservedAmount: 0,
    spentAmount: 0,
  });
  await backend.setFinanceBudget({
    adminUid: "admin-1",
    data: {approvedBudgetInr: 50000},
    reason: "Approve booking test budget",
  });
  const program = (programId, overrides) => backend.upsertProgram({
    adminUid: "admin-1",
    reason: "Create booking test program",
    data: {
      programId,
      name: programId,
      sourceType: "manual",
      qualificationEvent: "manual_approval",
      active: true,
      rewardValidityDays: 90,
      totalBudgetProin: 100000,
      maximumTotalGrants: 100,
      maximumGrantsPerAccount: 100,
      minimumBookingAmount: 0,
      maximumRedemptionPercent: 25,
      stackableWithDiscount: false,
      startsAtMillis: nowMillis - 60_000,
      endsAtMillis: nowMillis + 24 * 60 * 60 * 1000,
      eligibleSalonIds: [],
      eligibleServiceIds: [],
      termsVersion: "booking-test-v1",
      ...overrides,
    },
  });
  const book = async (salonId, extra = {}) => (await functions(
    "createBooking",
    {
      auth: {uid: `customer-${suffix}`},
      data: {
        salonId,
        serviceId: "cut",
        isInstant: true,
        arrivalMinutes: 15,
        ...extra,
      },
    },
  )).bookingId;
  const complete = async (salonId, bookingId) => {
    for (const status of ["confirmed", "inProgress", "completed"]) {
      await functions("updateBookingStatus", {
        auth: {uid: `owner-${salonId}`},
        data: {bookingId, status},
      });
    }
  };
  const bestOffer = async (salonId) => (await functions(
    "listCheckoutDiscountOffers",
    {
      auth: {uid: `customer-${suffix}`},
      data: {salonId, serviceIds: ["cut"], lockBestOffer: true},
    },
  )).bestOfferQuote;
  const read = async (path) => (await firestore.doc(path).get()).data();
  const grant = (programId, salonId, key, extra = {}) => backend.grantAsAdmin({
    adminUid: "admin-1",
    reason: "Grant booking test credit",
    data: {
      programId,
      walletType: "salon_promotion_credits",
      accountId: salonId,
      idempotencyKey: `booking-test:${key}`,
      ...extra,
    },
  });
  return {set, program, book, complete, bestOffer, read, grant, nowMillis, admin};
}

test("a Pritze deposit pays for discounts and the first-visit earning", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async (t) => {
  const loaded = loadBookingFunctions(t);
  const call = (name, request) => loaded.functions[name].run(request);
  const f = await bookingFixture(
    {...loaded, functions: call},
    7,
    ["deposit-salon", "reward-salon"],
  );
  await f.set("discountCampaigns/first-visit-30", {
    active: true,
    name: "First visit 30%",
    fundingSource: "salon_promotion_credits",
    discountType: "percent",
    discountPercent: 30,
    maximumDiscountAmount: 50,
    salonPayoutPercent: 100,
    payoutMultiplier: 1,
    salonFirstVisitEarningPercent: 10,
    salonFirstVisitEarningMaximumAmount: 50,
    totalPayoutBudget: 50000,
    maximumUsesPerCustomer: 10,
    salonIds: ["deposit-salon", "reward-salon"],
  });
  await f.program("test_salon_deposit", {
    walletType: "salon_promotion_credits",
    salonDeposit: true,
    rewardAmountProin: 1000,
    maximumProinPerBooking: 100000,
  });
  await f.program("test_salon_reward", {
    walletType: "salon_promotion_credits",
    rewardAmountProin: 100,
    maximumProinPerBooking: 100,
  });
  await f.grant("test_salon_deposit", "deposit-salon", "deposit-1");
  await f.grant("test_salon_reward", "reward-salon", "reward-1");
  const depositWallet = await loaded.backend.salonWalletData({
    salonId: "deposit-salon",
  });
  assert.equal(depositWallet.availableProin, 1000);

  // First visit: Rs 100 bill, 30% off is Rs 30, and the salon earns Rs 10.
  const firstQuote = await f.bestOffer("deposit-salon");
  assert.equal(firstQuote.discountAmount, 30);
  assert.equal(firstQuote.salonFirstVisitEarningAmount, 10);
  assert.equal(firstQuote.pritzePayoutAmount, 40);
  const first = await f.book("deposit-salon", {quoteId: firstQuote.quoteId});
  await f.complete("deposit-salon", first);
  // Deposit 1000 - discount 30 - salon earning 10 = 960, and nothing is owed.
  assert.equal(
    (await loaded.backend.salonWalletData({salonId: "deposit-salon"}))
      .availableProin,
    960,
  );
  const firstSettlement = await f.read(`salonSettlements/${first}`);
  assert.equal(firstSettlement.pritzePayoutAmount, 40);
  assert.equal(firstSettlement.salonFirstVisitEarningAmount, 10);
  assert.equal(firstSettlement.prepaidFromDepositAmount, 40);
  assert.equal(firstSettlement.paidAmount, 40);
  assert.equal(firstSettlement.status, "paid");
  const depositSalonWallet = await f.read("salonWallets/deposit-salon");
  assert.equal(depositSalonWallet.payableBalance, 0);
  assert.equal(depositSalonWallet.prepaidFromDepositAmount, 40);

  // Second visit to the same salon: the discount only, no earning.
  const secondQuote = await f.bestOffer("deposit-salon");
  assert.equal(secondQuote.salonFirstVisitEarningAmount, 0);
  assert.equal(secondQuote.pritzePayoutAmount, 30);
  const second = await f.book("deposit-salon", {quoteId: secondQuote.quoteId});
  await f.complete("deposit-salon", second);
  assert.equal(
    (await loaded.backend.salonWalletData({salonId: "deposit-salon"}))
      .availableProin,
    930,
  );
  assert.equal((await f.read(`salonSettlements/${second}`)).status, "paid");

  // Credit a salon earned (not a deposit) is still paid out to the salon.
  const rewardQuote = await f.bestOffer("reward-salon");
  assert.equal(rewardQuote.salonFirstVisitEarningAmount, 10);
  const third = await f.book("reward-salon", {quoteId: rewardQuote.quoteId});
  await f.complete("reward-salon", third);
  const owedSettlement = await f.read(`salonSettlements/${third}`);
  assert.equal(owedSettlement.prepaidFromDepositAmount, 0);
  assert.equal(owedSettlement.paidAmount, 0);
  assert.equal(owedSettlement.status, "payable");
  assert.equal((await f.read("salonWallets/reward-salon")).payableBalance, 40);

  const report = await loaded.backend.reconcile();
  assert.equal(report.status, "balanced", JSON.stringify(report));
});

test("points stay usable when booking applies an automatic journey offer", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async (t) => {
  const loaded = loadBookingFunctions(t);
  const call = (name, request) => loaded.functions[name].run(request);
  const f = await bookingFixture(
    {...loaded, functions: call},
    8,
    ["journey-salon"],
  );
  await f.set("discountCampaigns/journey-30", {
    active: true,
    name: "Journey",
    fundingSource: "salon_promotion_credits",
    salonPayoutPercent: 100,
    payoutMultiplier: 1,
    totalPayoutBudget: 50000,
    maximumUsesPerCustomer: 3,
    salonIds: ["journey-salon"],
    journeyCountScope: "salon",
    journeyMilestones: [{
      bookingNumber: 1,
      rewardType: "discount",
      discountType: "percent",
      discountPercent: 30,
      maximumDiscountAmount: 50,
    }],
  });
  // Website defaults: not stackable with a discount, 25% of the bill.
  await f.program("test_customer_points", {
    walletType: "customer_rewards",
    rewardAmountProin: 100,
    maximumProinPerBooking: 100,
  });
  await loaded.backend.grantAsAdmin({
    adminUid: "admin-1",
    reason: "Grant booking test points",
    data: {
      programId: "test_customer_points",
      walletType: "customer_rewards",
      accountId: "customer-8",
      idempotencyKey: "booking-test:points-8",
    },
  });
  // No offer chosen: booking will apply the journey, so the quote must
  // already account for it instead of promising points booking refuses.
  const quote = await call("getProinBookingQuote", {
    auth: {uid: "customer-8"},
    data: {salonId: "journey-salon", serviceIds: ["cut"]},
  });
  assert.equal(quote.discountAmount, 30);
  assert.equal(quote.allocatedProin, 0);
  const bookingId = await f.book("journey-salon", {
    requestedProin: quote.allocatedProin,
  });
  const booking = await f.read(`bookings/${bookingId}`);
  assert.equal(booking.discountAmount, 30);
  assert.equal(booking.customerPayableAmount, 70);
});
