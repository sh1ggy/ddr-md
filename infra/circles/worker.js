import { dataCrypto, networkOf, secretMatches } from "../data_crypto.js";

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
// to their circle, which sees it on them until it ends or lapses, and each
// credit's songs as it syncs. Their circle can cheer each credit, one preset
// each, and everyone in it sees the cheers. Credits and cheers last two days.
//
//   GET    /v1/me                 -> {id, name, ddrCode, code, codeUntil, live?,
//                                     circle: [person], following: [person]}
//                                     person = {id, name, ddrCode, friend,
//                                       live?: {venue, credit, side, session, at}}
//   PUT    /v1/me    {name, ddrCode}  joins circles, or changes either
//   POST   /v1/code                a new invite code; the old one stops
//   GET    /v1/code/CODE          -> {person, members, friends}
//   POST   /v1/join  {code, back}  -> {name}  back: let them into yours too
//   DELETE /v1/circle/ID          takes them out of your circle
//   DELETE /v1/following/ID       leaves their circle
//   PUT    /v1/live  {venue, credit, side, session?}  broadcasting, for LIVE_LIFE
//   DELETE /v1/live               broadcast over
//   PUT    /v1/credit {session, credit, plays: [play]}  a synced credit
//                                     play = {song, mode, difficulty, score, failed, best}
//   GET    /v1/feed               -> {credits: [{by: person, session, credit, at,
//                                       plays, cheers: [cheer], mine}],
//                                     yours: [{session, credit, at, plays, cheers}]}
//                                     cheer = {name, preset}; mine = your preset
//   PUT    /v1/cheer {by, session, credit, preset}  preset null takes it back
//   GET    /v1/showcase/ID         -> {cards: [card|null, card|null, card|null]}
//   PUT    /v1/showcase {cards}    replaces your three snapshots
//   DELETE /v1/me                 everything of this player's goes

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS showcases(owner TEXT PRIMARY KEY, cards TEXT NOT NULL) WITHOUT ROWID`,
  `CREATE TABLE IF NOT EXISTS profiles(owner TEXT PRIMARY KEY, id TEXT NOT NULL UNIQUE, name TEXT NOT NULL, ddrCode TEXT NOT NULL, code TEXT UNIQUE, codeUntil TEXT, createdAt TEXT NOT NULL, day TEXT NOT NULL DEFAULT '', lookups INTEGER NOT NULL DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS members(leader TEXT NOT NULL, member TEXT NOT NULL, at TEXT NOT NULL, PRIMARY KEY(leader, member)) WITHOUT ROWID`,
  `CREATE INDEX IF NOT EXISTS members_member ON members(member)`,
  `CREATE TABLE IF NOT EXISTS blocked(leader TEXT NOT NULL, member TEXT NOT NULL, PRIMARY KEY(leader,member)) WITHOUT ROWID`,
  `CREATE INDEX IF NOT EXISTS blocked_member ON blocked(member)`,
  `CREATE TABLE IF NOT EXISTS admissions(day TEXT PRIMARY KEY, accounts INTEGER NOT NULL CHECK(accounts <= 200))`,
  `CREATE TRIGGER IF NOT EXISTS circle_enrollment BEFORE INSERT ON profiles WHEN NOT EXISTS(SELECT 1 FROM profiles WHERE owner=NEW.owner) BEGIN INSERT INTO admissions(day,accounts) VALUES(substr(NEW.createdAt,1,10),1) ON CONFLICT(day) DO UPDATE SET accounts=accounts+1; END`,
  `CREATE TABLE IF NOT EXISTS usage(day TEXT NOT NULL, owner TEXT NOT NULL, mutations INTEGER NOT NULL CHECK(mutations <= 600), PRIMARY KEY(day,owner)) WITHOUT ROWID`,
  `CREATE INDEX IF NOT EXISTS usage_owner ON usage(owner)`,
  `CREATE TABLE IF NOT EXISTS days(day TEXT PRIMARY KEY, writes INTEGER NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS live(owner TEXT PRIMARY KEY, venue TEXT NOT NULL, credit INTEGER NOT NULL, side TEXT NOT NULL, session TEXT, at TEXT NOT NULL, until TEXT NOT NULL) WITHOUT ROWID`,
  `CREATE TABLE IF NOT EXISTS credits(owner TEXT NOT NULL, session TEXT NOT NULL, credit INTEGER NOT NULL, at TEXT NOT NULL, plays TEXT NOT NULL, PRIMARY KEY(owner, session, credit)) WITHOUT ROWID`,
  `CREATE INDEX IF NOT EXISTS credits_at ON credits(owner, at)`,
  `CREATE TABLE IF NOT EXISTS cheers(owner TEXT NOT NULL, session TEXT NOT NULL, credit INTEGER NOT NULL, cheerer TEXT NOT NULL, preset TEXT NOT NULL, at TEXT NOT NULL, PRIMARY KEY(owner, session, credit, cheerer)) WITHOUT ROWID`,
  `CREATE INDEX IF NOT EXISTS cheers_at ON cheers(owner, at)`,
  `CREATE INDEX IF NOT EXISTS live_until ON live(until)`,
  `CREATE INDEX IF NOT EXISTS live_legacy ON live(owner) WHERE substr(venue,1,8) != 'sealed1:'`,
  `CREATE INDEX IF NOT EXISTS credits_expiry ON credits(at)`,
  `CREATE INDEX IF NOT EXISTS cheers_expiry ON cheers(at)`,
  `CREATE INDEX IF NOT EXISTS cheers_cheerer ON cheers(cheerer)`,
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
// Mutations are bounded per player; there is no shared daily kill switch.
const MAX_BODY = 8192;
const MAX_MEMBERS = 100;
const MAX_CREDITS = 100;
// A broadcast lapses this long after its last credit, for a session the app
// never got to end.
const LIVE_LIFE = 2 * 3600000;
const VENUE = 40;
// How long a credit and its cheers stay up.
const FEED_LIFE = 2 * 86400000;
// The cheers the app offers; nothing else is taken, so there's no free text
// to moderate.
const PRESETS = ["lets_go", "clean", "stamina", "so_close", "rest_up", "legend"];
const SESSION = /^[A-Za-z0-9-]{1,64}$/;

let ready;

export default {
  async fetch(request, env) {
    try {
      if (request.method === "POST" && new URL(request.url).pathname === "/internal/maintenance") {
        if (!env.MAINTENANCE_KEY || !(await secretMatches(request.headers.get("Authorization"), `Bearer ${env.MAINTENANCE_KEY}`))) return json({error: "key"}, 401);
        ready ??= initialise(env.DB);
        await ready;
        return json(await maintain(env.DB, await dataCrypto(env.DATA_KEY), request.headers.get("X-Revoke-Invites") === "1"));
      }
      // Reject malformed auth/routes and throttle before touching D1.
      const auth = request.headers.get('Authorization') ?? '';
      if (!/^Bearer [A-Za-z0-9_-]{43}$/.test(auth)) return json({error: 'key'}, 401);
      const url = new URL(request.url);
      const allowed = /^(GET \/v1\/(me|feed|showcase\/[a-f0-9]{16}|code\/[A-HJ-NP-Z2-9-]{8,9})|PUT \/v1\/(me|live|credit|cheer|showcase)|POST \/v1\/(code|join|code\/lookup)|DELETE \/v1\/(me|live|circle\/[a-f0-9]{16}|following\/[a-f0-9]{16}))$/i;
      if (!allowed.test(`${request.method} ${url.pathname}`)) return json({error: 'not found'}, 404);
      if (request.cf && (!env.REQUEST_RATE || !env.NETWORK_RATE || !env.INVITE_RATE || !env.SAFETY_RATE)) {
        return json({error: 'unavailable'}, 503);
      }
      const ip = networkOf(request.headers.get('CF-Connecting-IP') ?? 'local');
      const safety = request.method === 'DELETE';
      if (!safety && env.NETWORK_RATE && !(await env.NETWORK_RATE.limit({key: ip})).success) return json({error: 'rate limit'}, 429);
      const owner = await sha256(auth.slice(7));
      if (!safety && env.REQUEST_RATE && !(await env.REQUEST_RATE.limit({key: owner})).success) return json({error: 'rate limit'}, 429);
      if (safety && env.SAFETY_RATE && !(await env.SAFETY_RATE.limit({key: owner})).success) return json({error: 'rate limit'}, 429);
      if ((url.pathname.startsWith('/v1/code/') || url.pathname === '/v1/join') &&
          env.INVITE_RATE && !(await env.INVITE_RATE.limit({key: ip})).success) return json({error: 'rate limit'}, 429);
      let body = null;
      if (['PUT', 'POST'].includes(request.method) && request.body) {
        const reader = request.body.getReader();
        const chunks = [];
        let size = 0;
        for (;;) {
          const {done, value} = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > MAX_BODY) { await reader.cancel(); return json({error: 'body too large'}, 413); }
          chunks.push(value);
        }
        const data = new Uint8Array(size);
        let offset = 0;
        for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
        if (size) {
          try { body = JSON.parse(new TextDecoder().decode(data)); }
          catch { return json({error: 'json'}, 400); }
          if (!body || typeof body !== 'object' || Array.isArray(body)) return json({error: 'json'}, 400);
        }
      }
      const vault = await dataCrypto(env.DATA_KEY);
      ready ??= initialise(env.DB);
      await ready;
      return await route(request, env.DB, owner, body, vault);
    } catch (e) {
      ready = undefined;
      if (/CHECK constraint failed.*(mutations|accounts)|circle quota/.test(String(e?.message))) return json({error: "daily limit"}, 429);
      console.error(JSON.stringify({event: "circles_error"}));
      return json({ error: "server" }, 500);
    }
  },
  async scheduled(event, env) {
    ready ??= initialise(env.DB);
    await ready;
    console.log(JSON.stringify({event: "circles_maintenance", ...await maintain(env.DB, await dataCrypto(env.DATA_KEY))}));
  },
};

// Additive upgrade for databases made before broadcasts carried a session.
async function initialise(db) {
  await db.batch(SCHEMA.map((s) => db.prepare(s)));
  const columns = await db.prepare("PRAGMA table_info(live)").all();
  if (!columns.results.some((column) => column.name === "session")) {
    await db.prepare("ALTER TABLE live ADD COLUMN session TEXT").run();
  }
}

async function route(request, db, owner, body, vault) {
  const { pathname } = new URL(request.url);
  const [, version, what, arg] = pathname.split('/');
  const route = `${request.method} ${what}${arg === undefined ? "" : "/"}`;
  if (route === "DELETE me") return remove(db, owner);
  const me = await db.prepare(`SELECT * FROM profiles WHERE owner = ?`).bind(owner).first();
  if (route === "GET me") return me ? state(db,me,vault) : json({id:null});
  if (!me && route !== "PUT me") return json({error:"profile"},403);
  // Deletion and revocation have a separate request limiter and do not
  // depend on mutation allowances. Invalid bodies spend no allowance.
  if (request.method !== "GET" && request.method !== "DELETE") {
    const invalid = validate(route, body);
    if (invalid) return json({error: invalid},400);
    const day = new Date().toISOString().slice(0,10);
    if (me) await db.prepare(`INSERT INTO usage(day,owner,mutations) VALUES (?1,?2,1)
      ON CONFLICT(day,owner) DO UPDATE SET mutations=mutations+1`).bind(day,owner).run();
  }
  if (route === "GET showcase/") return showcase(db, me, arg, vault);
  if (route === "PUT showcase") {
    const cards = body.cards.map(c => c === null ? null : Object.fromEntries(
      ['id','song','mode','difficulty','score','grade','lamp','flare','playedAt'].map(k => [k,c[k]])));
    await db.prepare(`INSERT INTO showcases(owner,cards) VALUES (?,?) ON CONFLICT(owner) DO UPDATE SET cards=excluded.cards`)
        .bind(owner, await vault.seal(JSON.stringify(cards), `showcase:${owner}`)).run();
    return showcase(db, me, me.id, vault);
  }
  if (route === "PUT me") return claim(db, owner, body, vault);

  if (route === "POST code") return newCode(db, me, vault);
  if (route === "POST code/") return lookup(db, me, body?.code);
  if (route === "GET code/") return lookup(db, me, arg);
  if (route === "POST join") return join(db, me, body?.code, body?.back === true);
  if (route === "DELETE circle/") return takeOut(db, me, arg, vault);
  if (route === "DELETE following/") return leave(db, me, arg, vault);
  if (route === "PUT live") return goLive(db, me, body, vault);
  if (route === "DELETE live") return endLive(db, me);
  if (route === "PUT credit") return postCredit(db, me, body);
  if (route === "GET feed") return feed(db, me);
  if (route === "PUT cheer") return cheer(db, me, body);
  return json({ error: "not found" }, 404);
}

// Whether the other end of a membership row is in the near end's circle too.
const FRIEND = `EXISTS(SELECT 1 FROM members b WHERE b.leader = m.member AND b.member = m.leader)`;

const person = (r) => ({
  id: r.id,
  name: r.name,
  ddrCode: r.ddrCode,
  friend: r.friend === 1,
  ...(r.venue == null ? {} : { live: { venue: r.venue, credit: r.credit, side: r.side, session: r.session ?? null, at: r.at } }),
});

async function state(db, me, vault) {
  const [circle, following, live] = await db.batch([
    db
      .prepare(
        `SELECT p.id, p.name, p.ddrCode, ${FRIEND} AS friend
         FROM members m JOIN profiles p ON p.owner = m.member WHERE m.leader = ? ORDER BY m.at`,
      )
      .bind(me.owner),
    db
      .prepare(
        `SELECT p.id, p.name, p.ddrCode, ${FRIEND} AS friend, l.venue, l.credit, l.side, l.session, l.at, m.leader AS liveOwner
         FROM members m JOIN profiles p ON p.owner = m.leader
         LEFT JOIN live l ON l.owner = m.leader AND l.until > ?2
         WHERE m.member = ?1 ORDER BY m.at`,
      )
      .bind(me.owner, new Date().toISOString()),
    db
      .prepare(`SELECT venue, credit, side, session, at FROM live WHERE owner = ? AND until > ?`)
      .bind(me.owner, new Date().toISOString()),
  ]);
  return json({
    id: me.id,
    name: me.name,
    ddrCode: me.ddrCode,
    code: me.code,
    codeUntil: me.codeUntil,
    // Your own broadcast, including its session.
    live: live.results[0] ? {...live.results[0],venue: await vault.open(live.results[0].venue,`live:${me.owner}`)} : null,
    circle: circle.results.map(person),
    following: await Promise.all(following.results.map(async (r) => person(r.venue == null ? r : {...r,venue: await vault.open(r.venue,`live:${r.liveOwner}`)}))),
  });
}

async function claim(db, owner, body, vault) {
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
  return state(db, await db.prepare(`SELECT * FROM profiles WHERE owner = ?`).bind(owner).first(), vault);
}

async function newCode(db, me, vault) {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const code = [...bytes].map((b) => CODE_CHARS[b % CODE_CHARS.length]).join("");
  const until = new Date(Date.now() + CODE_LIFE).toISOString();
  await db.prepare(`UPDATE profiles SET code = ?1, codeUntil = ?2 WHERE owner = ?3`).bind(code, until, me.owner).run();
  return state(db, { ...me, code, codeUntil: until }, vault);
}

// The circle a live code opens, after this player's daily allowance.
async function byCode(db, me, code) {
  const day = new Date().toISOString().slice(0, 10);
  const counted = await db.prepare(`UPDATE profiles SET day = ?1,
    lookups = CASE WHEN day = ?1 THEN lookups + 1 ELSE 1 END
    WHERE owner = ?2 AND (day != ?1 OR lookups < ?3) RETURNING lookups`)
    .bind(day, me.owner, DAY_LOOKUPS).first();
  if (!counted) return {error: json({error: 'daily limit'}, 429)};
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

// [back]: the joiner lets the leader into their own circle too, so one scan
// makes them friends. It only ever opens the joiner's circle, never the
// leader's, so it needs nothing from the leader.
async function join(db, me, code, back) {
  const { leader, error } = await byCode(db, me, code);
  if (error) return error;
  const insert = `INSERT INTO members(leader, member, at) SELECT ?1, ?2, ?3
    WHERE (SELECT count(*) FROM members WHERE leader = ?1) < ${MAX_MEMBERS}
      AND (SELECT count(*) FROM members WHERE member = ?2) < ${MAX_MEMBERS}
      AND NOT EXISTS(SELECT 1 FROM blocked WHERE leader=?1 AND member=?2)
      AND (?4 IS NULL OR EXISTS(SELECT 1 FROM profiles WHERE owner=?1 AND code=?4 AND codeUntil>?3))
      AND (?4 IS NOT NULL OR EXISTS(SELECT 1 FROM members WHERE leader=?2 AND member=?1))
    ON CONFLICT DO NOTHING`;
  const now = new Date().toISOString();
  await db.batch([
    db.prepare(insert).bind(leader.owner, me.owner, now, leader.code),
    ...(back ? [db.prepare(insert).bind(me.owner, leader.owner, now, null)] : []),
  ]);
  const joined = await db.prepare(`SELECT 1 FROM members WHERE leader = ? AND member = ?`).bind(leader.owner, me.owner).first();
  if (!joined) return json({error: 'circle full'}, 409);
  return json({ name: leader.name });
}

async function takeOut(db, me, id, vault) {
  await db.batch([
    db.prepare(`INSERT INTO blocked(leader,member) SELECT ?1,owner FROM profiles WHERE id=?2 ON CONFLICT DO NOTHING`).bind(me.owner,id),
    db.prepare(`DELETE FROM members WHERE leader=?1 AND member=(SELECT owner FROM profiles WHERE id=?2)`).bind(me.owner,id),
    db.prepare(`UPDATE profiles SET code=NULL,codeUntil=NULL WHERE owner=?`).bind(me.owner),
  ]);
  return state(db,{...me,code:null,codeUntil:null},vault);
}

async function leave(db, me, id, vault) {
  await db.batch([
    db.prepare(`DELETE FROM members WHERE member=?1 AND leader=(SELECT owner FROM profiles WHERE id=?2)`).bind(me.owner,id),
  ]);
  return state(db, me, vault);
}

async function goLive(db, me, body, vault) {
  const venue = String(body?.venue ?? "").trim().slice(0, VENUE);
  const credit = Number(body?.credit);
  const side = body?.side;
  // The app's session id, which its shared credits carry, so a broadcast's
  // credits can be told from another session's.
  const session = body?.session == null ? null : String(body.session);
  if (!Number.isInteger(credit) || credit < 1 || credit > 500 || !["1P", "2P"].includes(side) ||
      (session !== null && !SESSION.test(session))) {
    return json({ error: "live" }, 400);
  }
  const now = Date.now();
  await db
    .prepare(
      `INSERT INTO live(owner, venue, credit, side, session, at, until) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
       ON CONFLICT(owner) DO UPDATE SET venue = ?2, credit = ?3, side = ?4, session = ?5, until = ?7`,
    )
    .bind(me.owner, await vault.seal(venue,`live:${me.owner}`), credit, side, session, new Date(now).toISOString(), new Date(now + LIVE_LIFE).toISOString())
    .run();
  return new Response(null, { status: 204, headers: {"Cache-Control":"no-store","X-Content-Type-Options":"nosniff"} });
}

async function endLive(db, me) {
  await db.prepare(`DELETE FROM live WHERE owner = ?`).bind(me.owner).run();
  return new Response(null, { status: 204, headers: {"Cache-Control":"no-store","X-Content-Type-Options":"nosniff"} });
}

// A play as the feed shows it, or null for anything else.
function playOf(p) {
  const play = {
    song: String(p?.song ?? "").slice(0, 120),
    mode: p?.mode,
    difficulty: p?.difficulty,
    score: p?.score ?? null,
    failed: p?.failed === true,
    best: p?.best === true,
  };
  const ok =
    play.song &&
    ["singles", "doubles"].includes(play.mode) &&
    /^[A-Z]{1,12}$/.test(play.difficulty ?? "") &&
    (play.score === null || (Number.isInteger(play.score) && play.score >= 0 && play.score <= 1000000));
  return ok ? play : null;
}

async function postCredit(db, me, body) {
  const credit = Number(body?.credit);
  const plays = Array.isArray(body?.plays) && body.plays.length <= 6 ? body.plays.map(playOf) : [];
  if (!SESSION.test(body?.session ?? "") || !Number.isInteger(credit) || credit < 1 || credit > 500 ||
      plays.length === 0 || plays.includes(null)) {
    return json({ error: "credit" }, 400);
  }
  const now = Date.now();
  const old = new Date(now - FEED_LIFE).toISOString();
  const posted = await db.batch([
    db
      .prepare(
        `INSERT INTO credits(owner, session, credit, at, plays) SELECT ?1, ?2, ?3, ?4, ?5
         WHERE (SELECT count(*) FROM credits WHERE owner = ?1 AND at > ?6) < ${MAX_CREDITS}
           OR EXISTS(SELECT 1 FROM credits WHERE owner = ?1 AND session = ?2 AND credit = ?3)
         ON CONFLICT(owner, session, credit) DO UPDATE SET plays = ?5 RETURNING credit`,
      )
      .bind(me.owner, body.session, credit, new Date(now).toISOString(), JSON.stringify(plays), old),
    // Their own old credits and cheers go as new ones come.
    db.prepare(`DELETE FROM credits WHERE owner = ? AND at < ?`).bind(me.owner, old),
    db.prepare(`DELETE FROM cheers WHERE owner = ? AND at < ?`).bind(me.owner, old),
  ]);
  if (!posted[0].results.length) return json({error: 'credit limit'}, 429);
  return new Response(null, { status: 204, headers: {"Cache-Control":"no-store","X-Content-Type-Options":"nosniff"} });
}

async function feed(db, me) {
  const since = new Date(Date.now() - FEED_LIFE).toISOString();
  const [theirs, yours, cheers] = await db.batch([
    db
      .prepare(
        `SELECT c.owner, c.session, c.credit, c.at, c.plays, p.id, p.name, p.ddrCode, ${FRIEND} AS friend
         FROM members m JOIN credits c ON c.owner = m.leader JOIN profiles p ON p.owner = m.leader
         WHERE m.member = ?1 AND c.at > ?2 ORDER BY c.at DESC LIMIT 50`,
      )
      .bind(me.owner, since),
    db
      .prepare(`SELECT session, credit, at, plays FROM credits WHERE owner = ? AND at > ? ORDER BY at DESC LIMIT 20`)
      .bind(me.owner, since),
    db
      .prepare(
        `SELECT ch.owner, ch.session, ch.credit, ch.preset, ch.cheerer = ?1 AS mine, p.name, p.id
         FROM cheers ch JOIN profiles p ON p.owner = ch.cheerer
         WHERE (ch.owner = ?1 OR ch.owner IN (SELECT leader FROM members WHERE member = ?1)) AND ch.at > ?2
         ORDER BY ch.at DESC LIMIT 2000`,
      )
      .bind(me.owner, since),
  ]);
  const cheersOf = (owner, session, credit) =>
    cheers.results.filter((c) => c.owner === owner && c.session === session && c.credit === credit);
  return json({
    credits: theirs.results.map((c) => {
      const on = cheersOf(c.owner, c.session, c.credit);
      return {
        by: person(c),
        session: c.session,
        credit: c.credit,
        at: c.at,
        plays: JSON.parse(c.plays),
        cheers: on.map((x) => ({ id: x.id, name: x.name, preset: x.preset })),
        mine: on.find((x) => x.mine === 1)?.preset ?? null,
      };
    }),
    yours: yours.results.map((c) => ({
      session: c.session,
      credit: c.credit,
      at: c.at,
      plays: JSON.parse(c.plays),
      cheers: cheersOf(me.owner, c.session, c.credit).map((x) => ({ id: x.id, name: x.name, preset: x.preset })),
    })),
  });
}

async function cheer(db, me, body) {
  const preset = body?.preset ?? null;
  if (preset !== null && !PRESETS.includes(preset)) return json({ error: "preset" }, 400);
  // Only someone in their circle cheers a credit they've posted.
  const credit = await db
    .prepare(
      `SELECT c.owner FROM credits c JOIN profiles p ON p.owner = c.owner
       JOIN members m ON m.leader = c.owner AND m.member = ?1
       WHERE p.id = ?2 AND c.session = ?3 AND c.credit = ?4 AND c.at > ?5`,
    )
    .bind(me.owner, String(body?.by ?? ""), String(body?.session ?? ""), Number(body?.credit), new Date(Date.now() - FEED_LIFE).toISOString())
    .first();
  if (!credit) return json({ error: "credit" }, 404);
  const key = [credit.owner, body.session, Number(body.credit), me.owner];
  await (preset === null
    ? db.prepare(`DELETE FROM cheers WHERE owner = ?1 AND session = ?2 AND credit = ?3 AND cheerer = ?4`).bind(...key)
    : db
        .prepare(
          `INSERT INTO cheers(owner, session, credit, cheerer, preset, at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
           ON CONFLICT DO UPDATE SET preset = ?5, at = ?6`,
        )
        .bind(...key, preset, new Date().toISOString())
  ).run();
  return new Response(null, { status: 204, headers: {"Cache-Control":"no-store","X-Content-Type-Options":"nosniff"} });
}

async function remove(db, owner) {
  await db.batch([
    db.prepare(`DELETE FROM showcases WHERE owner=?`).bind(owner),
    db.prepare(`DELETE FROM credits WHERE owner = ?`).bind(owner),
    db.prepare(`DELETE FROM cheers WHERE owner = ?1 OR cheerer = ?1`).bind(owner),
    db.prepare(`DELETE FROM live WHERE owner = ?`).bind(owner),
    db.prepare(`DELETE FROM members WHERE leader = ?1 OR member = ?1`).bind(owner),
    db.prepare(`DELETE FROM blocked WHERE leader=?`).bind(owner),
    db.prepare(`DELETE FROM usage WHERE owner=?`).bind(owner),
    db.prepare(`DELETE FROM profiles WHERE owner = ?`).bind(owner),
  ]);
  return new Response(null, { status: 204, headers: {"Cache-Control":"no-store","X-Content-Type-Options":"nosniff"} });
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function json(body, status = 200) {
  return Response.json(body, {status, headers: {
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
    ...(status === 429 ? {'Retry-After': '60'} : {}),
  }});
}

function validate(route, body) {
  if (route === "PUT showcase") {
    if (!Array.isArray(body?.cards) || body.cards.length !== 3) return 'showcase';
    const ids = new Set(), charts = new Set();
    for (const c of body.cards) {
      if (c === null) continue;
      if (!c || typeof c !== 'object' || typeof c.id !== 'string' || c.id.length > 250 || !c.id.length || ids.has(c.id) ||
          typeof c.song !== 'string' || !c.song.length || c.song.length > 200 ||
          !['singles','doubles'].includes(c.mode) || !['BEGINNER','BASIC','DIFFICULT','EXPERT','CHALLENGE'].includes(c.difficulty) ||
          !Number.isInteger(c.score) || c.score < 0 || c.score > 1000000 ||
          !['','AAA','AA+','AA','AA-','A+','A','A-','B+','B','B-','C+','C','C-','D+','D','E'].includes(c.grade) ||
          !['','failed','clear','life4','fc','gfc','pfc','mfc'].includes(c.lamp) ||
          !['','I','II','III','IV','V','VI','VII','VIII','IX','EX'].includes(c.flare) ||
          (c.playedAt !== null && (typeof c.playedAt !== 'string' || !Number.isFinite(Date.parse(c.playedAt))))) return 'showcase';
      const chart = JSON.stringify([c.song,c.mode,c.difficulty]);
      if (charts.has(chart)) return 'showcase';
      charts.add(chart);
      ids.add(c.id);
    }
  }
  if (route === "PUT me") {
    if (!NAME.test(String(body?.name ?? "").trim().toUpperCase())) return "name";
    if (!DDR_CODE.test(String(body?.ddrCode ?? "").replaceAll(/\D/g,""))) return "ddrCode";
  }
  if (route === "PUT live") {
    if (!Number.isInteger(Number(body?.credit)) || Number(body.credit)<1 || Number(body.credit)>500 || !["1P","2P"].includes(body?.side) ||
        (body?.session != null && !SESSION.test(String(body.session)))) return "live";
  }
  if (route === "PUT credit") {
    if (!SESSION.test(body?.session ?? "") || !Number.isInteger(Number(body?.credit)) || Number(body.credit)<1 || Number(body.credit)>500 ||
        !Array.isArray(body?.plays) || !body.plays.length || body.plays.length>6 || body.plays.map(playOf).includes(null)) return "credit";
  }
  if (route === "PUT cheer" && body?.preset != null && !PRESETS.includes(body.preset)) return "preset";
  return null;
}

async function maintain(db,vault,revokeInvites=false) {
  const now=new Date().toISOString(), old=new Date(Date.now()-FEED_LIFE).toISOString(), day=now.slice(0,10);
  const {results:live}=await db.prepare(`SELECT owner,venue FROM live WHERE until>? AND substr(venue,1,8) != 'sealed1:' LIMIT 100`).bind(now).all();
  const updates=await Promise.all(live.map(async r=>db.prepare(`UPDATE live SET venue=? WHERE owner=? AND venue=?`)
    .bind(await vault.seal(r.venue,`live:${r.owner}`),r.owner,r.venue)));
  const results=await db.batch([
    ...updates,
    ...(revokeInvites ? [db.prepare(`UPDATE profiles SET code=NULL,codeUntil=NULL WHERE code IS NOT NULL`)] : []),
    db.prepare(`DELETE FROM live WHERE owner IN(SELECT owner FROM live WHERE until<=? LIMIT 1000)`).bind(now),
    db.prepare(`DELETE FROM credits WHERE (owner,session,credit) IN(SELECT owner,session,credit FROM credits WHERE at<=? LIMIT 1000)`).bind(old),
    db.prepare(`DELETE FROM cheers WHERE (owner,session,credit,cheerer) IN(SELECT owner,session,credit,cheerer FROM cheers WHERE at<=? LIMIT 1000)`).bind(old),
    db.prepare(`UPDATE profiles SET code=NULL,codeUntil=NULL WHERE owner IN(SELECT owner FROM profiles WHERE codeUntil<=? AND code IS NOT NULL LIMIT 1000)`).bind(now),
    db.prepare(`DELETE FROM usage WHERE day<?`).bind(day),
    db.prepare(`DELETE FROM admissions WHERE day<?`).bind(day),
    db.prepare(`DELETE FROM days WHERE day<?`).bind(day),
  ]);
  return {encrypted:live.length,maintenance:true};
}

// Showcase snapshots outlast the session feed. Only the owner and members
// of their circle may see them; only members can cheer.
async function showcase(db, me, id, vault) {
  const target = await db.prepare(`SELECT p.owner,s.cards FROM profiles p LEFT JOIN showcases s ON s.owner=p.owner
    WHERE p.id=?1 AND (p.owner=?2 OR EXISTS(SELECT 1 FROM members WHERE leader=p.owner AND member=?2))`).bind(id,me.owner).first();
  if (!target) return json({error:'showcase'},404);
  const cards = target.cards ? JSON.parse(await vault.open(target.cards, `showcase:${target.owner}`)) : [null,null,null];
  // Project legacy snapshots too: removed captions and reactions never leave the API.
  return json({cards:cards.map(c => c === null ? null : Object.fromEntries(
    ['id','song','mode','difficulty','score','grade','lamp','flare','playedAt'].map(k => [k,c[k]])))});
}
