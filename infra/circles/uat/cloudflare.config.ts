import { bindings, defineConfig, triggers } from "cf/config";
import * as entrypoint from "./entry.js" with { type: "cf-worker" };

export default defineConfig({
  worker: {
    name: "circles-uat",
    entrypoint,
    compatibilityDate: "2026-11-01",
    // Exercise the public Circles API, including its request controls.
    compatibilityFlags: ["global_fetch_strictly_public"],
    workersDev: false,
    env: {
      CIRCLES_URL: bindings.text("https://circles.ddr-md.workers.dev"),
      UAT_CONFIG: bindings.secret(),
    },
    triggers: [triggers.scheduled({ schedule: "* * * * *" })],
    observability: {
      enabled: true,
      logs: { enabled: true, invocationLogs: true },
      traces: { enabled: true },
    },
  },
});
