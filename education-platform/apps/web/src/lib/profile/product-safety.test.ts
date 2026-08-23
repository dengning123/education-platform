import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { PROFILE_COMMANDS } from "./contracts";
import { PROFILE_CAPABILITIES } from "./http-boundary";
import {
  isProfileFormDirty,
  profileAiSourceViolations,
  profileSemanticViolations,
  PROHIBITED_PROFILE_AI_CAPABILITY_PATTERN,
} from "./product-safety";
import { flattenProfileSemanticCopy, PROFILE_SEMANTIC_COPY } from "./semantic-copy";

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../../");

describe("Profile dirty-state contract", () => {
  it("tracks equality with the last authoritative form value, including a complete revert", () => {
    const authoritative = { institutionName: "浙江大学", gpaValue: "85", gpaScale: "100" };
    expect(isProfileFormDirty(authoritative, authoritative)).toBe(false);
    expect(isProfileFormDirty({ ...authoritative, gpaValue: "86" }, authoritative)).toBe(true);
    expect(isProfileFormDirty({ ...authoritative }, authoritative)).toBe(false);
  });
});

describe("Profile executable semantic guard", () => {
  it("accepts every approved typed semantic-copy entry", () => {
    const approved = flattenProfileSemanticCopy().join("\n");
    expect(profileSemanticViolations(approved)).toEqual([]);
  });

  it.each([
    "This is a verified profile.",
    "This Profile is 100% complete.",
    "Profile completion: 84%.",
    "Your application is admission ready.",
    "You are a strong applicant with a good fit.",
    "Your admission probability is 73%.",
    "This is a recommended program and a target school.",
    "Freezing means this Profile is complete and eligible.",
    "Evidence means verified.",
    "Your GPA indicates competitiveness.",
    "The institution determines prestige.",
    "The course title establishes prerequisite equivalency.",
  ])("rejects affirmative product claim: %s", (claim) => {
    expect(profileSemanticViolations(claim).length).toBeGreaterThan(0);
  });

  it("does not let an unrelated negation hide an affirmative claim", () => {
    expect(profileSemanticViolations("This is a verified profile, not a temporary draft.").length).toBeGreaterThan(0);
    expect(profileSemanticViolations("This is not a temporary draft, but it is a verified profile.").length).toBeGreaterThan(0);
  });

  it.each([
    "Freezing does not mean that you are eligible.",
    "This Profile is not presented as verified or complete.",
    "A record count never determines completeness.",
    "No course equivalency is inferred.",
    "Evidence is not proof that information was verified.",
  ])("allows important explanatory or negated copy: %s", (copy) => {
    expect(profileSemanticViolations(copy)).toEqual([]);
  });

  it("keeps the core semantic distinctions explicit in the typed catalog", () => {
    expect(PROFILE_SEMANTIC_COPY.completeness.COMPLETE).toContain("declared");
    expect(PROFILE_SEMANTIC_COPY.completeness.PARTIAL).toContain("not complete");
    expect(PROFILE_SEMANTIC_COPY.completeness.UNKNOWN).toContain("cannot currently confirm");
    expect(PROFILE_SEMANTIC_COPY.source.SELF_REPORT).toContain("not externally verified");
    expect(PROFILE_SEMANTIC_COPY.frozen.disclosure).toContain("does not mean");
    expect(PROFILE_SEMANTIC_COPY.mapping.noInference).toContain("not used");
  });

  it("scans the complete executable Profile UI source, including hidden states and dialogs", async () => {
    const paths = [
      "src/app/profile/page.tsx",
      "src/components/profile-draft-core.tsx",
      "src/components/profile-safety-provider.tsx",
      "src/lib/profile/draft-core.ts",
      "src/lib/profile/semantic-copy.ts",
    ];
    for (const path of paths) {
      const source = await readFile(resolve(webRoot, path), "utf8");
      expect(profileSemanticViolations(source), path).toEqual([]);
    }
  });
});

describe("no-AI-authoritative-autofill executable guard", () => {
  it("keeps AI/autofill capabilities and commands out of the closed Profile contract", () => {
    for (const value of [...PROFILE_CAPABILITIES, ...PROFILE_COMMANDS]) {
      expect(value).not.toMatch(PROHIBITED_PROFILE_AI_CAPABILITY_PATTERN);
    }
  });

  it("keeps AI providers and inferred authoritative writes out of the actual Profile executable path", async () => {
    const paths = [
      "src/components/profile-draft-core.tsx",
      "src/lib/profile/client.ts",
      "src/lib/profile/contracts.ts",
      "src/lib/profile/http-boundary.ts",
      "src/lib/profile/service.ts",
      "src/app/api/profile/[capability]/route.ts",
    ];
    for (const path of paths) {
      const source = await readFile(resolve(webRoot, path), "utf8");
      expect(profileAiSourceViolations(source), path).toEqual([]);
    }
    const manifest = JSON.parse(await readFile(resolve(webRoot, "package.json"), "utf8")) as { dependencies: Record<string, string> };
    for (const dependency of Object.keys(manifest.dependencies)) {
      expect(profileAiSourceViolations(`import value from \"${dependency}\"`), dependency).toEqual([]);
    }
  });

  it("fails closed for an AI provider, autofill capability, or inferred mutation sequence", () => {
    expect(profileAiSourceViolations("import OpenAI from 'openai'")).toContain("AI_PROVIDER_IMPORT:openai");
    expect(profileAiSourceViolations("const capability = 'ai-autofill'")).toContain("AI_AUTOFILL_CAPABILITY");
    expect(profileAiSourceViolations("inferMajor(input); postProfileRequest<Result>('mutate', body)")).toContain("INFERRED_AUTHORITATIVE_WRITE");
  });
});
