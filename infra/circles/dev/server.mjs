// The circles Worker on this machine, for the app and scenario.mjs:
//
//   [PORT=8787] node infra/circles/dev/server.mjs [--fresh]
//
// Serves http://localhost:$PORT (8787) over build/circles-dev.db; --fresh starts that
// over empty. Run the app with --dart-define=CIRCLES_URL=http://localhost:8787
// (and CIRCLES_KEY, see README) to use it.
import http from "node:http";
import { mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import worker from "../worker.js";
import { d1 } from "./d1.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const path = join(root, "build/circles-dev.db");
mkdirSync(dirname(path), { recursive: true });
if (process.argv.includes("--fresh")) rmSync(path, { force: true });
const DB = d1(path);
const PORT = Number(process.env.PORT ?? 8787);

http
  .createServer(async (req, res) => {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const answer = await worker.fetch(
      new Request(`http://localhost:${PORT}${req.url}`, {
        method: req.method,
        headers: req.headers,
        body: chunks.length ? Buffer.concat(chunks) : undefined,
      }),
      { DB, DATA_KEY: "00".repeat(32) },
    );
    res.writeHead(answer.status, Object.fromEntries(answer.headers));
    res.end(Buffer.from(await answer.arrayBuffer()));
    console.log(req.method, req.url, answer.status);
  })
  .listen(PORT, "127.0.0.1", () => console.log(`circles on http://localhost:${PORT} (${path})`));
