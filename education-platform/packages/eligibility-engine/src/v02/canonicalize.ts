import { createHash } from "node:crypto";

function nfc(value: string): string {
  return value.normalize("NFC");
}

function escapeJsonString(value: string): string {
  let out = "\"";
  for (const ch of nfc(value)) {
    const code = ch.codePointAt(0) ?? 0;
    if (ch === "\\") out += "\\\\";
    else if (ch === "\"") out += "\\\"";
    else if (code === 0x08) out += "\\b";
    else if (code === 0x0c) out += "\\f";
    else if (code === 0x0a) out += "\\n";
    else if (code === 0x0d) out += "\\r";
    else if (code === 0x09) out += "\\t";
    else if (code < 0x20) {
      out += `\\u${code.toString(16).padStart(4, "0")}`;
    } else {
      out += ch;
    }
  }
  return `${out}"`;
}

function canonicalNumber(n: number): string {
  if (!Number.isFinite(n)) {
    throw new Error("NaN/infinity forbidden");
  }
  if (Object.is(n, -0)) return "0";
  const asString = n.toString();
  if (asString.includes("e") || asString.includes("E")) {
    throw new Error("exponent form forbidden");
  }
  if (asString.includes(".")) {
    return asString.replace(/0+$/, "").replace(/\.$/, "");
  }
  return asString;
}

export function canonicalizeV02(value: unknown): string {
  if (value === null) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") return canonicalNumber(value);
  if (typeof value === "string") return escapeJsonString(value);
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalizeV02(item)).join(",")}]`;
  }
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    const keys = Object.keys(record)
      .map(nfc)
      .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    const seen = new Set<string>();
    for (const key of keys) {
      if (seen.has(key)) throw new Error("duplicate object key");
      seen.add(key);
    }
    return `{${keys
      .map((key) => `${escapeJsonString(key)}:${canonicalizeV02(record[key])}`)
      .join(",")}}`;
  }
  throw new Error("unsupported canonical value");
}

export function sha256Utf8Hex(canonical: string): string {
  return createHash("sha256").update(canonical, "utf8").digest("hex");
}

export function fingerprintV02(value: unknown): string {
  return sha256Utf8Hex(canonicalizeV02(value));
}
