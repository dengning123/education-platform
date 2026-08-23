import { expect, test, type Page } from "@playwright/test";

const fakeAuthOrigin = "http://127.0.0.1:55431";
const serviceRoleSentinel = "phase4b1a-service-role-must-stay-server-only";
const managementSentinel = "phase4b1a-management-token-must-stay-server-only";

async function signIn(page: Page, email: string, password: string) {
  await page.goto("/sign-in");
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/account$/);
  await expect(page.getByTestId("auth-status")).toHaveText("Authenticated");
}

async function profilePost(page: Page, capability: string, body: unknown) {
  return page.evaluate(async ({ capability: path, body: payload }) => {
    const response = await fetch(`/api/profile/${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });
    return { status: response.status, body: await response.json(), requestId: response.headers.get("x-request-id") };
  }, { capability, body });
}

test.beforeEach(async ({ request }) => {
  const response = await request.post(`${fakeAuthOrigin}/__test__/reset`);
  expect(response.ok()).toBe(true);
});

test("anonymous users cannot enter the protected account route", async ({ page }) => {
  await page.goto("/account");
  await expect(page).toHaveURL(/\/sign-in\?next=%2Faccount$/);
  await expect(page.getByTestId("sign-in-form")).toBeVisible();
});

test("an authenticated session is restored across a protected-page reload", async ({ page }) => {
  await signIn(page, "alice@example.test", "alice-password-1A");
  await expect(page.getByTestId("account-email")).toHaveText("alice@example.test");

  await page.reload();
  await expect(page).toHaveURL(/\/account$/);
  await expect(page.getByTestId("account-email")).toHaveText("alice@example.test");
});

test("logout removes protected-route access", async ({ page }) => {
  await signIn(page, "alice@example.test", "alice-password-1A");
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/sign-in$/);

  await page.goto("/account");
  await expect(page).toHaveURL(/\/sign-in\?next=%2Faccount$/);
});

test("an invalidated session returns to the safe sign-in state", async ({ page, request }) => {
  await signIn(page, "alice@example.test", "alice-password-1A");
  const revoked = await request.post(`${fakeAuthOrigin}/__test__/revoke`, {
    data: { email: "alice@example.test" },
  });
  expect(revoked.ok()).toBe(true);

  await page.reload();
  await expect(page).toHaveURL(/\/sign-in\?next=%2Faccount$/);
  await expect(page.getByTestId("sign-in-form")).toBeVisible();
});

test("an unrelated authenticated user receives identity state only and no product data access", async ({ browser }) => {
  const aliceContext = await browser.newContext();
  const alicePage = await aliceContext.newPage();
  await signIn(alicePage, "alice@example.test", "alice-password-1A");

  const bobContext = await browser.newContext();
  const bobPage = await bobContext.newPage();
  const bobRequests: string[] = [];
  bobPage.on("request", (request) => bobRequests.push(request.url()));
  await signIn(bobPage, "bob@example.test", "bob-password-1A");

  await expect(bobPage.getByTestId("account-email")).toHaveText("bob@example.test");
  await expect(bobPage.getByText("alice@example.test")).toHaveCount(0);
  await expect(bobPage.getByTestId("authorization-boundary")).toContainText(
    "it grants no database privileges",
  );
  expect(bobRequests.some((url) => /\/(?:rest|functions)\/v1\//.test(url))).toBe(false);

  await aliceContext.close();
  await bobContext.close();
});

test("client assets and browser requests contain no high-privilege secret", async ({ page, request }) => {
  const browserTraffic: string[] = [];
  page.on("request", async (browserRequest) => {
    browserTraffic.push(JSON.stringify({
      url: browserRequest.url(),
      headers: await browserRequest.allHeaders(),
      postData: browserRequest.postData(),
    }));
  });

  await page.goto("/sign-in");
  const scripts = await page.locator("script[src]").evaluateAll((nodes) =>
    nodes.map((node) => (node as HTMLScriptElement).src),
  );
  const scriptBodies = await Promise.all(scripts.map(async (url) => (await request.get(url)).text()));
  const inspected = [...browserTraffic, ...scriptBodies].join("\n");

  expect(inspected).not.toContain(serviceRoleSentinel);
  expect(inspected).not.toContain(managementSentinel);
  expect(browserTraffic.some((entry) => /\/functions\/v1\//.test(entry))).toBe(false);
});

test("dependency auth errors are mapped to a closed public message", async ({ page }) => {
  await page.goto("/sign-in");
  await page.getByLabel("Email").fill("alice@example.test");
  await page.getByLabel("Password").fill("incorrect-password");
  await page.getByRole("button", { name: "Sign in" }).click();

  await expect(page.getByTestId("auth-error")).toHaveText(
    "We could not sign you in. Check your credentials and try again.",
  );
  await expect(page.getByText("Internal fake dependency detail")).toHaveCount(0);
});

test("an authenticated Profile draft reaches only the same-origin Next boundary", async ({ page }) => {
  const requests: string[] = [];
  page.on("request", (request) => requests.push(request.url()));
  await signIn(page, "alice@example.test", "alice-password-1A");
  await page.goto("/profile");
  await expect(page.getByTestId("profile-draft-empty")).toBeVisible();
  await page.getByRole("button", { name: "Start Profile draft" }).click();
  await expect(page.getByTestId("profile-draft-core")).toBeVisible();
  await expect(page.getByTestId("profile-live-status")).toContainText("Request ID:");

  expect(requests.some((url) => /\/api\/profile\//.test(url))).toBe(true);
  expect(requests.some((url) => /\/rest\/v1\/rpc\//.test(url))).toBe(false);
  expect(requests.some((url) => /\/functions\/v1\//.test(url))).toBe(false);
});

test("anonymous and expired sessions receive closed Profile access", async ({ page, request }) => {
  await page.goto("/profile");
  await expect(page).toHaveURL(/\/sign-in\?next=%2Fprofile$/);

  const anonymous = await profilePost(page, "bootstrap", {});
  expect(anonymous.status).toBe(401);
  expect(anonymous.body).toMatchObject({ error: "AUTH_REQUIRED" });
  expect(anonymous.requestId).toBe(anonymous.body.requestId);

  await signIn(page, "alice@example.test", "alice-password-1A");
  const revoked = await request.post(`${fakeAuthOrigin}/__test__/revoke`, { data: { email: "alice@example.test" } });
  expect(revoked.ok()).toBe(true);
  const expired = await profilePost(page, "bootstrap", {});
  expect(expired.status).toBe(401);
  expect(expired.body).toEqual(expect.objectContaining({ error: "AUTH_REQUIRED" }));
});

test("logout closes the protected Profile shell", async ({ page }) => {
  await signIn(page, "alice@example.test", "alice-password-1A");
  await page.goto("/profile");
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/sign-in$/);
  await page.goto("/profile");
  await expect(page).toHaveURL(/\/sign-in\?next=%2Fprofile$/);
});

test("an unrelated session cannot read another owner's Profile through the Next boundary", async ({ browser }) => {
  const aliceContext = await browser.newContext();
  const alice = await aliceContext.newPage();
  await signIn(alice, "alice@example.test", "alice-password-1A");
  const created = await profilePost(alice, "draft", { operationId: "00000000-0000-4000-8000-000000000201" });
  expect(created.status).toBe(200);
  const aliceProfileId = created.body.data.profileVersionId as string;

  const bobContext = await browser.newContext();
  const bob = await bobContext.newPage();
  await signIn(bob, "bob@example.test", "bob-password-1A");
  const unrelated = await profilePost(bob, "readiness", { profileVersionId: aliceProfileId });
  expect(unrelated.status).toBe(404);
  expect(unrelated.body).toEqual(expect.objectContaining({ error: "RESOURCE_NOT_FOUND" }));
  expect(JSON.stringify(unrelated.body)).not.toContain("Internal fake PostgREST detail");
  expect(JSON.stringify(unrelated.body)).not.toContain("Internal fake hint");

  await aliceContext.close();
  await bobContext.close();
});
