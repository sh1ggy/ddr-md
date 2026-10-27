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
  `CREATE TABLE IF NOT EXISTS days(day TEXT PRIMARY KEY, writes INTEGER NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS networks(day TEXT NOT NULL, ip TEXT NOT NULL, rows INTEGER NOT NULL, PRIMARY KEY(day, ip))`,
];

const MAX_CHANGES = 200; // per push; keeps a request inside the free plan's CPU budget
const MAX_ROW = 32 * 1024;
const PULL_LIMIT = 500;
const DAY_ROWS = 20000; // rows per user per UTC day
// Rows per IP address per UTC day, however many keys it makes, so one
// script can't take the whole day's budget. A heavy first backup is ~2,200.
const NETWORK_ROWS = 30000;
// D1 rows written per UTC day, everyone together: 80% of the free plan's
// 100,000, and a small fraction of what a paid plan includes, so the
// account is never billed for sync. Each row costs two (row + revision
// index), each push three more (users, days, networks).
const DAY_WRITES = 80000;

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
  const { pathname, searchParams } = new URL(request.url);
  const route = `${request.method} ${pathname}`;
  if (route === "POST /v1/push") {
    const ip = request.headers.get("CF-Connecting-IP") ?? "";
    return push(db, owner, ip, await request.json().catch(() => null));
  }
  if (route === "GET /v1/pull") return pull(db, owner, Number(searchParams.get("cursor") ?? 0));
  if (route === "DELETE /v1/me") return remove(db, owner);
  return json({ error: "not found" }, 404);
}

async function push(db, owner, ip, body) {
  const changes = body?.changes;
  if (!Array.isArray(changes) || changes.length > MAX_CHANGES) return json({ error: "changes" }, 400);
  const now = new Date().toISOString();
  const day = now.slice(0, 10);
  const rows = [];
  for (const c of changes) {
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
  const ddrCode = /^\d{8}$/.test(body.ddrCode ?? "") ? body.ddrCode : null;
  const user = await db
    .prepare(
      `INSERT INTO users(owner, ddrCode, createdAt, seenAt) VALUES (?1, ?2, ?3, ?3)
       ON CONFLICT(owner) DO UPDATE SET seenAt = ?3, ddrCode = coalesce(?2, ddrCode)
       RETURNING day, dayRows, rev`,
    )
    .bind(owner, ddrCode, now)
    .first();
  const used = user.day === day ? user.dayRows : 0;
  if (used + rows.length > DAY_ROWS) return json({ error: "daily limit" }, 429);
  if (rows.length === 0) return json({ accepted: 0, rev: user.rev, lost: [] });
  const n = rows.length;
  const writes = n * 2 + 3;
  // The IP is kept only as a one-way fingerprint, and only for the day.
  const network = (await sha256(`${day} ${ip}`)).slice(0, 32);
  const counts = await db
    .prepare(
      `SELECT (SELECT writes FROM days WHERE day = ?1) AS total,
              (SELECT rows FROM networks WHERE day = ?1 AND ip = ?2) AS network`,
    )
    .bind(day, network)
    .first();
  if ((counts.total ?? 0) + writes > DAY_WRITES) return json({ error: "daily limit" }, 429);
  if ((counts.network ?? 0) + n > NETWORK_ROWS) return json({ error: "daily limit" }, 429);

  // One transaction: reserve n revisions, then give each row its own. A row
  // older than what's stored (another device wrote it later) keeps the newer
  // data but still takes the new revision, so the device that sent the older
  // one pulls the winner back.
  const prune = counts.total == null;
  const results = await db.batch([
    db
      .prepare(`UPDATE users SET rev = rev + ?1, day = ?2, dayRows = ?3 WHERE owner = ?4 RETURNING rev`)
      .bind(n, day, used + n, owner),
    db
      .prepare(`INSERT INTO days(day, writes) VALUES (?1, ?2) ON CONFLICT(day) DO UPDATE SET writes = writes + ?2`)
      .bind(day, writes),
    db
      .prepare(`INSERT INTO networks(day, ip, rows) VALUES (?1, ?2, ?3) ON CONFLICT(day, ip) DO UPDATE SET rows = rows + ?3`)
      .bind(day, network, n),
    // The day's first push clears earlier days' fingerprints.
    ...(prune ? [db.prepare(`DELETE FROM networks WHERE day < ?`).bind(day)] : []),
    ...rows.map(([t, k, u, d], i) =>
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
    .slice(prune ? 4 : 3)
    .flatMap((r, i) => (r.results[0].u === rows[i][2] ? [] : [i]));
  return json({ accepted: n, rev: results[0].results[0].rev, lost });
}

async function pull(db, owner, cursor) {
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
  // d is stored as JSON text, so it goes out as-is rather than parsed and
  // re-encoded.
  const changes = page
    .map((r) => `{"t":${JSON.stringify(r.t)},"k":${JSON.stringify(r.k)},"u":${JSON.stringify(r.u)},"d":${r.d ?? "null"}}`)
    .join(",");
  return new Response(
    `{"changes":[${changes}],"cursor":${next},"more":${more},"head":${head.results[0]?.rev ?? 0}}`,
    { headers: { "content-type": "application/json" } },
  );
}

async function remove(db, owner) {
  await db.batch([
    db.prepare(`DELETE FROM rows WHERE owner = ?`).bind(owner),
    db.prepare(`DELETE FROM users WHERE owner = ?`).bind(owner),
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
