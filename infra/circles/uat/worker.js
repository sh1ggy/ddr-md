// Persistent, account-scoped Circles test players. All activity goes through
// the regular API, using private player keys. No access to the player's key
// or database is needed by this Worker. See infra/README.md.

export const actors = [
  { name: "MIKA", ddrCode: "00000001", role: "cheerleader" },
  { name: "REXX", ddrCode: "00000002", role: "active" },
  { name: "TOFU", ddrCode: "00000003", role: "inactive" },
];

export function configOf(env) {
  if (!env.UAT_CONFIG) return null;
  const config = JSON.parse(env.UAT_CONFIG);
  if (!/^[a-f0-9]{16}$/.test(config.targetId) ||
      !actors.every(({ role }) => /^[A-Za-z0-9_-]{43}$/.test(config.keys?.[role])) ||
      new Set(Object.values(config.keys)).size !== 3) {
    throw new Error("Invalid Circles UAT configuration");
  }
  return config;
}

export function apiFor(env, config, send = fetch) {
  return async (role, method, path, body) => {
    const response = await send(new Request(`${env.CIRCLES_URL}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${config.keys[role]}`,
        "content-type": "application/json",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    }));
    if (!response.ok) {
      // Do not log response bodies or keys.
      throw new Error(`Circles UAT ${role}: ${method} ${path}: ${response.status}`);
    }
    return response.status === 204 ? null : response.json();
  };
}

function playsFor(credit) {
  return ["MAX 300", "Healing-D-Vision", "CHAOS"].map((song, i) => ({
    song, mode: "singles", difficulty: "EXPERT",
    score: 910000 + credit * 1234 + i * 2500,
    failed: credit === 2 && i === 2,
    best: credit === 3 && i === 0,
  }));
}

export async function tick(env, { now = Date.now(), send = fetch } = {}) {
  const config = configOf(env);
  if (!config) return { disabled: true };
  const api = apiFor(env, config, send);
  const me = await api("cheerleader", "GET", "/v1/me");
  const target = me.following?.find((p) => p.id === config.targetId);
  // Removing MIKA or deleting the target account stops all activity. The
  // scheduled job never recreates profiles or restores memberships.
  if (!target) return { attached: false };

  let posted = 0;
  const active = await api("active", "GET", "/v1/me");
  if (active.id && active.circle.some((p) => p.id === config.targetId)) {
    const session = `uat-${new Date(now).toISOString().slice(0, 10)}`;
    const feed = await api("active", "GET", "/v1/feed");
    const credits = feed.yours.filter((c) => c.session === session);
    for (const credit of [1, 2, 3]) {
      if (credits.some((c) => c.credit === credit)) continue;
      await api("active", "PUT", "/v1/credit", { session, credit, plays: playsFor(credit) });
      posted++;
    }
    // goLive preserves its initial at. Restart the broadcast hourly to
    // refresh that timestamp and stay inside the two-hour expiry, keeping
    // the daily session id so its sample credits remain on the live card.
    if (active.live?.session !== session || now - Date.parse(active.live.at) >= 3600000) {
      if (active.live) await api("active", "DELETE", "/v1/live");
      await api("active", "PUT", "/v1/live", {
        venue: "UAT Arcade", credit: 4, side: "1P", session,
      });
    }
  }

  const feed = await api("cheerleader", "GET", "/v1/feed");
  const theirs = feed.credits.filter((c) => c.by.id === config.targetId);
  const latest = new Map();
  for (const c of theirs) {
    if (!latest.has(c.session) || latest.get(c.session).credit < c.credit) latest.set(c.session, c);
  }
  let cheered = 0;
  for (const c of theirs) {
    const live = c.session === target.live?.session;
    if (!live && latest.get(c.session) !== c) continue;
    // Let the app establish its notification baseline before a new arrival.
    if (now - Date.parse(c.at) < 15000) continue;
    const preset = !live ? "legend"
      : c.plays.some((p) => p.best && !p.failed) ? "clean" : "lets_go";
    if (c.mine === preset) continue;
    await api("cheerleader", "PUT", "/v1/cheer", {
      by: config.targetId, session: c.session, credit: c.credit, preset,
    });
    if (++cheered === 20) break;
  }
  return { attached: true, posted, cheered };
}

export default {
  async scheduled(_controller, env) {
    const result = await tick(env);
    if (result.posted || result.cheered) console.log(JSON.stringify({ event: "circles-uat", ...result }));
  },
  async fetch() {
    return new Response("Not found", { status: 404 });
  },
};
