// Run with node infra/circles/dev/showcase_test.mjs.
import assert from 'node:assert/strict';
import worker from '../worker.js';
import {d1, keyOf} from './d1.mjs';
const DB = d1();
async function call(who, method, path, body) {
  const res = await worker.fetch(new Request(`https://x/v1/${path}`, {
    method, headers: {Authorization: `Bearer ${keyOf(who)}`, 'Content-Type':'application/json'},
    body: body === undefined ? undefined : JSON.stringify(body),
  }), {DB, DATA_KEY:'00'.repeat(32)});
  return {status:res.status, body:res.status === 204 ? null : await res.json()};
}
const a = (await call('a','PUT','me',{name:'A',ddrCode:'12345678'})).body.id;
const b = (await call('b','PUT','me',{name:'B',ddrCode:'87654321'})).body.id;
await call('c','PUT','me',{name:'C',ddrCode:'11111111'});
const code = (await call('a','POST','code')).body.code;
await call('b','POST','join',{code});
const card = {id:'chart-a',song:'MAX 300',mode:'singles',difficulty:'EXPERT',score:988410,
  grade:'AA+',lamp:'gfc',flare:'IX',caption:'First clear',playedAt:'2026-10-20T00:00:00Z'};
const read = who => call(who,'GET',`showcase/${a}`);
assert.deepEqual((await read('a')).body.cards,[null,null,null]);
assert.equal((await read('c')).status,404);
assert.equal((await call('b','PUT','showcase',{cards:[card,null,null]})).status,200);
// Writing always affects your own showcase.
assert.equal((await read('a')).body.cards[0],null);
assert.equal((await call('a','PUT','showcase',{cards:[card,null,null]})).status,200);
assert.equal((await read('b')).body.cards[0].caption,'First clear');
const raw = (await DB.prepare('SELECT cards FROM showcases LIMIT 1').first()).cards;
assert.ok(raw.startsWith('sealed1:'));
assert.ok(!raw.includes('First clear'));
for (const cards of [[card], [card,card,null], [card,{...card,id:"other-id"},null], [{...card,caption:'x'.repeat(41)},null,null],
  [{...card,score:1000001},null,null], [{...card,mode:'invalid'},null,null],
  [{...card,grade:'BOGUS'},null,null], [{...card,playedAt:'invalid'},null,null]]) {
  assert.equal((await call('a','PUT','showcase',{cards})).status,400);
}
const cheer = (who,cheered=true,id=card.id) => call(who,'PUT','showcase-cheer',{by:a,card:id,cheered});
assert.equal((await cheer('a')).status,404); // no self cheers
assert.equal((await cheer('c')).status,404);
assert.equal((await cheer('b',true,'missing')).status,404);
assert.equal((await cheer('b')).body.cards[0].cheers,1);
assert.equal((await cheer('b')).body.cards[0].cheers,1); // idempotent
assert.equal((await read('b')).body.cards[0].cheered,true);
assert.equal((await read('a')).body.cards[0].cheered,false);
assert.equal((await cheer('b',false)).body.cards[0].cheers,0);
await cheer('b');
// Reordering and editing a caption retain cheers; replacing a card clears them.
await call('a','PUT','showcase',{cards:[null,{...card,caption:'Still proud'},null]});
assert.equal((await read('b')).body.cards[1].cheers,1);
await call('a','DELETE',`circle/${b}`);
assert.equal((await read('b')).status,404);
assert.equal((await cheer('b')).status,404);
assert.equal((await read('a')).body.cards[1].cheers,0);
await call('a','PUT','showcase',{cards:[null,null,null]});
assert.equal((await DB.prepare('SELECT count(*) AS n FROM showcase_cheers').first()).n,0);
await call('a','PUT','showcase',{cards:[card,null,null]});
await call('a','DELETE','me');
assert.equal((await DB.prepare('SELECT count(*) AS n FROM showcases WHERE owner NOT IN (SELECT owner FROM profiles)').first()).n,0);
console.log('Showcase API: snapshots, encryption, validation, cheers, revocation and deletion passed');
