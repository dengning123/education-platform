import { describe, expect, it } from "vitest";

import {
  clearAllProfileRecovery,
  clearProfileRecovery,
  loadProfileRecovery,
  PROFILE_RECOVERY_CONTEXT_KEY,
  PROFILE_RECOVERY_SCHEMA_VERSION,
  PROFILE_RECOVERY_STORE_KEY,
  PROFILE_RECOVERY_TTL_MS,
  saveProfileRecovery,
  type ProfileRecoveryIdentity,
} from "./profile-recovery";

class MemoryStorage implements Storage {
  private readonly values = new Map<string, string>();

  get length() { return this.values.size; }
  clear() { this.values.clear(); }
  getItem(key: string) { return this.values.get(key) ?? null; }
  key(index: number) { return [...this.values.keys()][index] ?? null; }
  removeItem(key: string) { this.values.delete(key); }
  setItem(key: string, value: string) { this.values.set(key, value); }
}

const profileId = "00000000-0000-4000-8000-000000000501";
const otherProfileId = "00000000-0000-4000-8000-000000000502";

function identity(overrides: Partial<Omit<ProfileRecoveryIdentity, "kind">> = {}): ProfileRecoveryIdentity & { kind: "EDUCATION" } {
  return {
    kind: "EDUCATION",
    profileVersionId: profileId,
    versionNumber: 1,
    currentRevision: 4,
    formContextId: "CREATE",
    ...overrides,
  };
}

const educationPayload = {
  institutionName: "浙江大学",
  degreeName: "工学学士",
  degreeLevel: "BACHELORS",
  degreeStatus: "COMPLETED",
  startDate: "2020-09-01",
  completionDate: "2024-06-30",
  countryCode: "CN",
  gpaValue: "85",
  gpaScale: "100",
} as const;

describe("Profile session-local recovery", () => {
  it("round-trips a minimized draft without a raw Profile UUID, auth identity, token, locator, or relationship UUID", async () => {
    const storage = new MemoryStorage();
    expect(await saveProfileRecovery(storage, identity(), educationPayload, 4, 1_000)).toBe(true);

    const serialized = storage.getItem(PROFILE_RECOVERY_STORE_KEY) ?? "";
    expect(serialized).toContain(PROFILE_RECOVERY_SCHEMA_VERSION);
    for (const forbidden of [profileId, "studentId", "authUserId", "email", "access_token", "refresh_token", "cookie", "locator", "evidenceId", "degreeId"]) {
      expect(serialized.toLowerCase()).not.toContain(forbidden.toLowerCase());
    }

    const loaded = await loadProfileRecovery(storage, identity(), 1_001);
    expect(loaded).toMatchObject({ payload: educationPayload, capturedRevision: 4, revisionChanged: false });
  });

  it("marks a changed authoritative revision and never applies or saves it by merely reading", async () => {
    const storage = new MemoryStorage();
    await saveProfileRecovery(storage, identity(), educationPayload, 4, 1_000);
    const before = storage.getItem(PROFILE_RECOVERY_STORE_KEY);
    const loaded = await loadProfileRecovery(storage, identity({ currentRevision: 5 }), 1_001);
    expect(loaded?.revisionChanged).toBe(true);
    expect(loaded?.payload).toEqual(educationPayload);
    expect(storage.getItem(PROFILE_RECOVERY_STORE_KEY)).toBe(before);
  });

  it("fails closed on TTL expiry, schema mismatch, session context mismatch, and profile/version mismatch", async () => {
    const expired = new MemoryStorage();
    await saveProfileRecovery(expired, identity(), educationPayload, 4, 1_000);
    expect(await loadProfileRecovery(expired, identity(), 1_000 + PROFILE_RECOVERY_TTL_MS + 1)).toBeNull();
    expect(JSON.parse(expired.getItem(PROFILE_RECOVERY_STORE_KEY) ?? "{}").entries).toEqual([]);

    const schema = new MemoryStorage();
    schema.setItem(PROFILE_RECOVERY_STORE_KEY, JSON.stringify({ schemaVersion: "PROFILE_LOCAL_RECOVERY_V0", entries: [] }));
    expect(await loadProfileRecovery(schema, identity(), 2_000)).toBeNull();
    expect(schema.getItem(PROFILE_RECOVERY_STORE_KEY)).toBeNull();

    const session = new MemoryStorage();
    await saveProfileRecovery(session, identity(), educationPayload, 4, 3_000);
    session.setItem(PROFILE_RECOVERY_CONTEXT_KEY, "00000000-0000-4000-8000-000000000599");
    expect(await loadProfileRecovery(session, identity(), 3_001)).toBeNull();
    expect(session.getItem(PROFILE_RECOVERY_STORE_KEY)).toBeNull();

    const mismatch = new MemoryStorage();
    await saveProfileRecovery(mismatch, identity(), educationPayload, 4, 4_000);
    expect(await loadProfileRecovery(mismatch, identity({ profileVersionId: otherProfileId }), 4_001)).toBeNull();
    expect(mismatch.getItem(PROFILE_RECOVERY_STORE_KEY)).toBeNull();

    const version = new MemoryStorage();
    await saveProfileRecovery(version, identity(), educationPayload, 4, 5_000);
    expect(await loadProfileRecovery(version, identity({ versionNumber: 2 }), 5_001)).toBeNull();
    expect(version.getItem(PROFILE_RECOVERY_STORE_KEY)).toBeNull();
  });

  it("supports explicit per-form and session-wide cleanup", async () => {
    const storage = new MemoryStorage();
    await saveProfileRecovery(storage, identity(), educationPayload, 4, 1_000);
    await clearProfileRecovery(storage, identity());
    expect(await loadProfileRecovery(storage, identity(), 1_001)).toBeNull();

    await saveProfileRecovery(storage, identity(), educationPayload, 4, 2_000);
    clearAllProfileRecovery(storage);
    expect(storage.getItem(PROFILE_RECOVERY_STORE_KEY)).toBeNull();
    expect(storage.getItem(PROFILE_RECOVERY_CONTEXT_KEY)).toBeNull();
  });

  it("rejects arbitrary fields, identifiers, and malformed enum payloads", async () => {
    const storage = new MemoryStorage();
    expect(await saveProfileRecovery(storage, identity(), { ...educationPayload, evidenceId: profileId } as never, 4, 1_000)).toBe(false);
    expect(await saveProfileRecovery(storage, identity(), { ...educationPayload, degreeLevel: "PRESTIGE_TIER" } as never, 4, 1_000)).toBe(false);
    expect(storage.getItem(PROFILE_RECOVERY_STORE_KEY)).toBeNull();
  });
});
