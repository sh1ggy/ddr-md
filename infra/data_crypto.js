// Authenticated encryption for private database fields. The key is a Worker
// secret, kept separately from D1 and its backups. API clients remain compatible.
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const PREFIX = "sealed1:";

export async function dataCrypto(secret) {
  if (!/^[a-f0-9]{64}$/.test(secret ?? "")) throw new Error("missing data key");
  const material = Uint8Array.from(secret.match(/../g), (part) => parseInt(part, 16));
  const root = await crypto.subtle.importKey("raw", material, "HKDF", false, ["deriveKey"]);
  const derive = (name, algorithm, usages) => crypto.subtle.deriveKey({
    name: "HKDF", hash: "SHA-256", salt: encoder.encode("ddr-md-storage-v1"), info: encoder.encode(name),
  }, root, algorithm, false, usages);
  const [aes, mac] = await Promise.all([
    derive("fields", { name: "AES-GCM", length: 256 }, ["encrypt", "decrypt"]),
    derive("row-keys", { name: "HMAC", hash: "SHA-256", length: 256 }, ["sign"]),
  ]);
  return {
    sealed: (value) => typeof value === "string" && value.startsWith(PREFIX),
    async index(value) {
      const signature = await crypto.subtle.sign("HMAC", mac, encoder.encode(value));
      return "~1:" + [...new Uint8Array(signature)].map((b) => b.toString(16).padStart(2, "0")).join("");
    },
    async seal(value, context) {
      const iv = crypto.getRandomValues(new Uint8Array(12));
      const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: encoder.encode(context) }, aes, encoder.encode(value));
      return PREFIX + b64(iv) + "." + b64(new Uint8Array(ciphertext));
    },
    async open(value, context) {
      if (!this.sealed(value)) return value;
      const [iv, ciphertext] = value.slice(PREFIX.length).split(".");
      const clear = await crypto.subtle.decrypt({ name: "AES-GCM", iv: unb64(iv), additionalData: encoder.encode(context) }, aes, unb64(ciphertext));
      return decoder.decode(clear);
    },
  };
}

function b64(bytes) {
  let value = "";
  for (let i = 0; i < bytes.length; i += 8192) value += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(value);
}
function unb64(value) { return Uint8Array.from(atob(value), (c) => c.charCodeAt(0)); }

export async function secretMatches(provided, expected) {
  if (!expected || typeof provided !== "string" || provided.length > 256) return false;
  const key = await crypto.subtle.importKey("raw", encoder.encode("ddr-md-secret-comparison"), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(expected));
  return crypto.subtle.verify("HMAC", key, signature, encoder.encode(provided));
}

// Aggregate rotating IPv6 interface addresses within the same /64. Cloudflare
// supplies the address; request bodies and forwarded-for headers are ignored.
export function networkOf(ip) {
  if (!ip.includes(":")) return ip;
  const sides = ip.toLowerCase().split("::");
  const left = sides[0] ? sides[0].split(":") : [];
  const right = sides[1] ? sides[1].split(":") : [];
  const parts = sides.length === 2 ? [...left, ...Array(8 - left.length - right.length).fill("0"), ...right] : left;
  return parts.slice(0, 4).map((p) => parseInt(p, 16).toString(16)).join(":") + "::/64";
}
