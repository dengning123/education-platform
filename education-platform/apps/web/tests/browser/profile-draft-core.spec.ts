import { expect, test, type APIRequestContext, type Page } from "@playwright/test";

import { PROFILE_RECOVERY_CONTEXT_KEY, PROFILE_RECOVERY_STORE_KEY } from "../../src/lib/profile/profile-recovery";

const fakeAuthOrigin = "http://127.0.0.1:55431";

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

test.beforeEach(async ({ request }) => reset(request));

test("student completes the narrow source, education, course, declaration, and immediate freeze flow", async ({ page }) => {
  const browserRequests: { url: string; body: string | null }[] = [];
  page.on("request", (request) => browserRequests.push({ url: request.url(), body: request.postData() }));
  await openDraft(page);

  await page.getByRole("button", { name: "Sources", exact: true }).click();
  await page.getByRole("button", { name: "Add source" }).click();
  await page.getByLabel("Source type").selectOption("TRANSCRIPT");
  await page.getByLabel("Locator or reference").fill("本科成绩单原件");
  await page.getByRole("button", { name: "Save source" }).click();
  await expect(page.getByRole("heading", { name: "TRANSCRIPT" })).toBeVisible();
  await expect(page.getByText("Information referenced from a transcript source.")).toBeVisible();
  await expect(page.getByText("Officially verified")).toHaveCount(0);

  await page.getByRole("button", { name: "Education", exact: true }).click();
  await page.getByRole("button", { name: "Add education" }).click();
  await page.getByLabel("Institution name").fill("浙江大学");
  await page.getByLabel("Degree name").fill("工学学士");
  await page.getByLabel("Degree status").selectOption("COMPLETED");
  await page.getByLabel("Country code").fill("CN");
  await page.getByLabel("GPA value").fill("85");
  await page.getByLabel("GPA scale").fill("100");
  await page.getByRole("button", { name: "Save education" }).click();
  await expect(page.getByRole("heading", { name: "浙江大学" })).toBeVisible();
  await expect(page.getByText("85 / 100")).toBeVisible();
  await expect(page.getByLabel(/major/i)).toHaveCount(0);

  await page.getByRole("button", { name: "Courses", exact: true }).click();
  await page.getByRole("button", { name: "Add course" }).click();
  await page.getByLabel("Course code").fill("MATH-201");
  await page.getByLabel("Course title").fill("概率论与数理统计");
  await page.getByLabel("Term").fill("2024 秋");
  await page.getByLabel("Credits as shown").fill("4");
  await page.getByLabel("Numeric grade value").fill("92");
  await page.getByLabel("Numeric grade scale").fill("100");
  await page.getByLabel("Grade text").fill("优秀");
  await page.getByRole("button", { name: "Save course" }).click();
  await expect(page.getByRole("heading", { name: "概率论与数理统计" })).toBeVisible();
  await expect(page.getByText("92 / 100 · 优秀")).toBeVisible();
  await expect(page.getByText(/U\.S\. semester credits/)).toHaveCount(0);

  await page.getByRole("button", { name: "Overview", exact: true }).click();
  const counts = page.getByTestId("profile-record-counts");
  await expect(counts).toContainText("1");
  await expect(counts).not.toContainText("%");

  await page.getByRole("button", { name: "Completeness", exact: true }).click();
  const cards = page.locator(".completeness-card");
  await expect(cards).toHaveCount(8);
  const count = await cards.count();
  for (let index = 0; index < count; index += 1) {
    const card = cards.nth(index);
    const domain = (await card.getByRole("heading", { level: 3 }).textContent()) ?? "";
    const value = domain === "Education history" ? "COMPLETE" : domain === "Course history" ? "PARTIAL" : "UNKNOWN";
    await card.getByRole("radio", { name: new RegExp(`^${value}`) }).check();
    if (value !== "COMPLETE") await card.getByLabel(`${value} explanation`).fill(value === "PARTIAL" ? "Additional course records may be added later." : "I cannot currently confirm this scope.");
    await card.getByRole("button", { name: "Save declaration" }).click();
    await expect(card).toHaveAttribute("data-completeness", value);
  }

  await page.getByRole("button", { name: "Review & Freeze", exact: true }).click();
  await expect(page.getByText(/1 scope is PARTIAL/)).toBeVisible();
  await expect(page.getByText(/scope.*UNKNOWN/).first()).toBeVisible();
  await expect(page.getByText("required declaration is missing")).toHaveCount(0);
  await page.getByLabel(/I understand that this exact version becomes immutable/).check();
  const freeze = page.getByRole("button", { name: "Freeze this Profile version" });
  await expect(freeze).toBeEnabled();
  await freeze.click();
  await expect(page.getByTestId("profile-frozen-view")).toBeVisible();
  await expect(page.getByRole("heading", { name: "Frozen v1" })).toBeVisible();
  await expect(page.getByRole("button", { name: /Edit|Add|Save/ })).toHaveCount(0);
  await expect(page.getByText(/Historical frozen-version discovery is not available/)).toBeVisible();
  expect(await page.evaluate(([storeKey, contextKey]) => ({
    store: window.sessionStorage.getItem(storeKey),
    context: window.sessionStorage.getItem(contextKey),
  }), [PROFILE_RECOVERY_STORE_KEY, PROFILE_RECOVERY_CONTEXT_KEY])).toEqual({ store: null, context: null });
  expect(await page.evaluate(() => {
    const event = new Event("beforeunload", { cancelable: true });
    window.dispatchEvent(event);
    return event.defaultPrevented;
  })).toBe(false);

  const profileApiBodies = browserRequests.filter((entry) => /\/api\/profile\//.test(entry.url)).map((entry) => entry.body ?? "");
  expect(profileApiBodies.some((body) => body.includes('"command":"DEGREE_CREATE"'))).toBe(true);
  expect(profileApiBodies.some((body) => body.includes('"command":"COURSE_CREATE"'))).toBe(true);
  expect(profileApiBodies.join("\n")).not.toContain("studentId");
  expect(browserRequests.some((entry) => /\/(?:rest|functions)\/v1\//.test(entry.url))).toBe(false);
});

test("mapping readiness renders only owner-scoped projected labels and marks historical concepts", async ({ page, request }) => {
  await openDraft(page);
  const seeded = await request.post(`${fakeAuthOrigin}/__test__/seed-taxonomy-readiness`, {
    data: { email: "alice@example.test" },
  });
  expect(seeded.ok()).toBe(true);
  const fixture = await seeded.json() as Readonly<{
    historicalConceptId: string;
    activeConceptId: string;
    unrelatedConceptId: string;
  }>;

  await page.reload();
  await expect(page.getByTestId("profile-draft-core")).toBeVisible();

  await page.getByRole("button", { name: "Education", exact: true }).click();
  await expect(page.getByText("Economics · FIELD · Historical at v0.2", { exact: true })).toBeVisible();
  await expect(page.getByText(/Mapping readiness: PROPOSED/)).toBeVisible();

  await page.getByRole("button", { name: "Courses", exact: true }).click();
  await expect(page.getByText("Calculus · COURSE_CONCEPT", { exact: true })).toBeVisible();
  await expect(page.getByText(/Mapping readiness: VERIFIED/)).toBeVisible();

  await page.getByRole("button", { name: "Review & Freeze", exact: true }).click();
  const readiness = page.getByTestId("profile-mapping-readiness");
  await expect(readiness.getByText("Economics · FIELD · Historical at v0.2", { exact: true })).toBeVisible();
  await expect(readiness.getByText("Calculus · COURSE_CONCEPT", { exact: true })).toBeVisible();
  await expect(readiness.locator(".profile-status-pill.status-proposed")).toContainText("PROPOSED");
  await expect(readiness.locator(".profile-status-pill.status-verified")).toContainText("VERIFIED");
  await expect(readiness.getByText("Econometrics", { exact: true })).toHaveCount(0);
  await expect(page.getByRole("searchbox")).toHaveCount(0);
  await expect(page.getByRole("button", { name: /select taxonomy|search taxonomy/i })).toHaveCount(0);

  const body = await page.locator("body").innerText();
  expect(body).not.toContain(fixture.historicalConceptId);
  expect(body).not.toContain(fixture.activeConceptId);
  expect(body).not.toContain(fixture.unrelatedConceptId);
});

test("stale revision preserves the local form and requires explicit reconfirmation", async ({ page, request }) => {
  await openDraft(page);
  await page.getByRole("button", { name: "Sources", exact: true }).click();
  await page.getByRole("button", { name: "Add source" }).click();
  await page.getByLabel("Source type").selectOption("SELF_REPORT");
  await page.getByLabel("Locator or reference").fill("本地未提交来源");

  const bumped = await request.post(`${fakeAuthOrigin}/__test__/bump-profile-revision`, { data: { email: "alice@example.test" } });
  expect(bumped.ok()).toBe(true);
  await page.getByRole("button", { name: "Save source" }).click();

  await expect(page.getByText("Review the latest version before saving again.", { exact: true })).toBeVisible();
  await expect(page.getByLabel("Locator or reference")).toHaveValue("本地未提交来源");
  await page.getByRole("button", { name: /Confirm against revision/ }).click();
  await expect(page.getByRole("heading", { name: "SELF REPORT" })).toBeVisible();
  await expect(page.getByText("本地未提交来源")).toBeVisible();
});

test("missing declarations alone disable UI freeze while PARTIAL and UNKNOWN remain non-failure states", async ({ page }) => {
  await openDraft(page);
  await page.getByRole("button", { name: "Review & Freeze", exact: true }).click();
  await expect(page.getByRole("button", { name: "Freeze this Profile version" })).toBeDisabled();
  await expect(page.getByText(/required declarations are missing/)).toBeVisible();

  await page.getByRole("button", { name: "Completeness", exact: true }).click();
  const first = page.locator(".completeness-card").first();
  await first.getByRole("radio", { name: /^PARTIAL/ }).check();
  await first.getByLabel("PARTIAL explanation").fill("Some information is still being collected.");
  await first.getByRole("button", { name: "Save declaration" }).click();
  await expect(first).toHaveAttribute("data-completeness", "PARTIAL");
  await expect(first.getByText(/not complete/)).toBeVisible();
});

test("mobile layout accepts long Chinese text, keeps keyboard focus visible, and avoids horizontal overflow", async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await openDraft(page);
  await page.getByRole("button", { name: "Sources", exact: true }).focus();
  await expect(page.getByRole("button", { name: "Sources", exact: true })).toBeFocused();
  const targetHeight = await page.getByRole("button", { name: "Sources", exact: true }).evaluate((element) => element.getBoundingClientRect().height);
  expect(targetHeight).toBeGreaterThanOrEqual(44);

  await page.getByRole("button", { name: "Education", exact: true }).click();
  await expect(page.getByText(/Every Education record must reference one/)).toBeVisible();
  const dimensions = await page.evaluate(() => ({ viewport: window.innerWidth, scroll: document.documentElement.scrollWidth }));
  expect(dimensions.scroll).toBeLessThanOrEqual(dimensions.viewport);
});

test("Profile Draft Core semantic copy contains no unsupported product claims", async ({ page }) => {
  await openDraft(page);
  const text = (await page.locator("body").innerText()).toLowerCase();
  const prohibited = [
    "100% complete",
    "application ready",
    "verified profile",
    "good fit",
    "poor fit",
    "strong applicant",
    "weak applicant",
    "admission chance",
    "reach school",
    "target school",
    "safety school",
    "recommended program",
    "prestige score",
    "competitiveness score",
  ];
  for (const claim of prohibited) expect(text).not.toContain(claim);
});
