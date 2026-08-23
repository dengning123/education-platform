export const PROFILE_RECOVERY_SCHEMA_VERSION = "PROFILE_LOCAL_RECOVERY_V1";
export const PROFILE_RECOVERY_TTL_MS = 30 * 60 * 1000;
export const PROFILE_RECOVERY_MAX_BYTES = 24 * 1024;

export const PROFILE_RECOVERY_STORE_KEY = "education-platform.profile.unsaved.v1";
export const PROFILE_RECOVERY_CONTEXT_KEY = "education-platform.profile.tab-context.v1";

export type ProfileRecoveryKind = "EDUCATION" | "COURSE" | "COMPLETENESS";

export type EducationRecoveryPayload = Readonly<{
  institutionName: string;
  degreeName: string;
  degreeLevel: "BACHELORS" | "MASTERS" | "DOCTORAL" | "CERTIFICATE" | "OTHER";
  degreeStatus: "IN_PROGRESS" | "COMPLETED" | "WITHDRAWN";
  startDate: string;
  completionDate: string;
  countryCode: string;
  gpaValue: string;
  gpaScale: string;
}>;

export type CourseRecoveryPayload = Readonly<{
  courseCode: string;
  courseTitle: string;
  courseStatus: "PLANNED" | "IN_PROGRESS" | "COMPLETED" | "WITHDRAWN";
  term: string;
  completionDate: string;
  credits: string;
  gradeValue: string;
  gradeScale: string;
  gradeText: string;
}>;

export type CompletenessRecoveryPayload = Readonly<{
  value: "COMPLETE" | "PARTIAL" | "UNKNOWN";
  explanation: string;
}>;

export type ProfileRecoveryPayloads = Readonly<{
  EDUCATION: EducationRecoveryPayload;
  COURSE: CourseRecoveryPayload;
  COMPLETENESS: CompletenessRecoveryPayload;
}>;

export type ProfileRecoveryIdentity = Readonly<{
  kind: ProfileRecoveryKind;
  profileVersionId: string;
  versionNumber: number;
  currentRevision: number;
  formContextId: string;
}>;

export type ProfileRecoveryCandidate<Kind extends ProfileRecoveryKind> = Readonly<{
  kind: Kind;
  payload: ProfileRecoveryPayloads[Kind];
  capturedRevision: number;
  revisionChanged: boolean;
  expiresAt: number;
}>;

type StoredRecoveryEntry = Readonly<{
  kind: ProfileRecoveryKind;
  profileFingerprint: string;
  contextFingerprint: string;
  versionNumber: number;
  profileRevision: number;
  createdAt: number;
  expiresAt: number;
  payload: unknown;
}>;

type StoredRecovery = Readonly<{
  schemaVersion: typeof PROFILE_RECOVERY_SCHEMA_VERSION;
  entries: readonly StoredRecoveryEntry[];
}>;

type RecoveryStorage = Pick<Storage, "getItem" | "setItem" | "removeItem">;

const UUID_V4_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FINGERPRINT_PATTERN = /^[0-9a-f]{64}$/;
const ALLOWED_PAYLOAD_KEYS: Readonly<Record<ProfileRecoveryKind, readonly string[]>> = Object.freeze({
  EDUCATION: Object.freeze(["institutionName", "degreeName", "degreeLevel", "degreeStatus", "startDate", "completionDate", "countryCode", "gpaValue", "gpaScale"]),
  COURSE: Object.freeze(["courseCode", "courseTitle", "courseStatus", "term", "completionDate", "credits", "gradeValue", "gradeScale", "gradeText"]),
  COMPLETENESS: Object.freeze(["value", "explanation"]),
});

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  return actual.length === expected.length && actual.every((key, index) => key === [...expected].sort()[index]);
}

