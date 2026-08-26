import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

import { expect, test, type Page } from "@playwright/test";

type LocalUser = Readonly<{ id: string; email: string; password: string }>;
type ApiResponse = Readonly<{ status: number; body: Record<string, unknown> }>;
type ProfileDocument = Readonly<{ profileVersionId: string; revision: number; readiness: Readonly<{ freezeReady: boolean }> }>;
type Fixture = Readonly<{ classification: string; programVersionId: string; intentSetId: string; taxonomyReleaseCode: string }>;

const userIds: string[] = [];
let fixtureInstalled = false;

function localStatus(): Record<string, string> {
  const result = spawnSync(process.env.SUPABASE_BIN ?? "supabase", ["status", "--output", "json"], { encoding: "utf8" });
  if (result.status !== 0) throw new Error("Local Supabase status is unavailable");
  const start = result.stdout.indexOf("{");
  if (start < 0) throw new Error("Local Supabase status did not return JSON");
  return JSON.parse(result.stdout.slice(start));
}

const status = localStatus();
const apiUrl = new URL(status.API_URL);
if (!["127.0.0.1", "localhost"].includes(apiUrl.hostname) || !status.ANON_KEY) throw new Error("Test target is not the disposable local Supabase stack");

function container(): string {
  const value = process.env.PHASE025_DB_CONTAINER;
  if (!value || !/^supabase_db_[A-Za-z0-9_.-]+$/.test(value)) throw new Error("Exact disposable PHASE025_DB_CONTAINER is required");
  return value;
}

function database(sql: string): string {
  const result = spawnSync(process.env.DOCKER_BIN ?? "docker", [
    "exec", container(), "psql", "-U", "postgres", "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql,
  ], { encoding: "utf8" });
  if (result.status !== 0) throw new Error("Disposable local database command failed");
  return result.stdout.trim();
}

function installFixture(profileVersionId: string): Fixture {
  if (!/^[0-9a-f-]{36}$/i.test(profileVersionId)) throw new Error("Profile fixture identity is invalid");
  const sql = readFileSync(new URL("./profile-eligibility-fit.fixture.sql", import.meta.url), "utf8");
  const result = spawnSync(process.env.DOCKER_BIN ?? "docker", [
    "exec", "-i", container(), "psql", "-U", "postgres", "-d", "postgres", "-At",
    "-v", "ON_ERROR_STOP=1", "-v", `profile_version_id=${profileVersionId}`, "-f", "-",
  ], { encoding: "utf8", input: sql, maxBuffer: 4 * 1024 * 1024 });
  if (result.status !== 0) throw new Error("Local Profile/Eligibility/Fit fixture failed");
  const line = result.stdout.split("\n").map((value: string) => value.trim()).reverse().find((value: string) => value.startsWith("{"));
  if (!line) throw new Error("Local fixture did not return its closed identity");
  const fixture = JSON.parse(line) as Fixture;
  if (fixture.classification !== "GOLDEN PROGRAM RECORD + SYNTHETIC ELIGIBILITY RULES") throw new Error("Fixture classification is not explicit");
  fixtureInstalled = true;
  return fixture;
}

function resetLocalDatabase(): void {
  const result = spawnSync(process.env.SUPABASE_BIN ?? "supabase", ["db", "reset", "--local"], { encoding: "utf8", timeout: 180_000 });
  if (result.status !== 0) throw new Error("Disposable local database reset failed");
  fixtureInstalled = false;
  userIds.length = 0;
}

async function signUp(label: string): Promise<LocalUser> {
  const user = { id: "", email: `phase4b-e2e-${label}-${randomUUID()}@test.invalid`, password: `Phase4B-${randomUUID()}-Aa1!` };
  const response = await fetch(new URL("/auth/v1/signup", apiUrl), {
    method: "POST", headers: { apikey: status.ANON_KEY, "content-type": "application/json" },
    body: JSON.stringify({ email: user.email, password: user.password }),
  });
  const body = await response.json() as { user?: { id?: string } };
  if (!response.ok || !body.user?.id) throw new Error("Local Auth signup failed");
  const created = { ...user, id: body.user.id };
  userIds.push(created.id);
  return created;
}

