// Run with node infra/circles/dev/tiers_test.mjs.
import assert from 'node:assert/strict';
import worker from '../worker.js';
import {d1, keyOf} from './d1.mjs';
const DB=d1(), DATA_KEY='00'.repeat(32);
async function call(who,method,path,body) {
  const res=await worker.fetch(new Request(`https://x/v1/${path}`,{
    method,headers:{Authorization:`Bearer ${keyOf(who)}`,'Content-Type':'application/json'},
    body:body === undefined ? undefined : JSON.stringify(body),
  }),{DB,DATA_KEY});
  return {status:res.status,body:res.status===204 ? null : await res.json()};
}
await call('a','PUT','me',{name:'A',ddrCode:'12345678'});
const b=(await call('b','PUT','me',{name:'B',ddrCode:'87654321'})).body.id;
await call('c','PUT','me',{name:'C',ddrCode:'11111111'});
const code=(await call('a','POST','code')).body.code;
await call('b','POST','join',{code});
const tiers=[['MAX 300','EXPERT',14,70],['Healing-D-Vision','CHALLENGE',19,90]];
assert.equal((await call('a','PUT','tiers',{tiers,post:{level:14,count:1}})).status,204);
const seen=(await call('b','GET','tiers')).body.people;
assert.equal(seen.length,1);
assert.deepEqual(seen[0].tiers,tiers);
assert.deepEqual((await call('c','GET','tiers')).body.people,[]);
assert.deepEqual((await call('b','GET','feed')).body.tiers.map(t=>[t.level,t.count]),[[14,1]]);
const stored=await DB.prepare('SELECT list FROM tiers').first();
assert.ok(stored.list.startsWith('sealed1:'));
// A whole list fits its own body limit, not the 8 KB the others get.
const many=Array.from({length:2000},(_,i)=>[`Song number ${i} with a long title`,'EXPERT',12,i%20*5]);
assert.equal((await call('a','PUT','tiers',{tiers:many})).status,204);
assert.equal((await call('b','GET','tiers')).body.people[0].tiers.length,2000);
for (const bad of [[['x','EXPERT',14,72]],[['x','EXPERT',19,95]],[['x','EXPERT',14,100]],[['x','HARD',14,70]],
  [['x','EXPERT',14,70],['x','EXPERT',14,75]],[['x','EXPERT',20,0]]]) {
  assert.equal((await call('a','PUT','tiers',{tiers:bad})).status,400);
}
await call('a','DELETE',`circle/${b}`);
assert.deepEqual((await call('b','GET','tiers')).body.people,[]);
assert.equal((await call('a','DELETE','tiers')).status,204);
assert.equal((await DB.prepare('SELECT count(*) AS n FROM tiers').first()).n,0);
await call('a','PUT','tiers',{tiers});
await call('a','DELETE','me');
assert.equal((await DB.prepare('SELECT count(*) AS n FROM tiers').first()).n,0);
console.log('Tiers API: sharing, feed posts, body limit, validation, revocation and deletion passed');
