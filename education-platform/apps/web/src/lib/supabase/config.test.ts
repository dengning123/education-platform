import { describe, expect, it } from "vitest";

import { validatePublicSupabaseConfig } from "./config";

function legacyJwt(role: string): string {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ role })}.test-signature`;
}

describe("public Supabase configuration", () => {
  it("accepts a browser-safe publishable key", () => {
    expect(validatePublicSupabaseConfig(
      "https://project-ref.supabase.co/",
      "sb_publishable_phase4b1a_public_key",
    )).toEqual({
      url: "https://project-ref.supabase.co",
      publishableKey: "sb_publishable_phase4b1a_public_key",
    });
  });

  it("accepts only the anon role for legacy JWT public keys", () => {
    expect(validatePublicSupabaseConfig(
      "https://project-ref.supabase.co",
      legacyJwt("anon"),
    ).publishableKey).toBeTruthy();

    expect(() => validatePublicSupabaseConfig(
      "https://project-ref.supabase.co",
      legacyJwt("service_role"),
    )).toThrow("PUBLIC_SUPABASE_KEY_REJECTED");
  });

  it("rejects secret key formats, credentials in URLs, and missing values", () => {
    expect(() => validatePublicSupabaseConfig(
      "https://project-ref.supabase.co",
      "sb_secret_forbidden_browser_key",
    )).toThrow("PUBLIC_SUPABASE_KEY_REJECTED");
    expect(() => validatePublicSupabaseConfig(
      "https://user:password@project-ref.supabase.co",
      "sb_publishable_phase4b1a_public_key",
    )).toThrow("PUBLIC_SUPABASE_URL_INVALID");
    expect(() => validatePublicSupabaseConfig(undefined, undefined)).toThrow("PUBLIC_SUPABASE_CONFIG_MISSING");
  });
});
