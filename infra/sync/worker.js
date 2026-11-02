import { dataCrypto, networkOf, secretMatches } from "../data_crypto.js";

// Cloud sync for the app's own data (see infra/README.md "Cloud Sync").
//
// The server stores rows it never reads: each user's rows are opaque JSON keyed
// by (table, key), and every accepted write gets a per-user revision so a
// device can pull everything after its cursor. All joins and queries stay on
// the phone. The user is the SHA-256 of a random key the app generates; there
// is no sign-in. A DDR-CODE, when the app has one, is kept as a label only.
//
//   POST   /v1/push  {ddrCode?, changes: [{t, k, u, d}]}  d null = deleted
//                    -> {accepted, rev, lost}  rev = the user's revision
//                    after it; lost = indexes of changes a newer write beat
//   GET    /v1/pull?cursor=N  -> {changes: [{t, k, u, d}], cursor, more, head}
//                    head = the user's latest revision (0 when unknown)
//   DELETE /v1/me

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS users(owner TEXT PRIMARY KEY, ddrCode TEXT, createdAt TEXT NOT NULL, seenAt TEXT NOT NULL, rev INTEGER NOT NULL DEFAULT 0, day TEXT NOT NULL DEFAULT '', dayRows INTEGER NOT NULL DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS rows(owner TEXT NOT NULL, t TEXT NOT NULL, k TEXT NOT NULL, u TEXT NOT NULL, d TEXT, rev INTEGER NOT NULL, PRIMARY KEY(owner, t, k)) WITHOUT ROWID`,
  `CREATE INDEX IF NOT EXISTS rows_rev ON rows(owner, rev)`,
  `CREATE INDEX IF NOT EXISTS rows_legacy ON rows(owner) WHERE d IS NULL OR substr(d,1,8) != 'sealed1:'`,
  `CREATE INDEX IF NOT EXISTS users_legacy_labels ON users(owner) WHERE ddrCode IS NOT NULL AND substr(ddrCode,1,8) != 'sealed1:'`,
  `CREATE TABLE IF NOT EXISTS days(day TEXT PRIMARY KEY, writes INTEGER NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS admissions(day TEXT PRIMARY KEY, accounts INTEGER NOT NULL CHECK(accounts <= 200))`,
  `CREATE TRIGGER IF NOT EXISTS sync_enrollment BEFORE INSERT ON users WHEN NOT EXISTS(SELECT 1 FROM users WHERE owner = NEW.owner) BEGIN INSERT INTO admissions(day, accounts) VALUES (substr(NEW.createdAt,1,10),1) ON CONFLICT(day) DO UPDATE SET accounts = accounts + 1; END`,
  `CREATE TRIGGER IF NOT EXISTS sync_user_quota BEFORE UPDATE OF dayRows ON users WHEN NEW.dayRows > 20000 BEGIN SELECT RAISE(ABORT, 'sync quota'); END`,
  `CREATE TABLE IF NOT EXISTS networks(day TEXT NOT NULL, ip TEXT NOT NULL, rows INTEGER NOT NULL, PRIMARY KEY(day, ip))`,
  `CREATE TRIGGER IF NOT EXISTS sync_network_insert BEFORE INSERT ON networks WHEN NEW.rows > 30000 BEGIN SELECT RAISE(ABORT, 'sync quota'); END`,
  `CREATE TRIGGER IF NOT EXISTS sync_network_update BEFORE UPDATE OF rows ON networks WHEN NEW.rows > 30000 BEGIN SELECT RAISE(ABORT, 'sync quota'); END`,
];

const MAX_CHANGES = 200; // per push; keeps a request inside the free plan's CPU budget
const MAX_ROW = 32 * 1024;
const MAX_BODY = 8 * 1024 * 1024;
const PULL_LIMIT = 100; // Bounds decoded and encrypted page memory together.
// Database triggers enforce 20,000 rows/player/day and 30,000/network/day.
// Shared daily counters are telemetry, never a kill switch for established users.

let ready;

export default {
  async fetch(request, env) {
    try {
      if (request.method === "POST" && new URL(request.url).pathname === "/internal/maintenance") {
        if (!(await secretMatches(request.headers.get("Authorization"), `Bearer ${env.MAINTENANCE_KEY ?? ""}`)) || !env.MAINTENANCE_KEY) return json({error: "key"}, 401);
        ready ??= env.DB.batch(SCHEMA.map((s) => env.DB.prepare(s)));
        await ready;
        return json(await maintain(env.DB, await dataCrypto(env.DATA_KEY)));
      }
      const auth = request.headers.get("Authorization") ?? "";
      if (!/^Bearer [A-Za-z0-9_-]{43}$/.test(auth)) return json({ error: "key" }, 401);
      const { pathname, searchParams } = new URL(request.url);
      const route = `${request.method} ${pathname}`;
      if (!["POST /v1/push", "GET /v1/pull", "DELETE /v1/me"].includes(route)) {
        return json({ error: "not found" }, 404);
      }
      const cursor = Number(searchParams.get("cursor") ?? 0);
      if (route === "GET /v1/pull" && (!Number.isSafeInteger(cursor) || cursor < 0)) {
        return json({ error: "cursor" }, 400);
      }
      // Missing production bindings must not silently disable protection.
      if (request.cf && (!env.REQUEST_RATE || !env.NETWORK_RATE || !env.SAFETY_RATE)) {
        return json({ error: "unavailable" }, 503);
      }
      const ip = networkOf(request.headers.get("CF-Connecting-IP") ?? "local");
      const safety = request.method === "DELETE";
      if (!safety && env.NETWORK_RATE && !(await env.NETWORK_RATE.limit({ key: ip })).success) {
        return json({ error: "rate limit" }, 429);
      }
      const owner = await sha256(auth.slice(7));
      if (safety && env.SAFETY_RATE && !(await env.SAFETY_RATE.limit({ key: owner })).success) return json({ error: "rate limit" }, 429);
      if (!safety && env.REQUEST_RATE && !(await env.REQUEST_RATE.limit({ key: owner })).success) {
        return json({ error: "rate limit" }, 429);
      }
      let body;
      if (route === "POST /v1/push") {
        if (!request.body) return json({ error: "json" }, 400);
        const reader = request.body.getReader();
        const chunks = [];
        let size = 0;
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > MAX_BODY) {
            await reader.cancel();
            return json({ error: "body too large" }, 413);
          }
          chunks.push(value);
        }
        const data = new Uint8Array(size);
        let offset = 0;
        for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
        try { body = JSON.parse(new TextDecoder().decode(data)); }
        catch { return json({ error: "json" }, 400); }
        if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "json" }, 400);
      }
      const vault = await dataCrypto(env.DATA_KEY);
      ready ??= env.DB.batch(SCHEMA.map((s) => env.DB.prepare(s)));
      await ready;
      if (route === "POST /v1/push") return await push(env.DB, owner, ip, body, vault);
      if (route === "GET /v1/pull") return await pull(env.DB, owner, cursor, vault);
      return await remove(env.DB, owner);
    } catch (e) {
      ready = undefined;
      if (/sync quota|CHECK constraint failed.*accounts/.test(String(e?.message))) return json({error: "daily limit"}, 429);
      console.error(JSON.stringify({event: "sync_error"}));
      return json({ error: "server" }, 500);
    }
  },
  async scheduled(event, env) {
    ready ??= env.DB.batch(SCHEMA.map((s) => env.DB.prepare(s)));
    await ready;
    const result = await maintain(env.DB, await dataCrypto(env.DATA_KEY));
    console.log(JSON.stringify({event: "sync_maintenance", ...result}));
  },
};

async function push(db, owner, ip, body, vault) {
  const changes = body?.changes;
  if (!Array.isArray(changes) || changes.length > MAX_CHANGES) return json({ error: "changes" }, 400);
  const now = new Date().toISOString();
  const day = now.slice(0, 10);
  const rows = [];
  for (const c of changes) {
    if (!c || typeof c !== "object" || Array.isArray(c)) return json({ error: "change" }, 400);
    const d = c.d == null ? null : JSON.stringify(c.d);
    if (
      typeof c.t !== "string" || !/^[a-z_]{1,32}$/.test(c.t) ||
      typeof c.k !== "string" || c.k.length === 0 || c.k.length > 512 ||
      typeof c.u !== "string" || c.u.length > 32 ||
      (d !== null && (typeof c.d !== "object" || Array.isArray(c.d) || d.length > MAX_ROW))
    ) return json({ error: "change" }, 400);
    // A phone whose clock runs ahead would otherwise win every later edit.
    rows.push([c.t, c.k, c.u > now ? now : c.u, d]);
  }
  if (!rows.length) {
    const user = await db.prepare(`SELECT rev FROM users WHERE owner = ?`).bind(owner).first();
    return json({accepted: 0, rev: user?.rev ?? 0, lost: []});
  }
  // Upgrade this owner's legacy keys before an upsert can create duplicates.
  await migrate(db, vault, owner);
  const ddrCode = /^\d{8}$/.test(body.ddrCode ?? "") ? await vault.seal(body.ddrCode, `user:${owner}`) : null;
  const network = (await sha256(`${day} ${ip}`)).slice(0, 32);
  const n = rows.length;
  const sealed = await Promise.all(rows.map(async ([t, k, u, d]) => {
    const index = await vault.index(`${owner}\0${t}\0${k}`);
    return [t, index, u, await vault.seal(JSON.stringify({k, d: d === null ? null : JSON.parse(d)}), `${owner}\0${t}\0${index}`)];
  }));
  // Every allowance and data mutation is in the same transaction. A trigger
  // failure rolls back creation, counters, revisions, and rows together.
  const results = await db.batch([
    db.prepare(`INSERT INTO users(owner,ddrCode,createdAt,seenAt) VALUES (?1,?2,?3,?3)
      ON CONFLICT(owner) DO UPDATE SET seenAt=?3, ddrCode=coalesce(?2,users.ddrCode)`).bind(owner,ddrCode,now),
    db.prepare(`UPDATE users SET rev=rev+?1, day=?2,
      dayRows=CASE WHEN day=?2 THEN dayRows+?1 ELSE ?1 END WHERE owner=?3 RETURNING rev`).bind(n,day,owner),
    db.prepare(`INSERT INTO networks(day,ip,rows) VALUES (?1,?2,?3)
      ON CONFLICT(day,ip) DO UPDATE SET rows=rows+?3`).bind(day,network,n),
    db.prepare(`INSERT INTO days(day,writes) VALUES (?1,?2)
      ON CONFLICT(day) DO UPDATE SET writes=writes+?2`).bind(day,n*2+4),
    ...sealed.map(([t, k, u, d], i) =>
      db
        .prepare(
          `INSERT INTO rows(owner, t, k, u, d, rev)
           VALUES (?1, ?2, ?3, ?4, ?5, (SELECT rev FROM users WHERE owner = ?1) - ?6)
           ON CONFLICT(owner, t, k) DO UPDATE SET
             d = CASE WHEN excluded.u >= rows.u THEN excluded.d ELSE rows.d END,
             u = max(rows.u, excluded.u),
             rev = excluded.rev
           RETURNING u`,
        )
        .bind(owner, t, k, u, d, n - 1 - i),
    ),
  ]);
  // Indexes of rows a newer write beat.
  const lost = results
    .slice(4)
    .flatMap((r, i) => (r.results[0].u === rows[i][2] ? [] : [i]));
  return json({ accepted: n, rev: results[1].results[0].rev, lost });
}

async function pull(db, owner, cursor, vault) {
  if (!Number.isSafeInteger(cursor) || cursor < 0) return json({ error: "cursor" }, 400);
  const [{ results }, head] = await db.batch([
    db
      .prepare(`SELECT t, k, u, d, rev FROM rows WHERE owner = ? AND rev > ? ORDER BY rev LIMIT ?`)
      .bind(owner, cursor, PULL_LIMIT + 1),
    db.prepare(`SELECT rev FROM users WHERE owner = ?`).bind(owner),
  ]);
  const more = results.length > PULL_LIMIT;
  const page = results.slice(0, PULL_LIMIT);
  const next = page.length ? page[page.length - 1].rev : cursor;
  const changes = await Promise.all(page.map(async (r) => {
    if (!vault.sealed(r.d)) return {t:r.t,k:r.k,u:r.u,d:r.d === null ? null : JSON.parse(r.d)};
    const clear = JSON.parse(await vault.open(r.d, `${owner}\0${r.t}\0${r.k}`));
    return {t:r.t,k:clear.k,u:r.u,d:clear.d};
  }));
  return json({changes,cursor:next,more,head:head.results[0]?.rev ?? 0});
}

async function remove(db, owner) {
  await db.batch([
    db.prepare(`DELETE FROM rows WHERE owner = ?`).bind(owner),
    db.prepare(`DELETE FROM users WHERE owner = ?`).bind(owner),
  ]);
  return new Response(null, { status: 204, headers: privateHeaders() });
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function json(body, status = 200) {
  return Response.json(body, { status, headers: {
    ...privateHeaders(), ...(status === 429 ? { "Retry-After": "60" } : {}),
  } });
}

function privateHeaders() {
  return { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" };
}

// At most 100 legacy rows per transaction; no cleartext leaves the Worker.
async function migrate(db, vault, owner = null, once = false) {
  let migrated = 0;
  for (;;) {
    const {results} = await db.prepare(`SELECT owner,t,k,u,d,rev FROM rows
      WHERE (d IS NULL OR substr(d,1,8) != 'sealed1:') ${owner === null ? "" : "AND owner = ?"} LIMIT 100`)
      .bind(...(owner === null ? [] : [owner])).all();
    if (!results.length) return migrated;
    const statements = await Promise.all(results.map(async (r) => {
      const index = await vault.index(`${r.owner}\0${r.t}\0${r.k}`);
      const sealed = await vault.seal(JSON.stringify({k:r.k,d:r.d === null ? null : JSON.parse(r.d)}), `${r.owner}\0${r.t}\0${index}`);
      return db.prepare(`UPDATE rows SET k=?1,d=?2 WHERE owner=?3 AND t=?4 AND k=?5 AND rev=?6`)
        .bind(index,sealed,r.owner,r.t,r.k,r.rev);
    }));
    await db.batch(statements);
    migrated += results.length;
    if (once) return migrated;
  }
}

async function maintain(db, vault) {
  const day = new Date().toISOString().slice(0,10);
  const migrated = await migrate(db,vault,null,true);
  const {results:users} = await db.prepare(`SELECT owner,ddrCode FROM users WHERE ddrCode IS NOT NULL AND substr(ddrCode,1,8) != 'sealed1:' LIMIT 100`).all();
  const updates = await Promise.all(users.map(async (u) => db.prepare(`UPDATE users SET ddrCode=? WHERE owner=? AND ddrCode=?`)
    .bind(await vault.seal(u.ddrCode,`user:${u.owner}`),u.owner,u.ddrCode)));
  await db.batch([
    ...updates,
    db.prepare(`DELETE FROM networks WHERE day < ?`).bind(day),
    db.prepare(`DELETE FROM days WHERE day < date(?,'-7 days')`).bind(day),
    db.prepare(`DELETE FROM admissions WHERE day < ?`).bind(day),
  ]);
  return {migrated,labels:users.length};
}