function validPayload(kind: ProfileRecoveryKind, payload: unknown): payload is ProfileRecoveryPayloads[ProfileRecoveryKind] {
  if (!isRecord(payload) || !exactKeys(payload, ALLOWED_PAYLOAD_KEYS[kind])) return false;
  if (Object.values(payload).some((value) => typeof value !== "string" || value.length > 4_000)) return false;
  if (kind === "EDUCATION" && !["BACHELORS", "MASTERS", "DOCTORAL", "CERTIFICATE", "OTHER"].includes(String(payload.degreeLevel))) return false;
  if (kind === "EDUCATION" && !["IN_PROGRESS", "COMPLETED", "WITHDRAWN"].includes(String(payload.degreeStatus))) return false;
  if (kind === "COURSE" && !["PLANNED", "IN_PROGRESS", "COMPLETED", "WITHDRAWN"].includes(String(payload.courseStatus))) return false;
  if (kind === "COMPLETENESS" && !["COMPLETE", "PARTIAL", "UNKNOWN"].includes(String(payload.value))) return false;
  return true;
}

function parseProfileRecoveryStore(serialized: string | null): StoredRecovery | null {
  if (serialized === null || serialized.length > PROFILE_RECOVERY_MAX_BYTES) return null;
  try {
    const value = JSON.parse(serialized) as unknown;
    if (!isRecord(value) || !exactKeys(value, ["entries", "schemaVersion"]) || value.schemaVersion !== PROFILE_RECOVERY_SCHEMA_VERSION || !Array.isArray(value.entries)) return null;
    const entries: StoredRecoveryEntry[] = [];
    for (const candidate of value.entries) {
      if (!isRecord(candidate) || !exactKeys(candidate, ["contextFingerprint", "createdAt", "expiresAt", "kind", "payload", "profileFingerprint", "profileRevision", "versionNumber"])) return null;
      if (!["EDUCATION", "COURSE", "COMPLETENESS"].includes(String(candidate.kind))) return null;
      const kind = candidate.kind as ProfileRecoveryKind;
      if (!FINGERPRINT_PATTERN.test(String(candidate.profileFingerprint)) || !FINGERPRINT_PATTERN.test(String(candidate.contextFingerprint))) return null;
      if (![candidate.versionNumber, candidate.profileRevision, candidate.createdAt, candidate.expiresAt].every((entry) => typeof entry === "number" && Number.isSafeInteger(entry) && entry >= 0)) return null;
      if (!validPayload(kind, candidate.payload)) return null;
      entries.push(candidate as StoredRecoveryEntry);
    }
    return Object.freeze({ schemaVersion: PROFILE_RECOVERY_SCHEMA_VERSION, entries: Object.freeze(entries) });
  } catch {
    return null;
  }
}

function readStore(storage: RecoveryStorage): StoredRecovery {
  try {
    const raw = storage.getItem(PROFILE_RECOVERY_STORE_KEY);
    if (raw === null) return Object.freeze({ schemaVersion: PROFILE_RECOVERY_SCHEMA_VERSION, entries: Object.freeze([]) });
    const parsed = parseProfileRecoveryStore(raw);
    if (parsed) return parsed;
    storage.removeItem(PROFILE_RECOVERY_STORE_KEY);
  } catch {
    // A disabled or corrupted store behaves as if no recovery exists.
  }
  return Object.freeze({ schemaVersion: PROFILE_RECOVERY_SCHEMA_VERSION, entries: Object.freeze([]) });
}

function writeStore(storage: RecoveryStorage, entries: readonly StoredRecoveryEntry[]): boolean {
  const serialized = JSON.stringify({ schemaVersion: PROFILE_RECOVERY_SCHEMA_VERSION, entries });
  if (new TextEncoder().encode(serialized).byteLength > PROFILE_RECOVERY_MAX_BYTES) return false;
  try {
    storage.setItem(PROFILE_RECOVERY_STORE_KEY, serialized);
    return true;
  } catch {
    return false;
  }
}

function tabContext(storage: RecoveryStorage): string | null {
  try {
    const existing = storage.getItem(PROFILE_RECOVERY_CONTEXT_KEY);
    if (existing && UUID_V4_PATTERN.test(existing)) return existing.toLowerCase();
    const created = crypto.randomUUID().toLowerCase();
    storage.setItem(PROFILE_RECOVERY_CONTEXT_KEY, created);
    return created;
  } catch {
    return null;
  }
}

async function fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function fingerprints(storage: RecoveryStorage, identity: ProfileRecoveryIdentity) {
  const context = tabContext(storage);
  if (!context) return null;
  const profileFingerprint = await fingerprint(`${context}:PROFILE:${identity.profileVersionId}`);
  const contextFingerprint = await fingerprint(`${context}:${identity.kind}:${identity.profileVersionId}:${identity.formContextId}`);
  return Object.freeze({ profileFingerprint, contextFingerprint });
}

