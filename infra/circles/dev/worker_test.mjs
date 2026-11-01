// The circles Worker end to end on an in-memory database:
//
//   node infra/circles/dev/worker_test.mjs
import assert from "node:assert/strict";
import worker from "../worker.js";
import { d1, keyOf } from "./d1.mjs";

const DB = d1();
async function call(who, method, path, body) {
  const res = await worker.fetch(
    new Request(`https://x${path}`, {
      method,
      headers: { Authorization: `Bearer ${keyOf(who)}`, "content-type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    }),
    { DB },
  );
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

let r = await call("a", "GET", "/v1/me");
assert.equal(r.body.id, null);
assert.equal((await call("a", "POST", "/v1/code", {})).status, 403);
assert.equal((await call("a", "PUT", "/v1/me", { name: "TOO LONG NAME", ddrCode: "12345678" })).status, 400);
assert.equal((await call("a", "PUT", "/v1/me", { name: "SHIGGY", ddrCode: "1234" })).status, 400);
r = await call("a", "PUT", "/v1/me", { name: "shiggy", ddrCode: "1234-5678" });
assert.equal(r.body.name, "SHIGGY");
assert.equal(r.body.ddrCode, "12345678");
const a = r.body.id;
// A DDR-CODE can be given twice; people are told apart by id.
r = await call("b", "PUT", "/v1/me", { name: "MIKA", ddrCode: "12345678" });
const b = r.body.id;
assert.notEqual(a, b);

r = await call("a", "POST", "/v1/code");
assert.ok(Date.parse(r.body.codeUntil) - Date.now() <= 86400000);
const code = r.body.code;
assert.match(code, /^[A-HJ-NP-Z2-9]{8}$/);
r = await call("b", "GET", `/v1/code/${code.slice(0, 4)}-${code.slice(4).toLowerCase()}`);
assert.deepEqual(r.body, {
  person: { id: a, name: "SHIGGY", ddrCode: "12345678", friend: false },
  members: 0,
  friends: 0,
});
assert.equal((await call("a", "GET", `/v1/code/${code}`)).status, 404);

r = await call("b", "POST", "/v1/join", { code });
assert.deepEqual(r.body, { name: "SHIGGY" });
assert.equal((await call("b", "GET", "/v1/me")).body.following.length, 1);
r = await call("a", "GET", "/v1/me");
assert.deepEqual(r.body.circle, [{ id: b, name: "MIKA", ddrCode: "12345678", friend: false }]);

const code2 = (await call("b", "POST", "/v1/code")).body.code;
assert.equal((await call("a", "POST", "/v1/join", { code: code2 })).body.name, "MIKA");
r = await call("a", "GET", "/v1/me");
assert.equal(r.body.following[0].friend, true);
assert.equal(r.body.circle[0].friend, true);
assert.equal((await call("b", "GET", `/v1/code/${code}`)).body.friends, 1);

r = await call("b", "DELETE", `/v1/following/${a}`);
assert.equal(r.body.following.length, 0);
r = await call("a", "GET", "/v1/me");
assert.equal(r.body.circle.length, 0);
assert.equal(r.body.following[0].friend, false);

// Taken out, they can come back in with a live code.
assert.equal((await call("b", "POST", "/v1/join", { code })).status, 200);
r = await call("a", "DELETE", `/v1/circle/${b}`);
assert.equal(r.body.circle.length, 0);

// One scan, both ways: joining with back lets the leader into yours too.
await call("d", "PUT", "/v1/me", { name: "SABLE", ddrCode: "28816640" });
await call("d", "POST", "/v1/join", { code, back: true });
r = await call("d", "GET", "/v1/me");
assert.equal(r.body.following.find((p) => p.name === "SHIGGY").friend, true);
assert.equal(r.body.circle.find((p) => p.name === "SHIGGY").friend, true);

// A broadcast shows on its player to their circle until it ends.
await call("b", "POST", "/v1/join", { code });
assert.equal((await call("a", "PUT", "/v1/live", { venue: "Round1", credit: 0, side: "1P" })).status, 400);
assert.equal((await call("a", "PUT", "/v1/live", { venue: "Round1", credit: 2, side: "2P" })).status, 204);
r = await call("b", "GET", "/v1/me");
assert.deepEqual({ ...r.body.following[0].live, at: null }, { venue: "Round1", credit: 2, side: "2P", at: null });
assert.equal((await call("a", "DELETE", "/v1/live")).status, 204);
assert.equal((await call("b", "GET", "/v1/me")).body.following[0].live, undefined);

// A credit shows to its circle, who can cheer it once each; the poster sees
// the cheers on their own.
const play = { song: "MAX 300", mode: "singles", difficulty: "EXPERT", score: 912540, failed: false, best: true };
assert.equal((await call("a", "PUT", "/v1/credit", { session: "s-1", credit: 1, plays: [] })).status, 400);
assert.equal((await call("a", "PUT", "/v1/credit", { session: "s-1", credit: 1, plays: [{ ...play, mode: "x" }] })).status, 400);
assert.equal((await call("a", "PUT", "/v1/credit", { session: "s-1", credit: 1, plays: [play] })).status, 204);
r = await call("b", "GET", "/v1/feed");
assert.equal(r.body.credits.length, 1);
assert.deepEqual(r.body.credits[0].plays, [play]);
assert.equal(r.body.credits[0].mine, null);
const target = { by: a, session: "s-1", credit: 1 };
await call("c", "PUT", "/v1/me", { name: "GUESSER", ddrCode: "11112222" });
assert.equal((await call("b", "PUT", "/v1/cheer", { ...target, preset: "shout" })).status, 400);
assert.equal((await call("c", "PUT", "/v1/cheer", { ...target, preset: "clean" })).status, 404);
assert.equal((await call("b", "PUT", "/v1/cheer", { ...target, credit: 2, preset: "clean" })).status, 404);
assert.equal((await call("b", "PUT", "/v1/cheer", { ...target, preset: "clean" })).status, 204);
assert.equal((await call("b", "PUT", "/v1/cheer", { ...target, preset: "legend" })).status, 204);
assert.equal((await call("b", "GET", "/v1/feed")).body.credits[0].mine, "legend");
r = await call("a", "GET", "/v1/feed");
assert.deepEqual(r.body.yours[0].cheers, [{ name: "MIKA", preset: "legend" }]);
assert.equal((await call("b", "PUT", "/v1/cheer", { ...target, preset: null })).status, 204);
assert.equal((await call("a", "GET", "/v1/feed")).body.yours[0].cheers.length, 0);
// Someone outside the circle sees none of it.
assert.equal((await call("c", "GET", "/v1/feed")).body.credits.length, 0);

for (let i = 0; i < 30; i++) await call("c", "GET", "/v1/code/AAAAAAAA");
assert.equal((await call("c", "GET", `/v1/code/${code}`)).status, 429);

assert.equal((await call("a", "DELETE", "/v1/me")).status, 204);
assert.equal((await call("a", "GET", "/v1/me")).body.id, null);
assert.equal((await call("a", "GET", "/nope")).status, 404);
assert.equal((await worker.fetch(new Request("https://x/v1/me"), { DB })).status, 401);
console.log("circles worker: all checks passed");
