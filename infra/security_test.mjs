// Request-boundary and tenant-isolation regression checks; no cloud access.
// Run: node infra/security_test.mjs
import assert from "node:assert/strict";
import {dataCrypto,networkOf} from "./data_crypto.js";
import sync from "./sync/worker.js";
import circles from "./circles/worker.js";
import { d1, keyOf } from "./circles/dev/d1.mjs";

const auth = { Authorization: `Bearer ${keyOf("alice")}` };
const noDB = {
  prepare() { assert.fail("Rejected requests must not prepare D1 statements"); },
  batch() { assert.fail("Rejected requests must not query D1"); },
};
const allow = { async limit() { return { success: true }; } };
const deny = { async limit() { return { success: false }; } };

function request(path, { method = "GET", body, headers = auth, production = false } = {}) {
  const req = new Request(`https://example.test${path}`, { method, headers, body });
  if (production) Object.defineProperty(req, "cf", { value: {} });
  return req;
}

async function rejects(worker, req, status, bindings = {}) {
  const response = await worker.fetch(req, { DB: noDB, ...bindings });
  assert.equal(response.status, status);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  if (status === 429) assert.equal(response.headers.get("Retry-After"), "60");
}

await rejects(sync, request("/v1/pull", { headers: {} }), 401);
await rejects(sync, request("/v1/pull", { headers: { Authorization: keyOf("alice") } }), 401);
await rejects(sync, request("/v1/pull/trailing"), 404);
await rejects(sync, request("/v1/pull", { method: "POST" }), 404);
await rejects(sync, request("/v1/pull?cursor=-1"), 400);
await rejects(sync, request("/v1/pull?cursor=9007199254740992"), 400);
await rejects(sync, request("/v1/pull?cursor=NaN"), 400);
for (const body of [undefined, "{", "null", "[]", '"string"']) {
  await rejects(sync, request("/v1/push", { method: "POST", body }), 400);
}
// The stream size, rather than a trusted Content-Length, enforces the cap.
const oversized = request("/v1/push", {
  method: "POST", body: JSON.stringify({ changes: [], padding: "x".repeat(8 * 1024 * 1024) }),
});
assert.equal(oversized.headers.get("Content-Length"), null);
await rejects(sync, oversized, 413);
for (const [worker, path, names] of [
  [sync, "/v1/pull", ["REQUEST_RATE", "NETWORK_RATE", "SAFETY_RATE"]],
  [circles, "/v1/me", ["REQUEST_RATE", "NETWORK_RATE", "INVITE_RATE", "SAFETY_RATE"]],
]) {
  for (const missing of names) {
    const bindings = Object.fromEntries(names.filter((name) => name !== missing).map((name) => [name, allow]));
    await rejects(worker, request(path, { production: true }), 503, bindings);
  }
  for (const name of ["REQUEST_RATE", "NETWORK_RATE"]) {
    await rejects(worker, request(path), 429, { [name]: deny });
  }
}
await rejects(circles, request("/v1/code/AAAAAAAA"), 429, { INVITE_RATE: deny });
await rejects(circles, request("/v1/join", { method: "POST", body: '{"code":"AAAAAAAA"}' }), 429, { INVITE_RATE: deny });

const DATA_KEY = "00".repeat(32);
const DB = d1();
async function call(who, method, path, body) {
  const response = await sync.fetch(request(path, {
    method, body: body === undefined ? undefined : JSON.stringify(body),
    headers: { Authorization: `Bearer ${keyOf(who)}`, "CF-Connecting-IP": "192.0.2.1" },
  }), { DB, DATA_KEY, REQUEST_RATE: allow, NETWORK_RATE: allow });
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}
const change = {
  t: "cabinets", k: "Private venue/Cabinet 1", u: "2026-01-01T00:00:00Z",
  d: { name: "Cabinet 1", venueId: "Private venue" },
};
assert.equal((await call("alice", "POST", "/v1/push", { changes: [change] })).status, 200);
const alice = await call("alice", "GET", "/v1/pull");
assert.deepEqual(alice.body.changes, [change]);
assert.equal(alice.body.head, 1);
assert.deepEqual((await call("mallory", "GET", "/v1/pull?owner=alice&t=cabinets")).body.changes, []);
await call("mallory", "DELETE", "/v1/me");
assert.deepEqual((await call("alice", "GET", "/v1/pull")).body.changes, [change]);
// Names and SQL-shaped row keys stay bound values in the authenticated owner.
const sqlKey = { ...change, k: "' OR 1=1; --" };
await call("mallory", "POST", "/v1/push", { changes: [sqlKey], owner: "alice" });
assert.deepEqual((await call("alice", "GET", "/v1/pull")).body.changes, [change]);
assert.equal((await call("mallory", "POST", "/v1/push", { changes: [null] })).status, 400);
const older = await call("alice", "POST", "/v1/push", { changes: [{ ...change, u: "2025-01-01", d: { name: "older" } }] });
assert.deepEqual(older.body.lost, [0]);
assert.deepEqual((await call("alice", "GET", "/v1/pull")).body.changes, [change]);
await call("alice", "POST", "/v1/push", { changes: [{ ...change, u: "2026-02-01", d: null }] });
assert.equal((await call("alice", "GET", "/v1/pull")).body.changes[0].d, null);
assert.equal((await call("alice", "DELETE", "/v1/me")).status, 204);
assert.deepEqual((await call("alice", "GET", "/v1/pull")).body.changes, []);