function liveEntries(store: StoredRecovery, now: number): readonly StoredRecoveryEntry[] {
  return store.entries.filter((entry) => entry.expiresAt > now);
}

export async function ensureProfileRecoveryContext(
  storage: RecoveryStorage,
  identity: Pick<ProfileRecoveryIdentity, "profileVersionId" | "versionNumber">,
  now = Date.now(),
): Promise<boolean> {
  const context = tabContext(storage);
  if (!context) return false;
  const expected = await fingerprint(`${context}:PROFILE:${identity.profileVersionId}`);
  const store = readStore(storage);
  const live = liveEntries(store, now);
  if (live.some((entry) => entry.profileFingerprint !== expected || entry.versionNumber !== identity.versionNumber)) {
    clearAllProfileRecovery(storage);
    return false;
  }
  if (live.length !== store.entries.length) writeStore(storage, live);
  return true;
}

export async function saveProfileRecovery<Kind extends ProfileRecoveryKind>(
  storage: RecoveryStorage,
  identity: ProfileRecoveryIdentity & Readonly<{ kind: Kind }>,
  payload: ProfileRecoveryPayloads[Kind],
  capturedRevision: number,
  now = Date.now(),
): Promise<boolean> {
  if (!validPayload(identity.kind, payload) || !Number.isSafeInteger(capturedRevision) || capturedRevision < 0) return false;
  const hashes = await fingerprints(storage, identity);
  if (!hashes) return false;
  const store = readStore(storage);
  let entries = liveEntries(store, now);
  if (entries.some((entry) => entry.profileFingerprint !== hashes.profileFingerprint || entry.versionNumber !== identity.versionNumber)) entries = [];
  const next: StoredRecoveryEntry = Object.freeze({
    kind: identity.kind,
    ...hashes,
    versionNumber: identity.versionNumber,
    profileRevision: capturedRevision,
    createdAt: now,
    expiresAt: now + PROFILE_RECOVERY_TTL_MS,
    payload: Object.freeze({ ...payload }),
  });
  return writeStore(storage, [...entries.filter((entry) => entry.contextFingerprint !== hashes.contextFingerprint), next]);
}

export async function loadProfileRecovery<Kind extends ProfileRecoveryKind>(
  storage: RecoveryStorage,
  identity: ProfileRecoveryIdentity & Readonly<{ kind: Kind }>,
  now = Date.now(),
): Promise<ProfileRecoveryCandidate<Kind> | null> {
  const hashes = await fingerprints(storage, identity);
  if (!hashes) return null;
  const store = readStore(storage);
  const live = liveEntries(store, now);
  if (live.some((entry) => entry.profileFingerprint !== hashes.profileFingerprint || entry.versionNumber !== identity.versionNumber)) {
    clearAllProfileRecovery(storage);
    return null;
  }
  if (live.length !== store.entries.length) writeStore(storage, live);
  const entry = live.find((candidate) => candidate.contextFingerprint === hashes.contextFingerprint && candidate.kind === identity.kind);
  if (!entry || !validPayload(identity.kind, entry.payload)) return null;
  return Object.freeze({
    kind: identity.kind,
    payload: entry.payload as ProfileRecoveryPayloads[Kind],
    capturedRevision: entry.profileRevision,
    revisionChanged: entry.profileRevision !== identity.currentRevision,
    expiresAt: entry.expiresAt,
  });
}

export async function clearProfileRecovery(storage: RecoveryStorage, identity: ProfileRecoveryIdentity): Promise<void> {
  const hashes = await fingerprints(storage, identity);
  if (!hashes) return;
  const store = readStore(storage);
  writeStore(storage, store.entries.filter((entry) => entry.contextFingerprint !== hashes.contextFingerprint));
}

export function clearAllProfileRecovery(storage: RecoveryStorage): void {
  try {
    storage.removeItem(PROFILE_RECOVERY_STORE_KEY);
    storage.removeItem(PROFILE_RECOVERY_CONTEXT_KEY);
  } catch {
    // Best-effort cleanup is fail-closed because no value is subsequently restored.
  }
}
