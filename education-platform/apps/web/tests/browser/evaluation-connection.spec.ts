import { expect, test, type Page } from "@playwright/test";

const fakeAuthOrigin = "http://127.0.0.1:55431";
const requestId = "00000000-0000-4000-8000-000000000881";
const profileVersionId = "00000000-0000-4000-8000-000000000882";
const programVersionId = "00000000-0000-4000-8000-000000000883";
const operationId = "00000000-0000-4000-8000-000000000885";

async function signIn(page: Page) {
  await page.goto("/sign-in");
  await page.getByLabel("Email").fill("alice@example.test");
  await page.getByLabel("Password").fill("alice-password-1A");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/account$/);
}

async function evaluationPost(page: Page, capability: string, body: unknown) {
  return page.evaluate(async ({ capability: path, body: payload }) => {
    const response = await fetch(`/api/evaluation/${path}`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(payload),
    });
    return { status: response.status, body: await response.json(), requestId: response.headers.get("x-request-id") };
  }, { capability, body });
}

test.beforeEach(async ({ request }) => {
  const response = await request.post(`${fakeAuthOrigin}/__test__/reset`);
  expect(response.ok()).toBe(true);
});

test("anonymous and expired evaluation calls fail closed at the same-origin boundary", async ({ page, request }) => {
  await page.goto("/sign-in");
  const anonymous = await evaluationPost(page, "eligibility", { profileVersionId, programVersionId, operationId });
  expect(anonymous.status).toBe(401);
  expect(anonymous.body).toEqual(expect.objectContaining({ error: "AUTH_REQUIRED" }));
  expect(anonymous.requestId).toBe(anonymous.body.requestId);

  await signIn(page);
  const revoked = await request.post(`${fakeAuthOrigin}/__test__/revoke`, { data: { email: "alice@example.test" } });
  expect(revoked.ok()).toBe(true);
  const expired = await evaluationPost(page, "eligibility", { profileVersionId, programVersionId, operationId });
  expect(expired.status).toBe(401);
  expect(expired.body).toEqual(expect.objectContaining({ error: "AUTH_REQUIRED" }));
});

test("browser invocation reaches only the same-origin evaluation route with closed DTOs", async ({ page }) => {
  const requests: { url: string; body: string | null }[] = [];
  page.on("request", (request) => requests.push({ url: request.url(), body: request.postData() }));
  await signIn(page);

  await page.route("**/api/evaluation/eligibility", (route) => route.fulfill({
    status: 200,
    headers: { "content-type": "application/json", "x-request-id": requestId },
    body: JSON.stringify({
      requestId,
      data: {
        schemaVersion: "ELIGIBILITY_PRODUCTION_ASSEMBLY_V026", evalId: "00000000-0000-4000-8000-000000000884",
        profileId: profileVersionId, programId: programVersionId, status: "UNKNOWN", rootTruth: "UNKNOWN", requirements: [],
        inputFingerprint: "a".repeat(64), resultFingerprint: "b".repeat(64),
      },
    }),
  }));
  const eligibility = await evaluationPost(page, "eligibility", { profileVersionId, programVersionId, operationId });
  expect(eligibility.status).toBe(200);
  expect(eligibility.body.data.schemaVersion).toBe("ELIGIBILITY_PRODUCTION_ASSEMBLY_V026");
  expect(eligibility.requestId).toBe(requestId);

  expect(requests.some((request) => /\/api\/evaluation\/eligibility/.test(request.url))).toBe(true);
  expect(requests.some((request) => /\/(?:rest|functions)\/v1\//.test(request.url))).toBe(false);
  const evaluationBodies = requests.filter((request) => /\/api\/evaluation\//.test(request.url)).map((request) => request.body ?? "").join("\n");
  expect(evaluationBodies).not.toContain("studentId");
  expect(evaluationBodies).not.toContain("trustedSubject");
  expect(evaluationBodies).not.toContain("service_role");
});

test("authenticated browser requests cannot inject student authority or evaluator identity", async ({ page }) => {
  await signIn(page);
  for (const injected of [
    { profileVersionId, programVersionId, operationId, studentId: "00000000-0000-4000-8000-000000000889" },
    { profileVersionId, programVersionId, operationId, evaluatorBuild: "caller-controlled" },
  ]) {
    const response = await evaluationPost(page, "eligibility", injected);
    expect(response.status).toBe(422);
    expect(response.body).toEqual(expect.objectContaining({ error: "INVALID_REQUEST" }));
    expect(JSON.stringify(response.body)).not.toMatch(/SQLSTATE|constraint|detail|hint|stack|cause/i);
  }
});
