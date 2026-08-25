import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";

import { expect, test, type Page } from "@playwright/test";

type LocalUser = Readonly<{ id: string; email: string; password: string }>;
type ProfileResponse = Readonly<{ status: number; body: Record<string, unknown> }>;
type FrozenDiscovery = Readonly<{ profileVersionId: string }>;
type ProfileDocumentFixture = Readonly<{
  profileVersionId: string;
  revision: number;
  status: "DRAFT" | "FROZEN";
  evidenceItems: readonly Readonly<{ evidenceId: string }>[];
  readiness: Readonly<{ freezeReady: boolean }>;
}>;

const userIds: string[] = [];

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

function database(sql: string): string {
  const container = process.env.PHASE025_DB_CONTAINER;
  if (!container || !/^supabase_db_[A-Za-z0-9_.-]+$/.test(container)) throw new Error("Exact disposable PHASE025_DB_CONTAINER is required");
  const result = spawnSync(process.env.DOCKER_BIN ?? "docker", [
    "exec", container, "psql", "-U", "postgres", "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql,
  ], { encoding: "utf8" });
  if (result.status !== 0) throw new Error("Disposable local database command failed");
  return result.stdout.trim();
}

async function signUp(label: string): Promise<LocalUser> {
  const user = {
    id: "",
    email: `phase025-browser-${label}-${randomUUID()}@test.invalid`,
    password: `Phase025-${randomUUID()}-Aa1!`,
  };
  const response = await fetch(new URL("/auth/v1/signup", apiUrl), {
    method: "POST",
    headers: { apikey: status.ANON_KEY, "content-type": "application/json" },
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

async function profilePost(page: Page, capability: string, body: unknown): Promise<ProfileResponse> {
  return page.evaluate(async ({ capability: path, body: payload }) => {
    const response = await fetch(`/api/profile/${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });
    const responseBody: unknown = await response.json();
    if (responseBody === null || typeof responseBody !== "object" || Array.isArray(responseBody)) {
      throw new Error("Profile response was not an object");
    }
    return { status: response.status, body: responseBody as Record<string, unknown> };
  }, { capability, body });
}

function responseData<T>(response: ProfileResponse): T {
  if (!("data" in response.body)) throw new Error("Profile response did not contain data");
  return response.body.data as T;
}

async function createFrozenProfile(page: Page, withSource: boolean) {
  await page.goto("/profile");
  await expect(page.getByTestId("profile-draft-empty")).toBeVisible();
  await page.getByRole("button", { name: "Start Profile draft" }).click();
  await expect(page.getByTestId("profile-draft-core")).toBeVisible();

  let document = responseData<ProfileDocumentFixture>(await profilePost(page, "document", {}));
  if (withSource) {
    const result = await profilePost(page, "mutate", {
      profileVersionId: document.profileVersionId,
      operationId: randomUUID(),
      expectedRevision: document.revision,
      command: "EVIDENCE_CREATE",
      payload: { evidenceType: "SELF_REPORT", locator: "Alice lifecycle source", contentHash: null, observedAt: "2026-08-25T12:00:00Z" },
    });
    expect(result.status).toBe(200);
    document = responseData<ProfileDocumentFixture>(await profilePost(page, "document", {}));
  }

  for (const domain of ["EDUCATION_HISTORY", "COURSE_HISTORY", "COURSE_MAPPING", "TEST_HISTORY", "EXPERIENCE_HISTORY", "SKILL_HISTORY", "PREFERENCES", "GOALS"]) {
    const result = await profilePost(page, "mutate", {
      profileVersionId: document.profileVersionId,
      operationId: randomUUID(),
      expectedRevision: document.revision,
      command: "COMPLETENESS_UPSERT",
      payload: { educationContextId: null, domain, completeness: "COMPLETE", explanation: null },
    });
    expect(result.status).toBe(200);
    document = responseData<ProfileDocumentFixture>(await profilePost(page, "document", {}));
  }
  expect(document.readiness.freezeReady).toBe(true);
  await page.reload();
  await page.getByRole("button", { name: "Review & Freeze", exact: true }).click();
  await page.getByLabel(/I understand that this exact version becomes immutable/).check();
  await page.getByRole("button", { name: "Freeze this Profile version" }).click();
  await expect(page.getByTestId("profile-frozen-view")).toBeVisible();
  const discovery = await profilePost(page, "latest-frozen", {});
  expect(discovery.status).toBe(200);
  return responseData<FrozenDiscovery>(discovery);
}

function cleanup() {
  const ids = userIds.filter((value) => /^[0-9a-f-]{36}$/i.test(value));
  if (ids.length === 0) return;
  const list = ids.map((value) => `'${value}'::uuid`).join(",");
  database(`
    do $cleanup$
    declare v_student_id uuid;
    begin
      for v_student_id in select student_id from private.student_identities where auth_user_id in (${list})
      loop
        perform public.delete_student_data(v_student_id, 'PHASE025_REAL_BROWSER_E2E_CLEANUP');
      end loop;
      delete from auth.users where id in (${list});
    end
    $cleanup$;
  `);
  const residue = database(`select (select count(*) from auth.users where id in (${list})) + (select count(*) from private.student_identities where auth_user_id in (${list}));`);
  if (residue !== "0") throw new Error("Real-local browser fixture residue remains");
  userIds.length = 0;
}

test.afterAll(() => cleanup());

test("complete Profile lifecycle remains owner-scoped through the real local stack", async ({ browser }) => {
  const alice = await signUp("alice");
  const bob = await signUp("bob");
  const aliceContext = await browser.newContext();
  const bobContext = await browser.newContext();
  const alicePage = await aliceContext.newPage();
  const bobPage = await bobContext.newPage();

  await signIn(alicePage, alice);
  const aliceFrozen = await createFrozenProfile(alicePage, true);
  const aliceSourceBefore = responseData<ProfileDocumentFixture>(await profilePost(alicePage, "known-document", { profileVersionId: aliceFrozen.profileVersionId }));
  await alicePage.getByRole("button", { name: "Sign out" }).click();
  await expect(alicePage).toHaveURL(/\/sign-in$/);
  await signIn(alicePage, alice);
  await alicePage.goto("/profile");
  await expect(alicePage.getByTestId("profile-frozen-view")).toBeVisible();
  await expect(alicePage.getByRole("heading", { name: "Frozen v1" })).toBeVisible();
  await expect(alicePage.getByText("Alice lifecycle source")).toBeVisible();

  await signIn(bobPage, bob);
  const bobFrozen = await createFrozenProfile(bobPage, false);
  for (const [page, foreign] of [[alicePage, bobFrozen.profileVersionId], [bobPage, aliceFrozen.profileVersionId]] as const) {
    const read = await profilePost(page, "known-document", { profileVersionId: foreign });
    const fork = await profilePost(page, "fork", { sourceProfileVersionId: foreign, operationId: randomUUID() });
    expect(read.status).toBe(404);
    expect(fork.status).toBe(404);
    expect(read.body).toMatchObject({ error: "RESOURCE_NOT_FOUND" });
    expect(fork.body).toMatchObject({ error: "RESOURCE_NOT_FOUND" });
  }
  expect(responseData<FrozenDiscovery>(await profilePost(alicePage, "latest-frozen", {})).profileVersionId).toBe(aliceFrozen.profileVersionId);
  expect(responseData<FrozenDiscovery>(await profilePost(bobPage, "latest-frozen", {})).profileVersionId).toBe(bobFrozen.profileVersionId);

  const anonymousContext = await browser.newContext();
  const anonymousPage = await anonymousContext.newPage();
  await anonymousPage.goto("/sign-in");
  expect((await profilePost(anonymousPage, "latest-frozen", {})).status).toBe(401);
  await anonymousContext.close();

  const expiredUser = await signUp("expired");
  const expiredContext = await browser.newContext();
  const expiredPage = await expiredContext.newPage();
  await signIn(expiredPage, expiredUser);
  database(`delete from auth.users where id = '${expiredUser.id}'::uuid;`);
  expect((await profilePost(expiredPage, "latest-frozen", {})).status).toBe(401);
  await expiredContext.close();

  const malformedContext = await browser.newContext();
  const authCookies = (await aliceContext.cookies()).filter((cookie) => cookie.name.includes("auth-token"));
  expect(authCookies.length).toBeGreaterThan(0);
  await malformedContext.addCookies(authCookies.map((cookie) => ({ ...cookie, value: "malformed-session" })));
  const malformedPage = await malformedContext.newPage();
  await malformedPage.goto("/sign-in");
  expect((await profilePost(malformedPage, "latest-frozen", {})).status).toBe(401);
  await malformedContext.close();

  await alicePage.getByRole("button", { name: "Create new draft from this version" }).click();
  await expect(alicePage.getByTestId("profile-draft-core")).toBeVisible();
  await expect(alicePage.getByText("Draft v2")).toBeVisible();
  let newDraft = responseData<ProfileDocumentFixture>(await profilePost(alicePage, "document", {}));
  expect(newDraft.status).toBe("DRAFT");
  expect(newDraft.evidenceItems).toHaveLength(1);
  expect(newDraft.evidenceItems[0].evidenceId).not.toBe(aliceSourceBefore.evidenceItems[0].evidenceId);
  const continued = await profilePost(alicePage, "mutate", {
    profileVersionId: newDraft.profileVersionId,
    operationId: randomUUID(),
    expectedRevision: newDraft.revision,
    command: "EVIDENCE_CREATE",
    payload: { evidenceType: "SELF_REPORT", locator: "Post-fork authoritative edit", contentHash: null, observedAt: "2026-08-25T13:00:00Z" },
  });
  expect(continued.status).toBe(200);
  newDraft = responseData<ProfileDocumentFixture>(await profilePost(alicePage, "document", {}));
  expect(newDraft.evidenceItems).toHaveLength(2);
  const aliceSourceAfter = responseData<ProfileDocumentFixture>(await profilePost(alicePage, "known-document", { profileVersionId: aliceFrozen.profileVersionId }));
  expect(aliceSourceAfter).toEqual(aliceSourceBefore);

  await aliceContext.close();
  await bobContext.close();
  cleanup();
});
