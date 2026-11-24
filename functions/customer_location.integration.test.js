const test=require('node:test');
const fs=require('node:fs');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,updateDoc,getDoc,deleteField,serverTimestamp}=require('firebase/firestore');
test('discovery location remains private and only the customer can save or clear it', {skip:!process.env.FIRESTORE_EMULATOR_HOST}, async()=>{
 const env=await initializeTestEnvironment({projectId:'demo-salonfe-location',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});
 try {
  await env.withSecurityRulesDisabled(async c=>{for(const [id,role] of [['customer','customer'],['owner','owner']]) await setDoc(doc(c.firestore(),'users',id),{role,activeRole:role});});
  const customer=env.authenticatedContext('customer').firestore(), owner=env.authenticatedContext('owner').firestore();
  const ref=doc(customer,'users','customer');
  const location={latitude:19.999,longitude:73.789,accuracyMeters:100,purpose:'salon_discovery',capturedAt:serverTimestamp()};
  await assertSucceeds(updateDoc(ref,{customerLocation:location}));
  await assertFails(getDoc(doc(owner,'users','customer')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'users','customer')));
  await assertFails(updateDoc(doc(owner,'users','owner'),{customerLocation:location}));
  await assertFails(updateDoc(ref,{customerLocation:{...location,latitude:999}}));
  await assertFails(updateDoc(ref,{customerLocation:{...location,accuracyMeters:1}}));
  await assertFails(updateDoc(ref,{customerLocation:{...location,capturedAt:new Date('2000-01-01')}}));
  await assertSucceeds(updateDoc(ref,{customerLocation:deleteField()}));
 }finally{await env.cleanup();}
});
