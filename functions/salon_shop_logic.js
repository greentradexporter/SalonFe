// Deposit accounting is independent of the promotional wallet's credit line,
// reservations, customer Proin redemptions and complimentary grants.
function nonnegativeMoney(value) {
  const number = Number(value);
  return Number.isSafeInteger(number) && number > 0 ? number : 0;
}
function salonBalanceSummary(lots, bookings) {
  const deposit = lots.filter((lot) => lot.walletType === 'salon_promotion_credits' && lot.salonDeposit === true)
    .reduce((sum, lot) => sum + nonnegativeMoney(lot.originalProin), 0);
  let discount = 0;
  let earning = 0;
  for (const booking of bookings) {
    if (booking.status !== 'completed') continue;
    const bookingDiscount = nonnegativeMoney(booking.discountAmount);
    discount += bookingDiscount;
    // The payout includes reimbursement of the discount. Deduct that support
    // once, under Discount; only the remainder is the owner's extra earning.
    earning += Math.max(0, nonnegativeMoney(booking.pritzePayoutAmount) - bookingDiscount);
  }
  return {deposit, discount, earning, balance: deposit - discount - earning};
}
function hasNamedBarber(barbers) {
  return barbers.some((barber) => barber.isActive !== false && String(barber.name || '').trim().length > 0);
}
module.exports = {salonBalanceSummary, hasNamedBarber};
