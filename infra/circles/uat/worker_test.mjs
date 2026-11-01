// Exercise the simulator against the real Circles API on in-memory SQLite.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import circles from "../worker.js";
import worker, { actors, apiFor, tick } from "./worker.js";
import { d1 } from "../dev/d1.mjs";

const DB = d1();
const DATA_KEY = "00".repeat(32);
const originalNow = Date.now;
let now = originalNow();
Date.now = () => now;
const keys = Object.fromEntries(actors.map(({ role }) => [role, randomBytes(32).toString("base64url")]));
const personalKey = randomBytes(32).toString("base64url");
const strangerKey = randomBytes(32).toString("base64url");
let mutations = 0;
const send = async (request) => {
  if (request.method !== "GET") mutations++;
  return circles.fetch(request, { DB, DATA_KEY });
};
async function personal(method, path, body, key = personalKey) {
  const response = await send(new Request(`https://x${path}`, {
    method, headers: { Authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  }));
  assert.ok(response.ok, `${method} ${path}: ${response.status}`);
  return response.status === 204 ? null : response.json();
}

try {
  const target = await personal("PUT", "/v1/me", { name: "SHIGGY", ddrCode: "12345678" });
  const config = { targetId: target.id, keys };
  const env = { CIRCLES_URL: "https://x", UAT_CONFIG: JSON.stringify(config) };
  const api = apiFor(env, config, send);
  for (const actor of actors) await api(actor.role, "PUT", "/v1/me", actor);
  assert.deepEqual(await tick(env, { now, send }), { attached: false });
  const code = (await personal("POST", "/v1/code")).code;
  for (const actor of actors) {
    await api(actor.role, "POST", "/v1/join", { code, back: actor.role !== "cheerleader" });
  }

  let result = await tick(env, { now, send });
  assert.deepEqual(result, { attached: true, posted: 3, cheered: 0 });
  let me = await personal("GET", "/v1/me");
  assert.equal(me.circle.length, 3);
  assert.equal(me.following.length, 2);
  assert.ok(me.circle.find((p) => p.name === "MIKA" && !p.friend));
  assert.ok(me.following.find((p) => p.name === "REXX").live);
  assert.equal(me.following.find((p) => p.name === "TOFU").live, undefined);
  let rexx = await api("active", "GET", "/v1/me");
  let rexxFeed = await api("active", "GET", "/v1/feed");
  assert.equal(rexxFeed.yours.filter((c) => c.session === rexx.live.session).length, 3);
  assert.ok(rexxFeed.yours.some((c) => c.plays.some((p) => p.failed)));
  assert.ok(rexxFeed.yours.some((c) => c.plays.some((p) => p.best)));
  // The app selects live credits using the session on the friend's profile.
  // Checking only REXX's own feed misses a broadcast without that session.
  const visibleRexx = me.following.find((p) => p.name === "REXX");
  assert.equal(visibleRexx.live.session, rexx.live.session);
  const visibleCredits = (await personal("GET", "/v1/feed")).credits
    .filter((c) => c.by.id === visibleRexx.id && c.session === visibleRexx.live.session);
  assert.equal(visibleCredits.length, 3, "REXX's live credits must be visible to the target");
  assert.equal(visibleCredits.flatMap((c) => c.plays).length, 9);
  for (const c of visibleCredits) {
    assert.deepEqual(c.plays.map((p) => p.song), ["MAX 300", "Healing-D-Vision", "CHAOS"]);
    assert.ok(c.plays.every((p) => Number.isInteger(p.score)));
  }
  const before = mutations;
  await tick(env, { now, send });
  assert.equal(mutations, before, "unchanged ticks must not mutate anything");

  const play = { song: "MAX 300", mode: "singles", difficulty: "EXPERT", score: 999000, best: true };
  await personal("PUT", "/v1/live", { venue: "Arcade", credit: 1, side: "1P", session: "real-session" });
  await personal("PUT", "/v1/credit", { session: "real-session", credit: 1, plays: [play] });
  result = await tick(env, { now, send });
  assert.equal(result.cheered, 0, "allow notification baseline before cheering");
  now += 30000;
  result = await tick(env, { now, send });
  assert.equal(result.cheered, 1);
  let feed = await personal("GET", "/v1/feed");
  assert.equal(feed.yours[0].cheers[0].name, "MIKA");
  assert.equal(feed.yours[0].cheers[0].preset, "clean");
  assert.equal((await tick(env, { now, send })).cheered, 0, "no repeated cheers");

  await personal("PUT", "/v1/credit", { session: "real-session", credit: 2, plays: [{ ...play, best: false }] });
  now += 30000;
  assert.equal((await tick(env, { now, send })).cheered, 1);
  await personal("DELETE", "/v1/live");
  assert.equal((await tick(env, { now, send })).cheered, 1, "react to finished session");
  feed = await personal("GET", "/v1/feed");
  assert.equal(feed.yours.find((c) => c.credit === 2).cheers[0].preset, "legend");
  assert.equal(feed.yours.find((c) => c.credit === 1).cheers[0].preset, "clean");

  // A second player can share the same dancer name without being targeted.
  await personal("PUT", "/v1/me", { name: "SHIGGY", ddrCode: "12345678" }, strangerKey);
  const strangerCode = (await personal("POST", "/v1/code", undefined, strangerKey)).code;
  await api("cheerleader", "POST", "/v1/join", { code: strangerCode });
  await personal("PUT", "/v1/credit", { session: "other-session", credit: 1, plays: [play] }, strangerKey);
  now += 30000;
  await tick(env, { now, send });
  assert.equal((await personal("GET", "/v1/feed", undefined, strangerKey)).yours[0].cheers.length, 0);

  // Recover after heartbeat expiry and feed expiry; keep a bounded daily feed.
  for (const hours of [3, 25, 49, 73]) {
    now = originalNow() + hours * 3600000;
    await tick(env, { now, send });
    rexx = await api("active", "GET", "/v1/me");
    rexxFeed = await api("active", "GET", "/v1/feed");
    assert.ok(rexx.live);
    assert.equal(rexxFeed.yours.filter((c) => c.session === rexx.live.session).length, 3);
    assert.ok(rexxFeed.yours.length <= 6);
  }

  // Removing the cheerleader stops automation and never silently rejoins.
  const mika = (await personal("GET", "/v1/me")).circle.find((p) => p.name === "MIKA");
  await personal("DELETE", `/v1/circle/${mika.id}`);
  assert.deepEqual(await tick(env, { now, send }), { attached: false });
  assert.equal((await personal("GET", "/v1/me")).circle.length, 2);
  assert.deepEqual(await tick({}), { disabled: true });
  assert.equal((await worker.fetch()).status, 404);
  await assert.rejects(tick({ UAT_CONFIG: JSON.stringify({ targetId: target.id, keys: {} }) }), /Invalid/);
  await assert.rejects(tick(env, { send: async () => new Response("private content", { status: 429 }) }), /429/);
  console.log("circles UAT: all checks passed");
} finally {
  Date.now = originalNow;
}
