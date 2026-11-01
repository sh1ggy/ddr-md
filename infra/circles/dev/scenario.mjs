// Plays out circle scenarios against server.mjs, as made-up players and as
// "you": the debug build run with --dart-define=CIRCLES_KEY=<dev key>.
//
//   node infra/circles/dev/scenario.mjs <scenario>
//
// Pull to refresh on the Circle tab to see each one land.
import { YOU, keyOf } from "./d1.mjs";

const URL = process.env.CIRCLES_URL ?? "http://localhost:8787";
if (!["localhost", "127.0.0.1", "[::1]"].includes(new globalThis.URL(URL).hostname) &&
    !process.argv.includes("--allow-remote-fixtures")) {
  console.error("Scenarios use public fixture keys. Run against localhost; --allow-remote-fixtures is only for disposable test data.");
  process.exit(1);
}

async function as(who, method, path, body) {
  const res = await fetch(URL + path, {
    method,
    headers: { Authorization: `Bearer ${who}`, "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  }).catch(() => {
    console.error(`Nothing at ${URL}: start node infra/circles/dev/server.mjs first.`);
    process.exit(1);
  });
  const text = await res.text();
  if (res.status >= 300) throw new Error(`${method} ${path} as ${who.replace(/_+$/, "")}: ${res.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

// A made-up player with a DDR-CODE of their own.
const players = {
  MIKA: "51127734",
  REXX: "40981265",
  TOFU: "77310492",
  "JUN.K": "63048817",
  SABLE: "28816640",
};
async function player(name) {
  const key = keyOf(name);
  const me = await as(key, "GET", "/v1/me");
  return me.id ? { key, ...me } : { key, ...(await as(key, "PUT", "/v1/me", { name, ddrCode: players[name] })) };
}

// Your profile and a live code, made if the app hasn't yet.
async function you() {
  let me = await as(YOU, "GET", "/v1/me");
  if (!me.id) me = await as(YOU, "PUT", "/v1/me", { name: "SHIGGY", ddrCode: "12345678" });
  if (!me.code || new Date(me.codeUntil) < new Date()) me = await as(YOU, "POST", "/v1/code");
  return me;
}

// Has [name] join your circle.
async function joinYours(name) {
  const me = await you();
  const p = await player(name);
  await as(p.key, "POST", "/v1/join", { code: me.code });
  return p;
}

// You join [name]'s circle.
async function joinTheirs(name) {
  const p = await player(name);
  const code = (await as(p.key, "POST", "/v1/code")).code;
  await you();
  await as(YOU, "POST", "/v1/join", { code });
  return p;
}

// Three or four plays for a credit, a different set each [credit].
const songs = [
  ["MAX 300", "EXPERT"], ["PARANOiA Revolution", "DIFFICULT"], ["Healing-D-Vision", "EXPERT"],
  ["Lesson by DJ", "EXPERT"], ["Valkyrie dimension", "DIFFICULT"], ["CHAOS", "EXPERT"],
  ["Pluto Relinquish", "DIFFICULT"],
];
function someSongs(credit) {
  return Array.from({ length: 3 + (credit % 2) }, (_, i) => {
    const [song, difficulty] = songs[(credit * 3 + i) % songs.length];
    const score = 850000 + ((credit * 7919 + i * 104729) % 149990);
    return { song, mode: "singles", difficulty, score, failed: i === 2 && credit % 3 === 0, best: i === 0 };
  });
}

const scenarios = {
  "seed: a circle to look at: MIKA a friend, REXX and TOFU in yours, you in JUN.K's": async () => {
    await joinYours("MIKA");
    await joinTheirs("MIKA");
    await joinYours("REXX");
    await joinYours("TOFU");
    await joinTheirs("JUN.K");
  },
  "join: SABLE joins your circle": () => joinYours("SABLE"),
  "befriend: SABLE joins yours and lets you into theirs": async () => {
    await joinYours("SABLE");
    await joinTheirs("SABLE");
  },
  "leave: everyone leaves your circle": async () => {
    for (const p of (await as(YOU, "GET", "/v1/me")).circle) {
      await as(keyOf(p.name), "DELETE", `/v1/following/${(await you()).id}`);
    }
  },
  "live: MIKA starts a session (credit 1) and JUN.K is on credit 3": async () => {
    await as((await player("MIKA")).key, "PUT", "/v1/live", { venue: "Round1 Chicago", credit: 1, side: "1P", session: "mika-tonight" });
    await as((await player("JUN.K")).key, "PUT", "/v1/live", { venue: "Garden City", credit: 3, side: "2P", session: "junk-tonight" });
  },
  "credit: MIKA's credit syncs (songs and scores) and she starts the next": async () => {
    const mika = await player("MIKA");
    const live = (await as(YOU, "GET", "/v1/me")).following.find((p) => p.name === "MIKA")?.live;
    const credit = live?.credit ?? 1;
    await as(mika.key, "PUT", "/v1/credit", { session: "mika-tonight", credit, plays: someSongs(credit) });
    await as(mika.key, "PUT", "/v1/live", { venue: "Round1 Chicago", credit: credit + 1, side: "1P", session: "mika-tonight" });
  },
  "cheered: MIKA, REXX and TOFU cheer your latest credit (broadcast a session to see it on your live card)": async () => {
    const me = await you();
    // Your broadcast session's credits are what the live card shows; with
    // none synced yet, one stands in as if e-amusement had.
    const session = me.live?.session;
    if (!session) {
      console.error("Start or update a session with Broadcast to circle on, then rerun cheered. No sample was posted.");
      process.exit(1);
    }
    let yours = (await as(YOU, "GET", "/v1/feed")).yours.find((c) => c.session === session);
    if (!yours) {
      await as(YOU, "PUT", "/v1/credit", { session, credit: 1, plays: someSongs(1) });
      yours = (await as(YOU, "GET", "/v1/feed")).yours.find((c) => c.session === session);
    }
    for (const [name, preset] of [["MIKA", "legend"], ["REXX", "clean"], ["TOFU", "lets_go"]]) {
      await joinYours(name);
      // Repeating the scenario still produces new arrivals, rather than
      // resending the same three cheers the app has already shown.
      const next = yours.cheers.some((c) => c.name === name && c.preset === preset)
        ? ({legend: "lets_go", clean: "stamina", lets_go: "legend"})[preset] : preset;
      await as((await player(name)).key, "PUT", "/v1/cheer",
        { by: me.id, session: yours.session, credit: yours.credit, preset: next });
    }
  },
  "wrapped: you're in REXX's circle and REXX finishes a three-credit session, which MIKA cheered": async () => {
    const rexx = await joinTheirs("REXX");
    for (const credit of [1, 2, 3]) {
      await as(rexx.key, "PUT", "/v1/credit", { session: "rexx-thursday", credit, plays: someSongs(credit + 3) });
    }
    const mika = await player("MIKA");
    await as(mika.key, "POST", "/v1/join", { code: (await as(rexx.key, "POST", "/v1/code")).code });
    await as(mika.key, "PUT", "/v1/cheer", { by: rexx.id, session: "rexx-thursday", credit: 2, preset: "stamina" });
  },
  "end: MIKA and JUN.K end their sessions": async () => {
    for (const name of ["MIKA", "JUN.K"]) await as((await player(name)).key, "DELETE", "/v1/live");
  },
  "removed: MIKA takes you out of their circle": async () => {
    const me = await you();
    await as((await player("MIKA")).key, "DELETE", `/v1/circle/${me.id}`);
  },
  "reset: everyone, you included, deleted": async () => {
    for (const key of [YOU, ...Object.keys(players).map(keyOf)]) await as(key, "DELETE", "/v1/me");
  },
};

const name = process.argv[2];
const run = Object.entries(scenarios).find(([k]) => k.split(":")[0] === name);
if (!run) {
  console.log("node infra/circles/dev/scenario.mjs <scenario>\n");
  for (const k of Object.keys(scenarios)) console.log(`  ${k.replace(":", "  ·")}`);
  process.exit(name ? 1 : 0);
}
await run[1]();
const me = await as(YOU, "GET", "/v1/me");
console.log(`${run[0]}\n`);
console.log(`you: ${me.name ?? "(no profile)"} · code ${me.code ?? "none"}`);
console.log(`  your circle: ${me.circle?.map((p) => p.name + (p.friend ? " (friend)" : "")).join(", ") || "nobody"}`);
if (me.id) {
  const feed = await as(YOU, "GET", "/v1/feed");
  const cheers = (c) => (c.cheers.length ? ` · ${c.cheers.map((x) => `${x.name} ${x.preset}`).join(", ")}` : "");
  for (const c of feed.credits.slice(0, 3)) console.log(`  feed:        ${c.by.name} credit ${c.credit}, ${c.plays.length} songs${cheers(c)}`);
  for (const c of feed.yours.slice(0, 3)) console.log(`  your credit: ${c.credit}, ${c.plays.length} songs${cheers(c)}`);
}
console.log(`  you're in:   ${me.following?.map((p) => p.name + (p.friend ? " (friend)" : "") + (p.live ? ` (live, credit ${p.live.credit})` : "")).join(", ") || "nobody's"}`);
