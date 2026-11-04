// Run with node infra/circles/dev/showcase_test.mjs.
import assert from 'node:assert/strict';
import worker from '../worker.js';
import {dataCrypto} from '../../data_crypto.js';
import {d1, keyOf} from './d1.mjs';
const DB=d1(), DATA_KEY='00'.repeat(32);
async function call(who,method,path,body) {
  const res=await worker.fetch(new Request(`https://x/v1/${path}`,{
    method,headers:{Authorization:`Bearer ${keyOf(who)}`,'Content-Type':'application/json'},
    body:body === undefined ? undefined : JSON.stringify(body),
  }),{DB,DATA_KEY});
  return {status:res.status,body:res.status===204 ? null : await res.json()};
}
const a=(await call('a','PUT','me',{name:'A',ddrCode:'12345678'})).body.id;
const b=(await call('b','PUT','me',{name:'B',ddrCode:'87654321'})).body.id;
await call('c','PUT','me',{name:'C',ddrCode:'11111111'});
const code=(await call('a','POST','code')).body.code;
await call('b','POST','join',{code});
const card={id:'chart-a',song:'MAX 300',mode:'singles',difficulty:'EXPERT',score:988410,
  grade:'AA+',lamp:'gfc',flare:'IX',playedAt:'2026-10-20T00:00:00Z'};
const read=who=>call(who,'GET',`showcase/${a}`);
assert.deepEqual((await read('a')).body.cards,[null,null,null]);
assert.equal((await read('c')).status,404);
await call('b','PUT','showcase',{cards:[card,null,null]});
assert.equal((await read('a')).body.cards[0],null);
await call('a','PUT','showcase',{cards:[{...card,caption:'Legacy subtitle',cheers:4,cheered:true},null,null]});
assert.deepEqual((await read('b')).body.cards[0],card);
const stored=await DB.prepare('SELECT owner,cards FROM showcases WHERE owner=(SELECT owner FROM profiles WHERE id=?)').bind(a).first();
assert.ok(stored.cards.startsWith('sealed1:'));
const vault=await dataCrypto(DATA_KEY);
assert.ok(!(await vault.open(stored.cards,`showcase:${stored.owner}`)).includes('Legacy subtitle'));
// Old stored snapshots must not leak removed fields either.
await DB.prepare('UPDATE showcases SET cards=? WHERE owner=?').bind(
  await vault.seal(JSON.stringify([{...card,caption:'Old saved caption',cheers:5},null,null]),`showcase:${stored.owner}`),stored.owner).run();
assert.deepEqual((await read('b')).body.cards[0],card);
for (const cards of [[card],[card,card,null],[card,{...card,id:'different'},null],
  [{...card,score:1000001},null,null],[{...card,mode:'invalid'},null,null],
  [{...card,grade:'BOGUS'},null,null],[{...card,playedAt:'invalid'},null,null]]) {
  assert.equal((await call('a','PUT','showcase',{cards})).status,400);
}
assert.equal((await call('b','PUT','showcase-cheer',{by:a,card:card.id,cheered:true})).status,404);
await call('a','PUT','showcase',{cards:[null,card,null]});
assert.deepEqual((await read('b')).body.cards,[null,card,null]);
await call('a','DELETE',`circle/${b}`);
assert.equal((await read('b')).status,404);
await call('a','PUT','showcase',{cards:[null,null,null]});
assert.deepEqual((await read('a')).body.cards,[null,null,null]);
await call('a','DELETE','me');
assert.equal((await DB.prepare('SELECT count(*) AS n FROM showcases WHERE owner NOT IN (SELECT owner FROM profiles)').first()).n,0);
console.log('Showcase API: card-only snapshots, encryption, validation, revocation and deletion passed');
