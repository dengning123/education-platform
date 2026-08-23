import { expect, test, type APIRequestContext, type Page } from "@playwright/test";

import { PROFILE_RECOVERY_STORE_KEY } from "../../src/lib/profile/profile-recovery";

const fakeAuthOrigin = "http://127.0.0.1:55431";
const requestId = "00000000-0000-4000-8000-000000000701";

async function signIn(page: Page) {
  await page.goto("/sign-in");
  await page.getByLabel("Email").fill("alice@example.test");
  await page.getByLabel("Password").fill("alice-password-1A");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/account$/);
}

async function openDraft(page: Page) {
  await signIn(page);
  await page.goto("/profile");
  await expect(page.getByTestId("profile-draft-empty")).toBeVisible();
  await page.getByRole("button", { name: "Start Profile draft" }).click();
  await expect(page.getByTestId("profile-draft-core")).toBeVisible();
}

async function reset(request: APIRequestContext) {
  const response = await request.post(`${fakeAuthOrigin}/__test__/reset`);
  expect(response.ok()).toBe(true);
}

async function createSource(page: Page) {
  await page.getByRole("button", { name: "Sources", exact: true }).click();
  await page.getByRole("button", { name: "Add source" }).click();
  await page.getByLabel("Source type").selectOption("SELF_REPORT");
  await page.getByRole("button", { name: "Save source" }).click();
  await expect(page.getByRole("heading", { name: "SELF REPORT" })).toBeVisible();
}

async function acceptUnloadAndReload(page: Page) {
  page.once("dialog", (dialog) => dialog.accept());
  await page.reload();
  await expect(page.getByTestId("profile-draft-core")).toBeVisible();
}

async function recoveryStore(page: Page): Promise<string | null> {
  return page.evaluate((key) => window.sessionStorage.getItem(key), PROFILE_RECOVERY_STORE_KEY);
}

test.beforeEach(async ({ request }) => reset(request));

test("all editable sections use one exact dirty-state discard boundary and successful save clears it", async ({ page }) => {
  await openDraft(page);

  await page.getByRole("button", { name: "Sources", exact: true }).click();
  await page.getByRole("button", { name: "Add source" }).click();
  await page.getByLabel("Locator or reference").fill("not stored in recovery");
  expect(await page.evaluate(() => {
    const event = new Event("beforeunload", { cancelable: true });
    window.dispatchEvent(event);
    return event.defaultPrevented;
  })).toBe(true);
  await page.getByRole("button", { name: "Education", exact: true }).click();
  await expect(page.getByTestId("profile-unsaved-dialog")).toBeVisible();
  await page.getByRole("button", { name: "Keep editing" }).click();
  await expect(page.getByLabel("Locator or reference")).toHaveValue("not stored in recovery");
  expect(await recoveryStore(page)).toBeNull();
  await page.getByRole("button", { name: "Education", exact: true }).click();
  await page.getByTestId("profile-unsaved-dialog").getByRole("button", { name: "Discard changes" }).click();

  await page.getByRole("button", { name: "Sources", exact: true }).click();
  await page.getByRole("button", { name: "Add source" }).click();
  await page.getByRole("button", { name: "Save source" }).click();
  await page.getByRole("button", { name: "Education", exact: true }).click();
  await expect(page.getByTestId("profile-unsaved-dialog")).toHaveCount(0);

  await page.getByRole("button", { name: "Add education" }).click();
  await page.getByLabel("Institution name").fill("浙江大学");
  await page.getByRole("button", { name: "Courses", exact: true }).click();
  await expect(page.getByTestId("profile-unsaved-dialog")).toBeVisible();
  await page.getByTestId("profile-unsaved-dialog").getByRole("button", { name: "Discard changes" }).click();

  await page.getByRole("button", { name: "Add course" }).click();
  await page.getByLabel("Course title").fill("概率论");
  await page.getByRole("button", { name: "Completeness", exact: true }).click();
  await expect(page.getByTestId("profile-unsaved-dialog")).toBeVisible();
  await page.getByTestId("profile-unsaved-dialog").getByRole("button", { name: "Discard changes" }).click();

  const first = page.locator(".completeness-card").first();
  await first.getByRole("radio", { name: /^PARTIAL/ }).check();
  await first.getByLabel("PARTIAL explanation").fill("Still gathering records.");
  await page.getByRole("button", { name: "Overview", exact: true }).click();
  await expect(page.getByTestId("profile-unsaved-dialog")).toBeVisible();
  await page.getByTestId("profile-unsaved-dialog").getByRole("button", { name: "Discard changes" }).click();

  expect(await page.evaluate(() => {
    const event = new Event("beforeunload", { cancelable: true });
    window.dispatchEvent(event);
    return event.defaultPrevented;
  })).toBe(false);
});

test("same-origin navigation and logout require explicit discard before state or session is lost", async ({ page }) => {
  await openDraft(page);
  await createSource(page);
  await page.getByRole("button", { name: "Education", exact: true }).click();
  await page.getByRole("button", { name: "Add education" }).click();
  await page.getByLabel("Institution name").fill("Unsaved University");
  await expect.poll(() => recoveryStore(page)).not.toBeNull();

  await page.getByRole("link", { name: "Education Platform home" }).click();
  await expect(page.getByTestId("profile-unsaved-dialog")).toBeVisible();
  await page.getByRole("button", { name: "Keep editing" }).click();
  await expect(page).toHaveURL(/\/profile$/);
  await expect(page.getByLabel("Institution name")).toHaveValue("Unsaved University");

  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page.getByTestId("profile-unsaved-dialog")).toBeVisible();
  await page.getByRole("button", { name: "Keep editing" }).click();
  await expect(page).toHaveURL(/\/profile$/);

  await page.getByRole("button", { name: "Sign out" }).click();
  await page.getByRole("button", { name: "Discard changes" }).click();
  await expect(page).toHaveURL(/\/sign-in$/);
  expect(await recoveryStore(page)).toBeNull();
});

