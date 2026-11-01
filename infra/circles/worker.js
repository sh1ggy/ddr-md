// Circles: players following and cheering each other (see infra/README.md
// "Circles").
//
// Unlike cloud sync, this server reads what it stores: it decides who may see
// whom. A player is the SHA-256 of a random key the app generates, separate
// from the backup key. Others know them by their DDR dancer name and DDR-CODE,
// which the player gives and nobody checks; DDR-CODEs show on the cabinet, so
// one isn't unique here, and people are told apart by an opaque id derived
// from the key. Each player has one circle, joined with its invite code,
// which lasts a day; whoever has it is in. Two players in each other's
// circles are friends. A player can broadcast their session at the arcade
// to their circle, which sees it on them until it ends or lapses.
//
//   GET    /v1/me                 -> {id, name, ddrCode, code, codeUntil,
//                                     circle: [person], following: [person]}
//                                     person = {id, name, ddrCode, friend,
//                                       live?: {venue, credit, side, at}}
//   PUT    /v1/me    {name, ddrCode}  joins circles, or changes either
//   POST   /v1/code                a new invite code; the old one stops
//   GET    /v1/code/CODE          -> {person, members, friends}
//   POST   /v1/join  {code}       -> {name}
//   DELETE /v1/circle/ID          takes them out of your circle
//   DELETE /v1/following/ID       leaves their circle
//   PUT    /v1/live  {venue, credit, side}  broadcasting, for LIVE_LIFE
//   DELETE /v1/live               broadcast over
//   DELETE /v1/me                 everything of this player's goes

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS profiles(owner TEXT PRIMARY KEY, id TEXT NOT NULL UNIQUE, name TEXT NOT NULL, ddrCode TEXT NOT NULL, code TEXT UNIQUE, codeUntil TEXT, createdAt TEXT NOT NULL, day TEXT NOT NULL DEFAULT '', lookups INTEGER NOT NULL DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS members(leader TEXT NOT NULL, member TEXT NOT NULL, at TEXT NOT NULL, PRIMARY KEY(leader, member)) WITHOUT ROWID`,
  `CREATE INDEX IF NOT EXISTS members_member ON members(member)`,
  `CREATE TABLE IF NOT EXISTS days(day TEXT PRIMARY KEY, writes INTEGER NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS live(owner TEXT PRIMARY KEY, venue TEXT NOT NULL, credit INTEGER NOT NULL, side TEXT NOT NULL, at TEXT NOT NULL, until TEXT NOT NULL) WITHOUT ROWID`,
];

// A dancer name as the cabinet allows it.
const NAME = /^[A-Z0-9.\-*&!?#$@ ]{1,8}$/;
const DDR_CODE = /^\d{8}$/;
// No 0/O or 1/I, so a code read out loud at the cab is typed right.
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE = /^[A-HJ-NP-Z2-9]{8}$/;
// Code lookups and joins per player per UTC day, so codes can't be guessed.
const DAY_LOOKUPS = 30;
// How long an invite code works: long enough for a night at the arcade.
const CODE_LIFE = 86400000;
// Writes per UTC day, everyone together: well inside the free plan's D1
// allowance, so the account is never billed for circles.
const DAY_WRITES = 50000;
// A broadcast lapses this long after its last credit, for a session the app
// never got to end.
const LIVE_LIFE = 2 * 3600000;
const VENUE = 40;

let ready;

export default {
  async fetch(request, env) {
    try {
      ready ??= env.DB.batch(SCHEMA.map((s) => env.DB.prepare(s)));
      await ready;
      return await route(request, env.DB);
    } catch (e) {
      ready = undefined;
      console.error(e);
      return json({ error: "server" }, 500);
    }
  },
};

async function route(request, db) {
  const key = (request.headers.get("Authorization") ?? "").replace(/^Bearer /, "");
  if (!/^[A-Za-z0-9_-]{43}$/.test(key)) return json({ error: "key" }, 401);
  const owner = await sha256(key);
  const { pathname } = new URL(request.url);
  const [, version, what, arg] = pathname.split("/").map(decodeURIComponent);
  if (version !== "v1") return json({ error: "not found" }, 404);
  const body = request.method === "GET" || request.method === "DELETE"
    ? null
    : await request.json().catch(() => null);
  const route = `${request.method} ${what}${arg === undefined ? "" : "/"}`;
  if (request.method !== "GET") {
    const day = new Date().toISOString().slice(0, 10);
    const used = await db
      .prepare(`INSERT INTO days(day, writes) VALUES (?1, 1) ON CONFLICT(day) DO UPDATE SET writes = writes + 1 RETURNING writes`)
      .bind(day)
      .first();
    if (used.writes > DAY_WRITES) return json({ error: "daily limit" }, 429);
  }
  if (route === "PUT me") return claim(db, owner, body);
  if (route === "DELETE me") return remove(db, owner);
  // Everything else needs a profile first.
  const me = await db.prepare(`SELECT * FROM profiles WHERE owner = ?`).bind(owner).first();
  if (route === "GET me") return me ? state(db, me) : json({ id: null });
  if (!me) return json({ error: "profile" }, 403);
  if (route === "POST code") return newCode(db, me);
  if (route === "GET code/") return lookup(db, me, arg);
  if (route === "POST join") return join(db, me, body?.code);
  if (route === "DELETE circle/") return takeOut(db, me, arg);
  if (route === "DELETE following/") return leave(db, me, arg);
  if (route === "PUT live") return goLive(db, me, body);
  if (route === "DELETE live") return endLive(db, me);
  return json({ error: "not found" }, 404);
}

// Whether the other end of a membership row is in the near end's circle too.
const FRIEND = `EXISTS(SELECT 1 FROM members b WHERE b.leader = m.member AND b.member = m.leader)`;

const person = (r) => ({
  id: r.id,
  name: r.name,
  ddrCode: r.ddrCode,
  friend: r.friend === 1,
  ...(r.venue == null ? {} : { live: { venue: r.venue, credit: r.credit, side: r.side, at: r.at } }),
});

async function state(db, me) {
  const [circle, following] = await db.batch([
    db
      .prepare(
        `SELECT p.id, p.name, p.ddrCode, ${FRIEND} AS friend
         FROM members m JOIN profiles p ON p.owner = m.member WHERE m.leader = ? ORDER BY m.at`,
      )
      .bind(me.owner),
    db
      .prepare(
        `SELECT p.id, p.name, p.ddrCode, ${FRIEND} AS friend, l.venue, l.credit, l.side, l.at
         FROM members m JOIN profiles p ON p.owner = m.leader
         LEFT JOIN live l ON l.owner = m.leader AND l.until > ?2
         WHERE m.member = ?1 ORDER BY m.at`,
      )
      .bind(me.owner, new Date().toISOString()),
  ]);
  return json({
    id: me.id,
    name: me.name,
    ddrCode: me.ddrCode,
    code: me.code,
    codeUntil: me.codeUntil,
    circle: circle.results.map(person),
    following: following.results.map(person),
  });
}

async function claim(db, owner, body) {
  const name = String(body?.name ?? "").trim().toUpperCase();
  const ddrCode = String(body?.ddrCode ?? "").replaceAll(/\D/g, "");
  if (!NAME.test(name)) return json({ error: "name" }, 400);
  if (!DDR_CODE.test(ddrCode)) return json({ error: "ddrCode" }, 400);
  const id = (await sha256(`id:${owner}`)).slice(0, 16);
  await db
    .prepare(
      `INSERT INTO profiles(owner, id, name, ddrCode, createdAt) VALUES (?1, ?2, ?3, ?4, ?5)
       ON CONFLICT(owner) DO UPDATE SET name = ?3, ddrCode = ?4`,
    )
    .bind(owner, id, name, ddrCode, new Date().toISOString())
    .run();
  return state(db, await db.prepare(`SELECT * FROM profiles WHERE owner = ?`).bind(owner).first());
}

async function newCode(db, me) {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const code = [...bytes].map((b) => CODE_CHARS[b % CODE_CHARS.length]).join("");
  const until = new Date(Date.now() + CODE_LIFE).toISOString();
  await db.prepare(`UPDATE profiles SET code = ?1, codeUntil = ?2 WHERE owner = ?3`).bind(code, until, me.owner).run();
  return state(db, { ...me, code, codeUntil: until });
}

// The circle a live code opens, after this player's daily allowance.
async function byCode(db, me, code) {
  const day = new Date().toISOString().slice(0, 10);
  const used = me.day === day ? me.lookups : 0;
  if (used >= DAY_LOOKUPS) return { error: json({ error: "daily limit" }, 429) };
  await db.prepare(`UPDATE profiles SET day = ?1, lookups = ?2 WHERE owner = ?3`).bind(day, used + 1, me.owner).run();
  code = String(code ?? "").toUpperCase().replaceAll(/[^A-Z0-9]/g, "");
  if (!CODE.test(code)) return { error: json({ error: "code" }, 404) };
  const leader = await db
    .prepare(`SELECT * FROM profiles WHERE code = ?1 AND codeUntil > ?2`)
    .bind(code, new Date().toISOString())
    .first();
  if (!leader || leader.owner === me.owner) return { error: json({ error: "code" }, 404) };
  return { leader };
}

async function lookup(db, me, code) {
  const { leader, error } = await byCode(db, me, code);
  if (error) return error;
  const counts = await db
    .prepare(`SELECT count(*) AS members, sum(${FRIEND}) AS friends FROM members m WHERE m.leader = ?`)
    .bind(leader.owner)
    .first();
  return json({ person: person(leader), members: counts.members, friends: counts.friends ?? 0 });
}

async function join(db, me, code) {
  const { leader, error } = await byCode(db, me, code);
  if (error) return error;
  await db
    .prepare(`INSERT INTO members(leader, member, at) VALUES (?1, ?2, ?3) ON CONFLICT DO NOTHING`)
    .bind(leader.owner, me.owner, new Date().toISOString())
    .run();
  return json({ name: leader.name });
}

async function takeOut(db, me, id) {
  await db
    .prepare(`DELETE FROM members WHERE leader = ?1 AND member = (SELECT owner FROM profiles WHERE id = ?2)`)
    .bind(me.owner, id)
    .run();
  return state(db, me);
}

async function leave(db, me, id) {
  await db
    .prepare(`DELETE FROM members WHERE member = ?1 AND leader = (SELECT owner FROM profiles WHERE id = ?2)`)
    .bind(me.owner, id)
    .run();
  return state(db, me);
}

async function goLive(db, me, body) {
  const venue = String(body?.venue ?? "").trim().slice(0, VENUE);
  const credit = Number(body?.credit);
  const side = body?.side;
  if (!venue || !Number.isInteger(credit) || credit < 1 || !["1P", "2P"].includes(side)) {
    return json({ error: "live" }, 400);
  }
  const now = Date.now();
  await db
    .prepare(
      `INSERT INTO live(owner, venue, credit, side, at, until) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
       ON CONFLICT(owner) DO UPDATE SET venue = ?2, credit = ?3, side = ?4, until = ?6`,
    )
    .bind(me.owner, venue, credit, side, new Date(now).toISOString(), new Date(now + LIVE_LIFE).toISOString())
    .run();
  return new Response(null, { status: 204 });
}

async function endLive(db, me) {
  await db.prepare(`DELETE FROM live WHERE owner = ?`).bind(me.owner).run();
  return new Response(null, { status: 204 });
}

async function remove(db, owner) {
  await db.batch([
    db.prepare(`DELETE FROM live WHERE owner = ?`).bind(owner),
    db.prepare(`DELETE FROM members WHERE leader = ?1 OR member = ?1`).bind(owner),
    db.prepare(`DELETE FROM profiles WHERE owner = ?`).bind(owner),
  ]);
  return new Response(null, { status: 204 });
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function json(body, status = 200) {
  return Response.json(body, { status });
}
