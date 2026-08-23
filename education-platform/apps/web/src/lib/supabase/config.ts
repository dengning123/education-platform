export type PublicSupabaseConfig = Readonly<{
  url: string;
  publishableKey: string;
}>;

const forbiddenKeyPrefixes = ["sb_secret_", "sb_service_role_"];
const allowedProtocols = new Set(["http:", "https:"]);

function decodeLegacyJwtRole(key: string): string | null {
  const segments = key.split(".");
  if (segments.length !== 3) return null;

  try {
    const padded = segments[1].replaceAll("-", "+").replaceAll("_", "/")
      .padEnd(Math.ceil(segments[1].length / 4) * 4, "=");
    const payload = JSON.parse(atob(padded)) as { role?: unknown };
    return typeof payload.role === "string" ? payload.role : null;
  } catch {
    return null;
  }
}

export function validatePublicSupabaseConfig(
  rawUrl: string | undefined,
  rawPublishableKey: string | undefined,
): PublicSupabaseConfig {
  if (!rawUrl || !rawPublishableKey) {
    throw new Error("PUBLIC_SUPABASE_CONFIG_MISSING");
  }

  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new Error("PUBLIC_SUPABASE_URL_INVALID");
  }

  if (!allowedProtocols.has(url.protocol) || url.username || url.password) {
    throw new Error("PUBLIC_SUPABASE_URL_INVALID");
  }

  const publishableKey = rawPublishableKey.trim();
  if (publishableKey.length < 20 || forbiddenKeyPrefixes.some((prefix) => publishableKey.startsWith(prefix))) {
    throw new Error("PUBLIC_SUPABASE_KEY_REJECTED");
  }

  const legacyRole = decodeLegacyJwtRole(publishableKey);
  if (legacyRole !== null && legacyRole !== "anon") {
    throw new Error("PUBLIC_SUPABASE_KEY_REJECTED");
  }

  return Object.freeze({
    url: url.toString().replace(/\/$/, ""),
    publishableKey,
  });
}

export function getPublicSupabaseConfig(): PublicSupabaseConfig {
  return validatePublicSupabaseConfig(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );
}