for (const failure of [
  { name: "save failure", status: 500, error: "INTERNAL_ERROR" },
  { name: "operation conflict", status: 409, error: "PROFILE_OPERATION_CONFLICT" },
  { name: "ambiguous timeout", status: 504, error: "REQUEST_TIMEOUT" },
] as const) {
  test(`${failure.name} preserves local dirty state`, async ({ page }) => {
    await openDraft(page);
    await page.getByRole("button", { name: "Sources", exact: true }).click();
    await page.getByRole("button", { name: "Add source" }).click();
    await page.getByLabel("Locator or reference").fill(`unsaved-${failure.error}`);
    await page.route("**/api/profile/mutate", (route) => route.fulfill({
      status: failure.status,
      contentType: "application/json",
      body: JSON.stringify({ error: failure.error, requestId, message: "Closed public test message." }),
    }));
    await page.getByRole("button", { name: "Save source" }).click();
    await expect(page.getByLabel("Locator or reference")).toHaveValue(`unsaved-${failure.error}`);
    await page.getByRole("button", { name: "Education", exact: true }).click();
    await expect(page.getByTestId("profile-unsaved-dialog")).toBeVisible();
  });
}

test("Education recovery is explicit, minimized, never auto-submits, and clears after authoritative save", async ({ page }) => {
  const mutations: string[] = [];
  page.on("request", (request) => {
    if (/\/api\/profile\/mutate/.test(request.url())) mutations.push(request.postData() ?? "");
  });
  await openDraft(page);
  await createSource(page);
  const mutationsBeforeRecovery = mutations.length;
  await page.getByRole("button", { name: "Education", exact: true }).click();
  await page.getByRole("button", { name: "Add education" }).click();
  await page.getByLabel("Institution name").fill("浙江大学");
  await page.getByLabel("Degree name").fill("工学学士");
  await page.getByLabel("GPA value").fill("85");
  await page.getByLabel("GPA scale").fill("100");
  await expect.poll(() => recoveryStore(page)).not.toBeNull();
  const serialized = await recoveryStore(page) ?? "";
  expect(serialized).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i);
  for (const forbidden of ["locator", "evidenceId", "studentId", "authUserId", "access_token", "refresh_token", "cookie"]) {
    expect(serialized.toLowerCase()).not.toContain(forbidden.toLowerCase());
  }
  expect(mutations).toHaveLength(mutationsBeforeRecovery);

  await acceptUnloadAndReload(page);
  await page.getByRole("button", { name: "Education", exact: true }).click();
  await page.getByRole("button", { name: "Add education" }).click();
  await expect(page.getByTestId("profile-recovery-prompt")).toBeVisible();
  await expect(page.getByLabel("Institution name")).toHaveValue("");
  expect(mutations).toHaveLength(mutationsBeforeRecovery);
  await page.getByRole("button", { name: "Restore local draft" }).click();
  await expect(page.getByLabel("Institution name")).toHaveValue("浙江大学");
  await expect(page.getByLabel("Degree name")).toHaveValue("工学学士");
  expect(mutations).toHaveLength(mutationsBeforeRecovery);
  await page.getByRole("button", { name: "Save education" }).click();
  await expect(page.getByRole("heading", { name: "浙江大学" })).toBeVisible();
  await expect.poll(() => recoveryStore(page)).toContain("\"entries\":[]");
});

test("Course recovery is explicit and discarding it clears the local record", async ({ page }) => {
  await openDraft(page);
  await createSource(page);
  await page.getByRole("button", { name: "Courses", exact: true }).click();
  await page.getByRole("button", { name: "Add course" }).click();
  await page.getByLabel("Course code").fill("MATH-201");
  await page.getByLabel("Course title").fill("概率论与数理统计");
  await expect.poll(() => recoveryStore(page)).not.toBeNull();
  await acceptUnloadAndReload(page);
  await page.getByRole("button", { name: "Courses", exact: true }).click();
  await page.getByRole("button", { name: "Add course" }).click();
  await expect(page.getByTestId("profile-recovery-prompt")).toBeVisible();
  await page.getByRole("button", { name: "Discard local draft" }).click();
  await expect(page.getByLabel("Course title")).toHaveValue("");
  await expect.poll(() => recoveryStore(page)).toContain("\"entries\":[]");
});

test("Completeness recovery requires explicit restore and warns when the authoritative revision changed", async ({ page, request }) => {
  await openDraft(page);
  await page.getByRole("button", { name: "Completeness", exact: true }).click();
  const first = page.locator(".completeness-card").first();
  await first.getByRole("radio", { name: /^PARTIAL/ }).check();
  await first.getByLabel("PARTIAL explanation").fill("Still collecting official records.");
  await expect.poll(() => recoveryStore(page)).not.toBeNull();
  const bumped = await request.post(`${fakeAuthOrigin}/__test__/bump-profile-revision`, { data: { email: "alice@example.test" } });
  expect(bumped.ok()).toBe(true);
  await acceptUnloadAndReload(page);
  await page.getByRole("button", { name: "Completeness", exact: true }).click();
  const prompt = page.getByTestId("profile-recovery-prompt");
  await expect(prompt).toContainText("authoritative Profile revision has changed");
  await expect(first.getByLabel("UNKNOWN explanation")).toHaveValue("");
  await prompt.getByRole("button", { name: "Restore local draft" }).click();
  await expect(first.getByLabel("PARTIAL explanation")).toHaveValue("Still collecting official records.");
});
