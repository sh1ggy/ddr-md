// The slice of Cloudflare D1 the circles Worker uses, over Node's SQLite, so
// it runs and is tested without Cloudflare.
import { DatabaseSync } from "node:sqlite";

export function d1(path = ":memory:") {
  const sql = new DatabaseSync(path);
  class Statement {
    constructor(query, args = []) {
      this.query = query;
      this.args = args;
    }
    bind(...args) {
      return new Statement(this.query, args);
    }
    async all() {
      return { results: sql.prepare(this.query).all(...this.args) };
    }
    async first() {
      return (await this.all()).results[0] ?? null;
    }
    async run() {
      return this.all();
    }
  }
  return {
    prepare: (query) => new Statement(query),
    batch: async (statements) => {
      const results = [];
      for (const s of statements) results.push(await s.all());
      return results;
    },
  };
}

// A player's key: their name padded to the 43 characters a real one has.
export const keyOf = (name) => name.toLowerCase().replaceAll(/[^a-z0-9_-]/g, "-").padEnd(43, "_");

// The key a debug build uses with --dart-define=CIRCLES_KEY=, so scenarios
// can act as that player too.
export const YOU = keyOf("dev-you");
