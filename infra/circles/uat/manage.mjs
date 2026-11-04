// Local administrator commands; only setup needs D1 access. Credentials stay
// in .secrets.json (gitignored), never in arguments or output.
import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { randomBytes } from "node:crypto";
import { execFileSync } from "node:child_process";
import { actors, apiFor, configOf, tick } from "./worker.js";

const directory = fileURLToPath(new URL(".", import.meta.url));
const secretsPath = new URL(".secrets.json", import.meta.url);
const statePath = new URL("../../terraform.tfstate", import.meta.url);
const CIRCLES_URL = process.env.CIRCLES_URL ?? "https://circles.ddr-md.workers.dev";
const [command, targetId] = process.argv.slice(2);

function cf(args, account) {
  return execFileSync("cf", args, {
    cwd: directory, encoding: "utf8",
    env: { ...process.env, ...(account ? { CLOUDFLARE_ACCOUNT_ID: account } : {}) },
    stdio: ["ignore", "pipe", "inherit"],
  });
}

function database() {
  const state = JSON.parse(readFileSync(statePath));
  const resource = state.resources.find((r) => r.type === "cloudflare_d1_database" && r.name === "circles");
  if (!resource) throw new Error("Circles D1 missing from infra/terraform.tfstate");
  const { id, account_id } = resource.instances[0].attributes;
  return (sql, params = []) => {
    const results = JSON.parse(cf(["d1", "query", id, "--body", JSON.stringify({ sql, params })], account_id));
    if (!results.every((r) => r.success)) throw new Error("D1 query failed");
    return results.flatMap((r) => r.results);
  };
}

async function main() {
  if (!["setup", "tick", "status", "reset"].includes(command)) {
    throw new Error("Usage: node manage.mjs <setup TARGET_ID | tick | status | reset>");
  }
  if (command === "setup") {
    if (!/^[a-f0-9]{16}$/.test(targetId ?? "")) throw new Error("A Circles profile id is required");
    if (CIRCLES_URL !== "https://circles.ddr-md.workers.dev") throw new Error("Setup uses the production D1 database and URL");
    const query = database();
    const target = query("SELECT id,name FROM profiles WHERE id=?", [targetId])[0];
    if (!target) throw new Error("Target profile does not exist");
    const saved = existsSync(secretsPath) ? JSON.parse(readFileSync(secretsPath)) : {
      UAT_CONFIG: JSON.stringify({ targetId, keys: Object.fromEntries(
        actors.map(({ role }) => [role, randomBytes(32).toString("base64url")]),
      ) }),
    };
    const config = configOf(saved);
    if (config.targetId !== targetId) throw new Error("Reset the existing target before changing accounts");
    writeFileSync(secretsPath, JSON.stringify(saved, null, 2) + "\n", { mode: 0o600 });
    const api = apiFor({ CIRCLES_URL }, config);
    for (const actor of actors) {
      const profile = await api(actor.role, "PUT", "/v1/me", { name: actor.name, ddrCode: actor.ddrCode });
      // Explicit admin attachment, without needing or changing the real
      // player's private key or rotating their invite code.
      const insert = `INSERT INTO members(leader,member,at)
        SELECT p.owner,q.owner,? FROM profiles p,profiles q WHERE p.id=? AND q.id=?
        AND (SELECT count(*) FROM members WHERE leader=p.owner)<100
        AND (SELECT count(*) FROM members WHERE member=q.owner)<100
        ON CONFLICT DO NOTHING`;
      query(insert, [new Date().toISOString(), targetId, profile.id]);
      if (actor.role !== "cheerleader") query(insert, [new Date().toISOString(), profile.id, targetId]);
      const me = await api(actor.role, "GET", "/v1/me");
      if (!me.following.some((p) => p.id === targetId) ||
          (actor.role !== "cheerleader" && !me.circle.some((p) => p.id === targetId))) {
        throw new Error(`Could not attach ${actor.name}; circle may be full`);
      }
      console.log(`${actor.name}: ${actor.role} attached to ${target.name}`);
    }
    console.log(JSON.stringify(await tick({ CIRCLES_URL, ...saved })));
    console.log("Private credentials saved in .secrets.json; deploy with cf deploy --secrets-file .secrets.json");
    return;
  }

  const saved = JSON.parse(readFileSync(secretsPath));
  const config = configOf(saved);
  const api = apiFor({ CIRCLES_URL }, config);
  if (command === "tick") {
    console.log(JSON.stringify(await tick({ CIRCLES_URL, ...saved })));
  } else if (command === "status") {
    for (const { role, name } of actors) {
      const me = await api(role, "GET", "/v1/me");
      const feed = me.id ? await api(role, "GET", "/v1/feed") : { yours: [] };
      console.log(JSON.stringify({ name, id: me.id, live: me.live,
        followsTarget: me.following?.some((p) => p.id === config.targetId),
        targetFollows: me.circle?.some((p) => p.id === config.targetId),
        credits: feed.yours.length }));
    }
  } else if (command === "reset") {
    // Disable first, so a scheduled run cannot recreate activity while
    // profiles are being removed. No real player's rows are deleted.
    cf(["workers", "secrets", "delete", "UAT_CONFIG", "--worker", "circles-uat", "--force"]);
    for (const { role, name } of actors) {
      await api(role, "DELETE", "/v1/me");
      console.log(`${name} removed`);
    }
    unlinkSync(secretsPath);
  }
}

await main().catch((error) => { console.error(error.message); process.exitCode = 1; });
