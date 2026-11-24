const test = require('node:test');
const assert = require('node:assert/strict');

test('Shop save is owner-only, requires photo and barber, stays editable and saves atomically', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async (t) => {
  process.env.GCLOUD_PROJECT = 'demo-salonfe-shop';
  process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-salonfe-shop'});
  const admin = require('firebase-admin');
  const functions = require('./index');
  const firestore = admin.firestore();
  const realAuth = Object.getOwnPropertyDescriptor(admin, 'auth');
  Object.defineProperty(admin, 'auth', {configurable: true, value: () => ({
    getUserByPhoneNumber: async () => { const error = new Error('missing'); error.code = 'auth/user-not-found'; throw error; },
  })});
  t.after(() => { if (realAuth) Object.defineProperty(admin, 'auth', realAuth); else delete admin.auth; });
  const ownerUid = 'shop-owner';
  const salonId = `salon-${ownerUid}`;
  await firestore.doc(`users/${ownerUid}`).set({role: 'owner', activeRole: 'owner'});
  await firestore.doc('users/customer').set({role: 'customer', activeRole: 'customer'});
  const data = {salonId, name: 'Style Studio', ownerName: 'Owner', address: 'Nashik',
    phone: '+919000000991', openTime: '9:00 AM', closeTime: '8:00 PM',
    photoUrls: ['https://example.com/shop.jpg'], initialBarbers: [{id: 'shop-barber', name: 'Sam'}]};
  const save = (patch = {}, uid = ownerUid) => functions.saveOwnerSalonShop.run({auth: {uid}, data: {...data, ...patch}});
  await assert.rejects(save({}, 'customer'), (error) => error.code === 'permission-denied');
  await assert.rejects(functions.saveOwnerSalonShop.run({data}), (error) => error.code === 'unauthenticated');
  await assert.rejects(save({photoUrls: []}), (error) => error.code === 'failed-precondition');
  await assert.rejects(save({initialBarbers: []}), (error) => error.code === 'failed-precondition');
  assert.equal((await firestore.doc(`salons/${salonId}`).get()).exists, false);
  await assert.rejects(save({closedWeekdays: [0]}), (error) => error.code === 'invalid-argument');
  await save({closedWeekdays: [1, 7]});
  assert.equal((await firestore.doc(`salons/${salonId}`).get()).data().email, '');
  assert.equal((await firestore.doc('barbers/shop-barber').get()).data().name, 'Sam');
  await firestore.doc(`salons/${salonId}`).update({approvalStatus: 'approved', email: 'existing@example.com'});
  await save({name: 'Updated Studio', initialBarbers: []});
  let salon = (await firestore.doc(`salons/${salonId}`).get()).data();
  assert.equal(salon.name, 'Updated Studio');
  assert.equal(salon.approvalStatus, 'approved');
  assert.equal(salon.email, 'existing@example.com');
  assert.deepEqual(salon.closedWeekdays, [1, 7]);
  await save({name: 'Updated Studio', closedWeekdays: []});
  assert.deepEqual((await firestore.doc(`salons/${salonId}`).get()).data().closedWeekdays, []);
  await assert.rejects(save({photoUrls: []}), (error) => error.code === 'failed-precondition');
  await firestore.doc('barbers/foreign-barber').set({salonId: 'other', ownerUid: 'other', name: 'Other'});
  await assert.rejects(save({name: 'Must not save', initialBarbers: [{id: 'foreign-barber', name: 'Stolen'}]}),
    (error) => error.code === 'permission-denied');
  salon = (await firestore.doc(`salons/${salonId}`).get()).data();
  assert.equal(salon.name, 'Updated Studio');
  await firestore.doc('barbers/shop-barber').update({isActive: false});
  await assert.rejects(save({initialBarbers: []}), (error) => error.code === 'failed-precondition');
  await assert.rejects(save(), (error) => error.code === 'failed-precondition');
  const lots = Array.from({length: 501}, (_, i) => ({id: `deposit-${String(i).padStart(3, '0')}`,
    data: {accountId: salonId, walletType: 'salon_promotion_credits', salonDeposit: true, originalProin: 10}}));
  for (let start = 0; start < lots.length; start += 400) {
    const batch = firestore.batch();
    lots.slice(start, start + 400).forEach((lot) => batch.set(firestore.doc(`proinLots/${lot.id}`), lot.data));
    await batch.commit();
  }
  await firestore.doc('bookings/completed').set({salonId, status: 'completed', discountAmount: 10, pritzePayoutAmount: 20});
  const summary = await functions.getSalonBalanceSummary.run({auth: {uid: ownerUid}, data: {salonId}});
  assert.deepEqual(summary, {deposit: 5010, discount: 10, earning: 10, balance: 4990});
  await assert.rejects(functions.getSalonBalanceSummary.run({auth: {uid: 'customer'}, data: {salonId}}),
    (error) => error.code === 'permission-denied');
});
