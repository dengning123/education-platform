import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

import { expect, test, type Page } from "@playwright/test";

type LocalUser = Readonly<{ id: string; email: string; password: string }>;
type ApiResponse = Readonly<{ status: number; body: Record<string, unknown> }>;
type ProfileDocument = Readonly<{ profileVersionId: string; revision: number; readiness: Readonly<{ freezeReady: boolean }> }>;
type Fixture = Readonly<{ classification: string; programVersionId: string; ruleSetId: string }>;
type IntentDocument = Readonly<{
  intentSetId: string; profileVersionId: string; status: "DRAFT" | "FROZEN"; revision: number; snapshotHash: string | null;
  dimensions: readonly Readonly<{ dimension: string; state: string }>[];
  declarations: readonly Readonly<{ declarationId: string; dimension: string; typedValue: Record<string, unknown> }>[];
  readiness: Readonly<{ freezeReady: boolean }>;
}>;
type IntentOperation = Readonly<{ intentSetId: string; revision: number; resourceId?: string | null; document?: IntentDocument }>;

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

function fitRequest(profileVersionId: string, intentSetId: string, fixture: Fixture, completedEligibilityEvaluationId: string | null) {
  return {
    profileVersionId,
    intentSetId,
    programVersionId: fixture.programVersionId,
    completedEligibilityEvaluationId,
    operationId: randomUUID(),
  };
}