async function signIn(page: Page, user: LocalUser) {
  await page.goto("/sign-in");
  await page.getByLabel("Email").fill(user.email);
  await page.getByLabel("Password").fill(user.password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/account$/);
}

async function post(page: Page, route: string, body: unknown): Promise<ApiResponse> {
  return page.evaluate(async ({ route: path, body: payload }) => {
    const response = await fetch(path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(payload) });
    const responseBody: unknown = await response.json();
    if (responseBody === null || typeof responseBody !== "object" || Array.isArray(responseBody)) throw new Error("API response was not an object");
    return { status: response.status, body: responseBody as Record<string, unknown> };
  }, { route, body });
}

function data<T>(response: ApiResponse): T {
  if (!("data" in response.body)) throw new Error("API response did not contain data");
  return response.body.data as T;
}

async function frozenProfile(page: Page, withSource: boolean): Promise<string> {
  const draft = await post(page, "/api/profile/draft", { operationId: randomUUID() });
  expect(draft.status).toBe(200);
  let document = data<ProfileDocument>(await post(page, "/api/profile/document", {}));
  if (withSource) {
    expect((await post(page, "/api/profile/mutate", {
      profileVersionId: document.profileVersionId, operationId: randomUUID(), expectedRevision: document.revision,
      command: "EVIDENCE_CREATE", payload: { evidenceType: "SELF_REPORT", locator: "Local connection proof", contentHash: null, observedAt: "2026-08-25T12:00:00Z" },
    })).status).toBe(200);
    document = data<ProfileDocument>(await post(page, "/api/profile/document", {}));
  }
  for (const domain of ["EDUCATION_HISTORY", "COURSE_HISTORY", "COURSE_MAPPING", "TEST_HISTORY", "EXPERIENCE_HISTORY", "SKILL_HISTORY", "PREFERENCES", "GOALS"]) {
    expect((await post(page, "/api/profile/mutate", {
      profileVersionId: document.profileVersionId, operationId: randomUUID(), expectedRevision: document.revision,
      command: "COMPLETENESS_UPSERT", payload: { educationContextId: null, domain, completeness: "COMPLETE", explanation: null },
    })).status).toBe(200);
    document = data<ProfileDocument>(await post(page, "/api/profile/document", {}));
  }
  expect(document.readiness.freezeReady).toBe(true);
  const frozen = await post(page, "/api/profile/freeze", {
    profileVersionId: document.profileVersionId, operationId: randomUUID(), expectedRevision: document.revision,
  });
  expect(frozen.status).toBe(200);
  const authoritative = data<{ status: string; profileVersionId: string }>(await post(page, "/api/profile/known-document", { profileVersionId: document.profileVersionId }));
  expect(authoritative.status).toBe("FROZEN");
  return authoritative.profileVersionId;
}

function fitRequest(profileVersionId: string, fixture: Fixture, eligibilityContextEvaluationId: string | null) {
  return {
    profileVersionId,
    intentSetId: fixture.intentSetId,
    programVersionId: fixture.programVersionId,
    taxonomyReleaseCode: fixture.taxonomyReleaseCode,
    supersedesEvaluationId: null,
    eligibilityContextEvaluationId,
    evidence: {
      canonicalObservationIds: [], catalogMappingIds: [], studentCourseIds: [], studentMappingIds: [], taxonomyConceptIds: [],
      contextClaimIds: [], contextMappingIds: [], accessContextId: null, directFinancialComparisons: [], approvedFinancialNormalizationIds: [],
    },
  };
}

