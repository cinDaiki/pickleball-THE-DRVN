import test from 'node:test';import assert from 'node:assert/strict';import {money,reference,imageType,csv,hash,tokenFor,effectiveStatus,uuid} from '../supabase/functions/drvn-api/core.mjs';
test('money rejects fractional cents, overflow and negatives',()=>{for(const v of [-1,1.2,Infinity,100000001])assert.throws(()=>money(v));assert.equal(money(15000),15000);});
test('GCash references normalize spacing without accepting letters',()=>{assert.equal(reference('1234 5678-9012'),'123456789012');assert.throws(()=>reference('123ABC456789'));});
test('image content must match an image signature',()=>{assert.throws(()=>imageType(new TextEncoder().encode('<svg onload="attack()">')));assert.equal(imageType(Uint8Array.from([255,216,255,...Array(10).fill(0)]))[0],'image/jpeg');});
test('status tokens are stable, secret-dependent and stored only as hashes',async()=>{const a=await tokenFor('entry','secret-a');assert.equal(a.length,64);assert.equal(a,await tokenFor('entry','secret-a'));assert.notEqual(a,await tokenFor('entry','secret-b'));assert.notEqual(a,await hash(a));});
test('expiration releases unpaid reservations without expiring proof under review',()=>{assert.equal(effectiveStatus({status:'awaiting_payment',expires_at:'2020-01-01'}),'expired');assert.equal(effectiveStatus({status:'under_review',expires_at:'2020-01-01'}),'under_review');});
test('CSV neutralizes spreadsheet formulas and quotes',()=>{assert.equal(csv([['=CMD()', 'a"b']]),'"\'=CMD()","a""b"');});
test('invalid record identifiers rejected',()=>{assert.throws(()=>uuid('anything&select=*'));assert.equal(uuid('bd887e45-5766-414d-a39d-1d9c31d90bde'),'bd887e45-5766-414d-a39d-1d9c31d90bde');});

test('event validation rejects invalid schedules and categories',async()=>{
 const {validateEvent}=await import('../supabase/functions/drvn-api/core.mjs');
 const event={title:'Davao Open',venue:'Main court',status:'draft',opens_at:'2026-11-01T00:00:00Z',closes_at:'2026-11-02T00:00:00Z',starts_at:'2026-11-03T00:00:00Z'};
 const cats=[{name:'Open',unit:'individual',fee_cents:15000,capacity:16}];
 assert.doesNotThrow(()=>validateEvent(event,cats));
 assert.throws(()=>validateEvent({...event,closes_at:event.opens_at},cats),/closing/);
 assert.throws(()=>validateEvent({...event,starts_at:event.opens_at},cats),/close before/);
 assert.throws(()=>validateEvent(event,[{...cats[0],capacity:0}]),/capacity/);
 assert.throws(()=>validateEvent(event,[...cats,{...cats[0],name:'OPEN'}]),/unique/);
 assert.throws(()=>validateEvent(event,[{...cats[0],fee_cents:1.5}]),/amount/);
});
test('paging validates identifiers and bounds',async()=>{
 const {listOptions}=await import('../supabase/functions/drvn-api/core.mjs');
 assert.equal(listOptions({page:2,query:'  Ann '}).p_query,'Ann');
 assert.throws(()=>listOptions({page:-1}),/page/);
 assert.throws(()=>listOptions({event:'abc'}),/identifier/);
 assert.throws(()=>listOptions({query:'x'.repeat(151)}),/150/);
});