async function mutateIntent(page: Page, intentSetId: string, expectedRevision: number, command: string, payload: unknown, operationId = randomUUID()) {
  return post(page, "/api/intent/mutate", { intentSetId, operationId, expectedRevision, command, payload });
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

  const createOperationId = randomUUID();
  const createRequest = { profileVersionId: aliceProfile, operationId: createOperationId };
  const created = await post(alicePage, "/api/intent/create", createRequest);
  expect(created.status).toBe(200);
  const intent = data<IntentOperation>(created);
  expect(intent.revision).toBe(0);
  expect(data(await post(alicePage, "/api/intent/create", createRequest))).toEqual(intent);
  const intentSetId = intent.intentSetId;
  expect(data<{ activeDraft: IntentDocument }>(await post(alicePage, "/api/intent/discover", { profileVersionId: aliceProfile })).activeDraft.intentSetId).toBe(intentSetId);

  const deliveryOperationId = randomUUID();
  const deliveryPayload = { declaration: {
    dimension: "GEOGRAPHIC_DELIVERY", semanticType: "DELIVERY_CONSTRAINT", importance: "REQUIRED",
    importanceConfirmedByStudent: true, typedValue: { deliveryMode: "ONLINE", relation: "DESIRED" },
  } };
  const delivery = await mutateIntent(alicePage, intentSetId, 0, "DECLARATION_CREATE", deliveryPayload, deliveryOperationId);
  expect(delivery.status).toBe(200);
  expect(data(await mutateIntent(alicePage, intentSetId, 0, "DECLARATION_CREATE", deliveryPayload, deliveryOperationId))).toEqual(data(delivery));
  const conflict = await mutateIntent(alicePage, intentSetId, 0, "DECLARATION_CREATE", {
    declaration: { ...deliveryPayload.declaration, typedValue: { deliveryMode: "HYBRID", relation: "DESIRED" } },
  }, deliveryOperationId);
  expect(conflict.status).toBe(409);
  expect(conflict.body).toEqual(expect.objectContaining({ error: "INTENT_OPERATION_CONFLICT" }));

  let revision = 1;
  const duration = await mutateIntent(alicePage, intentSetId, revision, "DECLARATION_CREATE", { declaration: {
    dimension: "PERSONAL_PREFERENCE", semanticType: "DURATION_CONSTRAINT", importance: "PREFERRED",
    importanceConfirmedByStudent: true, typedValue: { minimumMonths: 6, maximumMonths: 24 },
  } });
  expect(duration.status).toBe(200);
  revision += 1;
  const durationId = data<IntentOperation>(duration).resourceId;
  expect(durationId).toMatch(/^[0-9a-f-]{36}$/i);
  expect((await mutateIntent(alicePage, intentSetId, revision, "DECLARATION_DELETE", { declarationId: durationId })).status).toBe(200);
  revision += 1;
  expect(data<IntentDocument>(await post(alicePage, "/api/intent/document", { intentSetId })).dimensions.find((item) => item.dimension === "PERSONAL_PREFERENCE")?.state).toBe("UNANSWERED");
  const finalDuration = await mutateIntent(alicePage, intentSetId, revision, "DECLARATION_CREATE", { declaration: {
    dimension: "PERSONAL_PREFERENCE", semanticType: "DURATION_CONSTRAINT", importance: "PREFERRED",
    importanceConfirmedByStudent: true, typedValue: { minimumMonths: 9, maximumMonths: 18 },
  } });
  expect(finalDuration.status).toBe(200);
  const finalDurationId = data<IntentOperation>(finalDuration).resourceId;
  expect(finalDurationId).toMatch(/^[0-9a-f-]{36}$/i);
  revision += 1;
  for (const dimension of ["ACADEMIC", "CAREER", "FINANCIAL", "INTERNATIONAL_ACCESSIBILITY"]) {
    expect((await mutateIntent(alicePage, intentSetId, revision, "DIMENSION_MARK_NOT_SUPPLIED", { dimension })).status).toBe(200);
    revision += 1;
  }

  const deliveryDeclarationId = data<IntentDocument>(await post(alicePage, "/api/intent/document", { intentSetId })).declarations
    .find((item) => item.dimension === "GEOGRAPHIC_DELIVERY")?.declarationId;
  expect(deliveryDeclarationId).toMatch(/^[0-9a-f-]{36}$/i);
  expect((await mutateIntent(alicePage, intentSetId, revision, "DECLARATION_REPLACE", {
    declarationId: deliveryDeclarationId,
    declaration: { ...deliveryPayload.declaration, typedValue: { deliveryMode: "HYBRID", relation: "DESIRED" } },
  })).status).toBe(200);
  revision += 1;
  expect((await mutateIntent(alicePage, intentSetId, revision, "DECLARATION_DELETE", {
    declarationId: deliveryDeclarationId,
  })).status).toBe(200);
  revision += 1;
  expect((await mutateIntent(alicePage, intentSetId, revision, "DECLARATION_DELETE", {
    declarationId: finalDurationId,
  })).status).toBe(200);
  revision += 1;
  for (const dimension of ["GEOGRAPHIC_DELIVERY", "PERSONAL_PREFERENCE"]) {
    expect((await mutateIntent(alicePage, intentSetId, revision, "DIMENSION_MARK_NOT_SUPPLIED", { dimension })).status).toBe(200);
    revision += 1;
  }
  const stale = await mutateIntent(alicePage, intentSetId, 0, "DIMENSION_MARK_NOT_SUPPLIED", { dimension: "ACADEMIC" });
  expect(stale.status).toBe(409);
  expect(stale.body).toEqual(expect.objectContaining({ error: "INTENT_REVISION_CONFLICT" }));

  await alicePage.goto("/account");
  await alicePage.getByRole("button", { name: "Sign out" }).click();
  await expect(alicePage).toHaveURL(/\/sign-in$/);
  await signIn(alicePage, alice);
  const resumed = data<IntentDocument>(await post(alicePage, "/api/intent/document", { intentSetId }));
  expect(resumed.revision).toBe(revision);
  expect(resumed.readiness.freezeReady).toBe(true);

  const freezeOperationId = randomUUID();
  const freezeRequest = { intentSetId, operationId: freezeOperationId, expectedRevision: revision };
  const frozenIntentResponse = await post(alicePage, "/api/intent/freeze", freezeRequest);
  expect(frozenIntentResponse.status).toBe(200);
  const frozenIntent = data<IntentOperation>(frozenIntentResponse);
  expect(frozenIntent.document?.status).toBe("FROZEN");
  expect(frozenIntent.document?.snapshotHash).toMatch(/^[a-f0-9]{64}$/);
  expect(data(await post(alicePage, "/api/intent/freeze", freezeRequest))).toEqual(frozenIntent);
  const frozenMutation = await mutateIntent(alicePage, intentSetId, frozenIntent.revision, "DIMENSION_MARK_NOT_SUPPLIED", { dimension: "ACADEMIC" });
  expect(frozenMutation.status).toBe(409);
  expect(frozenMutation.body).toEqual(expect.objectContaining({ error: "INTENT_LIFECYCLE_CONFLICT" }));

  for (const route of ["document", "taxonomy", "access-options"]) {
    const body = route === "taxonomy" ? { intentSetId, dimension: "ACADEMIC" } : { intentSetId };
    const attack = await post(bobPage, `/api/intent/${route}`, body);
    expect(attack.status).toBe(404);
  }
  expect((await mutateIntent(bobPage, intentSetId, frozenIntent.revision, "DIMENSION_MARK_NOT_SUPPLIED", { dimension: "ACADEMIC" })).status).toBe(404);

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

  const browserFitBodies: string[] = [];
  alicePage.on("request", (request) => {
    if (request.url().endsWith("/api/evaluation/fit") && request.method() === "POST") browserFitBodies.push(request.postData() ?? "");
  });
  const noContextResponse = await post(alicePage, "/api/evaluation/fit", fitRequest(aliceProfile, intentSetId, fixture, null));
  expect(noContextResponse.status).toBe(200);
  const noContext = data<{
    fitEvaluationId: string; candidateInputFingerprint: string; resultFingerprint: string;
    dimensions: Record<string, { assessment: string; confidence: string; evidenceCoverage: string; reasonCodes: readonly string[] }>;
  }>(noContextResponse);
  expect(Object.keys(noContext.dimensions)).toHaveLength(6);
  expect(Object.values(noContext.dimensions).some((dimension) => dimension.reasonCodes.length > 0)).toBe(true);
  for (const dimension of Object.values(noContext.dimensions)) {
    expect(dimension.assessment).toBe("UNKNOWN");
    expect(dimension.confidence).toBe("LOW");
    expect(dimension.evidenceCoverage).toBe("INSUFFICIENT");
  }

  const withContextResponse = await post(alicePage, "/api/evaluation/fit", fitRequest(aliceProfile, intentSetId, fixture, aliceEligibility.evalId));
  expect(withContextResponse.status).toBe(200);
  const withContext = data<typeof noContext>(withContextResponse);
  expect(withContext.dimensions).toEqual(noContext.dimensions);
  expect(withContext.candidateInputFingerprint).toBe(noContext.candidateInputFingerprint);
  expect(withContext.resultFingerprint).toBe(noContext.resultFingerprint);
  for (const fitEvaluationId of [noContext.fitEvaluationId, withContext.fitEvaluationId]) {
    expect(database(`select count(*) from public.fit_evaluations where evaluation_id = '${fitEvaluationId}'::uuid and evaluation_state = 'COMPLETED';`)).toBe("1");
    expect(database(`select count(*) from public.fit_dimension_results where evaluation_id = '${fitEvaluationId}'::uuid;`)).toBe("6");
    expect(database(`select count(*) from public.fit_signals where evaluation_id = '${fitEvaluationId}'::uuid;`)).toBe("0");
    expect(database(`select count(*) from public.fit_manifest_intent_declarations where evaluation_id = '${fitEvaluationId}'::uuid;`)).toBe("0");
    expect(database(`
      select count(*)
      from public.fit_manifest_items item
      join public.fit_manifest_phase2_completeness completeness
        using(manifest_item_id, evaluation_id, profile_version_id)
      join public.fit_dimension_methods method using(method_id)
      join public.fit_method_input_policies policy using(input_policy_id, method_id)
      join public.student_data_completeness source
        using(profile_version_id, completeness_id)
      where item.evaluation_id = '${fitEvaluationId}'::uuid
        and item.item_type = 'PHASE2_STUDENT_COMPLETENESS'
        and item.authority_role = 'LIMITING_CONTEXT'
        and item.source_class_code = case method.dimension
          when 'ACADEMIC' then 'STUDENT_RAW_ACADEMIC_HISTORY'
          when 'INTERNATIONAL_ACCESSIBILITY' then 'STUDENT_RAW_ACCESS_CONTEXT'
          else 'STUDENT_RAW_INTENT' end
        and policy.input_domain = 'STUDENT_COMPLETENESS'
        and source.education_context_id is null
        and source.domain = case when method.dimension in (
          'ACADEMIC','CAREER','INTERNATIONAL_ACCESSIBILITY'
        ) then 'GOALS'::public.student_data_domain
        else 'PREFERENCES'::public.student_data_domain end;
    `)).toBe("6");
    expect(database(`
      select count(*)
      from public.fit_input_domain_states state
      join public.fit_method_input_policies policy using(input_policy_id, method_id)
      where state.evaluation_id = '${fitEvaluationId}'::uuid
        and policy.input_domain = 'FIT_INTENTS'
        and state.availability = 'NOT_SUPPLIED'
        and state.completeness_manifest_item_id is null
        and state.provenance_manifest_item_id is null;
    `)).toBe("6");
    expect(database(`
      select count(*) from public.fit_evaluations evaluation
      join public.fit_evaluator_builds build using(evaluator_build_id)
      where evaluation.evaluation_id = '${fitEvaluationId}'::uuid
        and build.evaluator_build_id = '30000000-0000-0000-0000-000000000284'::uuid
        and build.evaluator_version = '0.1.0-product-v027';
    `)).toBe("1");
  }

  const changedCreate = data<IntentOperation>(await post(alicePage, "/api/intent/create", {
    profileVersionId: aliceProfile,
    operationId: randomUUID(),
  }));
  const changedIntentSetId = changedCreate.intentSetId;
  expect((await mutateIntent(alicePage, changedIntentSetId, 0, "DECLARATION_CREATE", { declaration: {
    dimension: "PERSONAL_PREFERENCE", semanticType: "PROGRAM_FEATURE_CONSTRAINT", importance: "PREFERRED",
    importanceConfirmedByStudent: true, typedValue: { featureKey: "CAPSTONE_AVAILABLE", expected: true },
  } })).status).toBe(200);
  let changedRevision = 1;
  for (const dimension of ["ACADEMIC", "CAREER", "FINANCIAL", "GEOGRAPHIC_DELIVERY", "INTERNATIONAL_ACCESSIBILITY"]) {
    expect((await mutateIntent(alicePage, changedIntentSetId, changedRevision, "DIMENSION_MARK_NOT_SUPPLIED", { dimension })).status).toBe(200);
    changedRevision += 1;
  }
  expect((await post(alicePage, "/api/intent/freeze", {
    intentSetId: changedIntentSetId,
    operationId: randomUUID(),
    expectedRevision: changedRevision,
  })).status).toBe(200);
  const changedDispositionResponse = await post(
    alicePage,
    "/api/evaluation/fit",
    fitRequest(aliceProfile, changedIntentSetId, fixture, null),
  );
  expect(changedDispositionResponse.status).toBe(200);
  const changedDisposition = data<typeof noContext>(changedDispositionResponse);
  expect(changedDisposition.candidateInputFingerprint).not.toBe(noContext.candidateInputFingerprint);

  expect(browserFitBodies).toHaveLength(3);
  for (const serialized of browserFitBodies) {
    expect(Object.keys(JSON.parse(serialized)).sort()).toEqual(["completedEligibilityEvaluationId", "intentSetId", "operationId", "profileVersionId", "programVersionId"].sort());
    expect(serialized).not.toMatch(/taxonomyReleaseCode|supersedesEvaluationId|evidence|manifest|observation|mapping|financialNormalization|accessContextId/i);
  }
  const mismatchedContext = await post(alicePage, "/api/evaluation/fit", fitRequest(aliceProfile, intentSetId, fixture, bobEligibility.evalId));
  expect(mismatchedContext.status).toBe(422);
  expect(mismatchedContext.body).toEqual(expect.objectContaining({ error: "INVALID_REQUEST" }));
  const bobAttack = await post(bobPage, "/api/evaluation/fit", fitRequest(aliceProfile, intentSetId, fixture, aliceEligibility.evalId));
  expect(bobAttack.status).toBe(404);
  expect(bobAttack.body).toEqual(expect.objectContaining({ error: "RESOURCE_NOT_FOUND" }));

  const anonymousContext = await browser.newContext();
  const anonymousPage = await anonymousContext.newPage();
  await anonymousPage.goto("/sign-in");
  expect((await post(anonymousPage, "/api/evaluation/eligibility", { profileVersionId: aliceProfile, programVersionId: fixture.programVersionId, operationId: randomUUID() })).status).toBe(401);
  expect((await post(anonymousPage, "/api/intent/document", { intentSetId })).status).toBe(401);
  await anonymousContext.close();

  const expired = await signUp("expired");
  const expiredContext = await browser.newContext();
  const expiredPage = await expiredContext.newPage();
  await signIn(expiredPage, expired);
  database(`delete from auth.users where id = '${expired.id}'::uuid;`);
  expect((await post(expiredPage, "/api/evaluation/eligibility", { profileVersionId: aliceProfile, programVersionId: fixture.programVersionId, operationId: randomUUID() })).status).toBe(401);
  expect((await post(expiredPage, "/api/intent/document", { intentSetId })).status).toBe(401);
  await expiredContext.close();

  const malformedContext = await browser.newContext();
  const authCookies = (await aliceContext.cookies()).filter((cookie) => cookie.name.includes("auth-token"));
  await malformedContext.addCookies(authCookies.map((cookie) => ({ ...cookie, value: "malformed-session" })));
  const malformedPage = await malformedContext.newPage();
  await malformedPage.goto("/sign-in");
  expect((await post(malformedPage, "/api/evaluation/eligibility", { profileVersionId: aliceProfile, programVersionId: fixture.programVersionId, operationId: randomUUID() })).status).toBe(401);
  expect((await post(malformedPage, "/api/intent/document", { intentSetId })).status).toBe(401);
  await malformedContext.close();

  await aliceContext.close();
  await bobContext.close();
  cleanupStudents();
  resetLocalDatabase();
  expect(database("select count(*) from public.program_requirement_rule_sets where rule_set_id = '4b400000-0000-4000-8000-000000000001'::uuid;")).toBe("0");
  expect(database("select count(*) from public.fit_intent_sets;")).toBe("0");
  expect(database("select count(*) from private.fit_intent_product_states_v027;")).toBe("0");
});
