const test = require('node:test');
const assert = require('node:assert/strict');
const {salonBalanceSummary, hasNamedBarber} = require('./salon_shop_logic');
const lot = {walletType: 'salon_promotion_credits', salonDeposit: true, originalProin: 1000};
test('balance deducts discount support once and extra earning separately', () => {
  assert.deepEqual(salonBalanceSummary([lot], [{status: 'completed', discountAmount: 10, pritzePayoutAmount: 20}]),
    {deposit: 1000, discount: 10, earning: 10, balance: 980});
});
test('only deposit lots count; customer rewards, grants and pending/cancelled visits do not', () => {
  assert.deepEqual(salonBalanceSummary([lot, {...lot, salonDeposit: false}, {...lot, walletType: 'customer_rewards'}],
    ['confirmed', 'inProgress', 'cancelled', 'rejected'].map((status) => ({status, discountAmount: 200, pritzePayoutAmount: 400}))),
    {deposit: 1000, discount: 0, earning: 0, balance: 1000});
});
test('multiple deposits, no discount incentives, negative balances and Proin redemption', () => {
  assert.deepEqual(salonBalanceSummary([lot, {...lot, originalProin: 500}], [
    {status: 'completed', discountAmount: 1000, pritzePayoutAmount: 2000, proinRedeemedAmount: 90},
    {status: 'completed', discountAmount: 0, pritzePayoutAmount: 100},
  ]), {deposit: 1500, discount: 1000, earning: 1100, balance: -600});
});
test('malformed legacy numbers cannot create false money or negative earnings', () => {
  assert.deepEqual(salonBalanceSummary([{...lot, originalProin: 'bad'}], [
    {status: 'completed', discountAmount: 50, pritzePayoutAmount: 0},
    {status: 'completed', discountAmount: -10, pritzePayoutAmount: 'bad'},
  ]), {deposit: 0, discount: 50, earning: 0, balance: -50});
});
test('shop requires an active named barber', () => {
  assert.equal(hasNamedBarber([]), false);
  assert.equal(hasNamedBarber([{name: '  '}, {name: 'Sam', isActive: false}]), false);
  assert.equal(hasNamedBarber([{name: 'Sam', isActive: true}]), true);
});