const circleDB = d1();
async function circle(who, method, path, body) {
  const response = await circles.fetch(request(path, {
    method, body: body === undefined ? undefined : JSON.stringify(body),
    headers: { Authorization: `Bearer ${keyOf(who)}` },
  }), { DB: circleDB, DATA_KEY });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}
await circle("alice", "PUT", "/v1/me", { name: "ALICE", ddrCode: "12345678" });
const mallory = await circle("mallory", "PUT", "/v1/me", { name: "MALLORY", ddrCode: "87654321" });
const invite = (await circle("alice", "POST", "/v1/code")).body.code;
await circle("alice", "PUT", "/v1/live", { venue: "Private venue", credit: 1, side: "1P" });
assert.deepEqual((await circle("mallory", "GET", "/v1/me")).body.following, []);
assert.equal((await circle("mallory", "GET", `/v1/code/${invite}`)).body.person.live, undefined);
assert.equal((await circle("mallory", "GET", `/v1/live?owner=alice`)).status, 404);
await circle("mallory", "POST", "/v1/join", { code: invite });
assert.equal((await circle("mallory", "GET", "/v1/me")).body.following[0].live.venue, "Private venue");
await circle("alice", "DELETE", `/v1/circle/${mallory.body.id}`);
assert.deepEqual((await circle("mallory", "GET", "/v1/me")).body.following, []);
// Data-at-rest encryption hides identifiers and payloads, including tombstones.
await call("encrypted", "POST", "/v1/push", {ddrCode:"12345678",changes:[change]});
const raw = (await DB.prepare("SELECT k,d FROM rows WHERE t='cabinets'").all()).results;
assert.ok(raw.every(r => r.k.startsWith("~1:") && r.d.startsWith("sealed1:")));
assert.ok(!JSON.stringify(raw).includes("Private venue"));
assert.ok((await DB.prepare("SELECT ddrCode FROM users WHERE ddrCode IS NOT NULL").first()).ddrCode.startsWith("sealed1:"));
// Empty uploads neither create users nor spend mutation capacity.
const before=(await DB.prepare("SELECT count(*) AS n FROM users").first()).n;
await call("empty", "POST", "/v1/push", {changes:[]});
assert.equal((await DB.prepare("SELECT count(*) AS n FROM users").first()).n,before);
// Both concurrent requests hit the same nearly-spent allowance. Exactly one
// commits; rejected transactions roll back revisions, rows and global telemetry.
const day=new Date().toISOString().slice(0,10);
await DB.prepare("UPDATE users SET day=?,dayRows=19999 WHERE ddrCode IS NOT NULL").bind(day).run();
const concurrent=await Promise.all([
 call("encrypted","POST","/v1/push",{changes:[{...change,k:"One"}]}),
 call("encrypted","POST","/v1/push",{changes:[{...change,k:"Two"}]})
]);
assert.deepEqual(concurrent.map(r=>r.status).sort(),[200,429]);
assert.equal((await DB.prepare("SELECT dayRows FROM users WHERE ddrCode IS NOT NULL").first()).dayRows,20000);
// A spent mutation allowance never prevents revoking location or deleting data.
await circle("alice","PUT","/v1/live",{venue:"Private venue",credit:1,side:"1P"});
const owner=(await circleDB.prepare("SELECT owner FROM profiles WHERE name='ALICE'").first()).owner;
await circleDB.prepare("INSERT INTO usage(day,owner,mutations) VALUES (?,?,600) ON CONFLICT(day,owner) DO UPDATE SET mutations=600").bind(day,owner).run();
assert.equal((await circle("alice","POST","/v1/code")).status,429);
assert.equal((await circle("alice","DELETE","/v1/live")).status,204);
assert.equal((await circle("alice","DELETE","/v1/me")).status,204);
// Removal revokes the old code and the same member remains blocked after rotation.
const rotated=(await circle("mallory","POST","/v1/code")).body.code;
await circle("guest","PUT","/v1/me",{name:"GUEST",ddrCode:"55556666"});
await circle("guest","POST","/v1/join",{code:rotated});
const guest=(await circle("guest","GET","/v1/me")).body.id;
await circle("mallory","DELETE",`/v1/circle/${guest}`);
assert.equal((await circle("guest","POST","/v1/join",{code:rotated})).status,404);
const nextCode=(await circle("mallory","POST","/v1/code")).body.code;
assert.equal((await circle("guest","POST","/v1/join",{code:nextCode})).status,409);
await circle("guest","DELETE","/v1/me");
await circle("guest","PUT","/v1/me",{name:"GUEST",ddrCode:"55556666"});
assert.equal((await circle("guest","POST","/v1/join",{code:nextCode})).status,409);
// Scheduled cleanup does not require the inactive player to post again.
await circle("mallory","PUT","/v1/live",{venue:"Private arcade",credit:1,side:"1P"});
await circleDB.prepare("UPDATE live SET until='2000-01-01'").run();
await circles.scheduled({}, {DB:circleDB,DATA_KEY});
assert.equal((await circleDB.prepare("SELECT count(*) AS n FROM live").first()).n,0);
// A legacy database migrates in-place without changing cursor or API data.
await DB.prepare("INSERT INTO rows(owner,t,k,u,d,rev) SELECT owner,'venues','Legacy venue','2026-01-01','{\"name\":\"Legacy venue\"}',999 FROM users LIMIT 1").run();
await sync.scheduled({}, {DB,DATA_KEY});
assert.equal((await DB.prepare("SELECT count(*) AS n FROM rows WHERE k='Legacy venue'").first()).n,0);
assert.equal((await DB.prepare("SELECT rev FROM rows WHERE rev=999").first()).rev,999);
// Enrollment exhaustion is isolated from existing users, with no orphan rows.
await DB.prepare("UPDATE admissions SET accounts=200").run();
const usersBefore=(await DB.prepare("SELECT count(*) AS n FROM users").first()).n;
assert.equal((await call("new-blocked","POST","/v1/push",{changes:[change]})).status,429);
assert.equal((await DB.prepare("SELECT count(*) AS n FROM users").first()).n,usersBefore);
assert.equal((await call("mallory","POST","/v1/push",{changes:[{...change,k:"Existing user"}]})).status,200);
await circleDB.prepare("UPDATE admissions SET accounts=200").run();
const usageBefore=(await circleDB.prepare("SELECT count(*) AS n FROM usage").first()).n;
assert.equal((await circle("new-blocked","PUT","/v1/me",{name:"NEW",ddrCode:"11112222"})).status,429);
assert.equal((await circleDB.prepare("SELECT count(*) AS n FROM usage").first()).n,usageBefore);
assert.equal((await circle("mallory","POST","/v1/code")).status,200);
// Private field authentication binds the ciphertext to its owning record.
const vault=await dataCrypto(DATA_KEY);
const ciphertext=await vault.seal("Private venue 界","owner/table/key");
assert.equal(await vault.open(ciphertext,"owner/table/key"),"Private venue 界");
await assert.rejects(vault.open(ciphertext,"different-owner/table/key"));
assert.equal(networkOf("2001:db8:1234:5678::1"),networkOf("2001:0db8:1234:5678:abcd::9"));
assert.notEqual(networkOf("2001:db8:1234:5678::1"),networkOf("2001:db8:1234:5679::1"));
// Maintenance must use the partial indexes rather than scan every backup.
const plan=await DB.prepare("EXPLAIN QUERY PLAN SELECT owner,t,k,u,d,rev FROM rows WHERE d IS NULL OR substr(d,1,8) != 'sealed1:' LIMIT 100").all();
assert.ok(plan.results.some(row=>row.detail.includes("rows_legacy")));
console.log("security regression checks: all passed");