function cleanupStudents(): void {
  const ids = userIds.filter((value) => /^[0-9a-f-]{36}$/i.test(value));
  if (ids.length === 0) return;
  const list = ids.map((value) => `'${value}'::uuid`).join(",");
  database(`
    do $cleanup$
    declare v_student_id uuid;
    begin
      for v_student_id in select student_id from private.student_identities where auth_user_id in (${list})
      loop
        perform public.delete_student_data(v_student_id, 'PHASE4B_PROFILE_ELIGIBILITY_FIT_E2E_CLEANUP');
      end loop;
      delete from auth.users where id in (${list});
    end
    $cleanup$;
  `);
}

test.afterAll(() => {
  if (fixtureInstalled || userIds.length > 0) resetLocalDatabase();
});

test("real Browser to frozen Profile to Eligibility to Fit remains owner-scoped and non-interfering", async ({ browser }) => {
  test.setTimeout(300_000);
  resetLocalDatabase();
  const alice = await signUp("alice");
  const bob = await signUp("bob");
  const aliceContext = await browser.newContext();
  const bobContext = await browser.newContext();
  const alicePage = await aliceContext.newPage();
  const bobPage = await bobContext.newPage();
  await signIn(alicePage, alice);
  await signIn(bobPage, bob);
  const aliceProfile = await frozenProfile(alicePage, true);
  const bobProfile = await frozenProfile(bobPage, false);
  const fixture = installFixture(aliceProfile);

  const aliceEligibilityOperationId = randomUUID();
  const aliceEligibilityRequest = {
    profileVersionId: aliceProfile,
    programVersionId: fixture.programVersionId,
    operationId: aliceEligibilityOperationId,
  };
  const aliceEligibilityResponse = await post(alicePage, "/api/evaluation/eligibility", aliceEligibilityRequest);
  expect(aliceEligibilityResponse.status).toBe(200);
  const aliceEligibility = data<{
    evalId: string; profileId: string; programId: string; requirements: readonly { explanation: string }[];
  }>(aliceEligibilityResponse);
  expect(aliceEligibility.profileId).toBe(aliceProfile);
  expect(aliceEligibility.programId).toBe(fixture.programVersionId);
  expect(aliceEligibility.requirements.length).toBeGreaterThan(0);
  expect(aliceEligibility.requirements.some((requirement) => requirement.explanation.length > 0)).toBe(true);
  expect(database(`select count(*) from public.eligibility_evaluations where evaluation_id = '${aliceEligibility.evalId}'::uuid and evaluation_state = 'COMPLETED';`)).toBe("1");
  const aliceEligibilityReplay = await post(alicePage, "/api/evaluation/eligibility", aliceEligibilityRequest);
  expect(aliceEligibilityReplay.status).toBe(200);
  expect(data(aliceEligibilityReplay)).toEqual(aliceEligibility);
  expect(database(`select count(*) from private.eligibility_assembly_operations_v026 where operation_id = '${aliceEligibilityOperationId}'::uuid;`)).toBe("1");

  const bobEligibilityResponse = await post(bobPage, "/api/evaluation/eligibility", {
    profileVersionId: bobProfile, programVersionId: fixture.programVersionId, operationId: randomUUID(),
  });
  expect(bobEligibilityResponse.status).toBe(200);
  const bobEligibility = data<{ evalId: string }>(bobEligibilityResponse);

  for (const [page, foreignProfile] of [[alicePage, bobProfile], [bobPage, aliceProfile]] as const) {
    const response = await post(page, "/api/evaluation/eligibility", { profileVersionId: foreignProfile, programVersionId: fixture.programVersionId, operationId: randomUUID() });
    expect(response.status).toBe(404);
    expect(response.body).toEqual(expect.objectContaining({ error: "PROFILE_NOT_FOUND" }));
  }

  const noContextResponse = await post(alicePage, "/api/evaluation/fit", fitRequest(aliceProfile, fixture, null));
  expect(noContextResponse.status).toBe(200);
  const noContext = data<{
    fitEvaluationId: string; candidateInputFingerprint: string; resultFingerprint: string;
    dimensions: Record<string, { assessment: string; confidence: string; evidenceCoverage: string; reasonCodes: readonly string[] }>;
  }>(noContextResponse);
  expect(Object.keys(noContext.dimensions)).toHaveLength(6);
  expect(Object.values(noContext.dimensions).some((dimension) => dimension.reasonCodes.length > 0)).toBe(true);

  const withContextResponse = await post(alicePage, "/api/evaluation/fit", fitRequest(aliceProfile, fixture, aliceEligibility.evalId));
  expect(withContextResponse.status).toBe(200);
  const withContext = data<typeof noContext>(withContextResponse);
  expect(withContext.dimensions).toEqual(noContext.dimensions);
  expect(withContext.candidateInputFingerprint).toBe(noContext.candidateInputFingerprint);
  expect(withContext.resultFingerprint).toBe(noContext.resultFingerprint);
  for (const fitEvaluationId of [noContext.fitEvaluationId, withContext.fitEvaluationId]) {
    expect(database(`select count(*) from public.fit_evaluations where evaluation_id = '${fitEvaluationId}'::uuid and evaluation_state = 'COMPLETED';`)).toBe("1");
    expect(database(`select count(*) from public.fit_dimension_results where evaluation_id = '${fitEvaluationId}'::uuid;`)).toBe("6");
  }

  const mismatchedContext = await post(alicePage, "/api/evaluation/fit", fitRequest(aliceProfile, fixture, bobEligibility.evalId));
  expect(mismatchedContext.status).toBe(422);
  expect(mismatchedContext.body).toEqual(expect.objectContaining({ error: "INVALID_REQUEST" }));
  const bobAttack = await post(bobPage, "/api/evaluation/fit", fitRequest(aliceProfile, fixture, aliceEligibility.evalId));
  expect(bobAttack.status).toBe(404);
  expect(bobAttack.body).toEqual(expect.objectContaining({ error: "RESOURCE_NOT_FOUND" }));

  const anonymousContext = await browser.newContext();
  const anonymousPage = await anonymousContext.newPage();
  await anonymousPage.goto("/sign-in");
  expect((await post(anonymousPage, "/api/evaluation/eligibility", { profileVersionId: aliceProfile, programVersionId: fixture.programVersionId, operationId: randomUUID() })).status).toBe(401);
  await anonymousContext.close();

  const expired = await signUp("expired");
  const expiredContext = await browser.newContext();
  const expiredPage = await expiredContext.newPage();
  await signIn(expiredPage, expired);
  database(`delete from auth.users where id = '${expired.id}'::uuid;`);
  expect((await post(expiredPage, "/api/evaluation/eligibility", { profileVersionId: aliceProfile, programVersionId: fixture.programVersionId, operationId: randomUUID() })).status).toBe(401);
  await expiredContext.close();

  const malformedContext = await browser.newContext();
  const authCookies = (await aliceContext.cookies()).filter((cookie) => cookie.name.includes("auth-token"));
  await malformedContext.addCookies(authCookies.map((cookie) => ({ ...cookie, value: "malformed-session" })));
  const malformedPage = await malformedContext.newPage();
  await malformedPage.goto("/sign-in");
  expect((await post(malformedPage, "/api/evaluation/eligibility", { profileVersionId: aliceProfile, programVersionId: fixture.programVersionId, operationId: randomUUID() })).status).toBe(401);
  await malformedContext.close();

  await aliceContext.close();
  await bobContext.close();
  cleanupStudents();
  resetLocalDatabase();
  expect(database("select count(*) from public.program_requirement_rule_sets where rule_set_id = '4b400000-0000-4000-8000-000000000001'::uuid;")).toBe("0");
  expect(database("select count(*) from public.fit_intent_sets where intent_set_id = '4b400000-0000-4000-8000-000000000010'::uuid;")).toBe("0");
});
