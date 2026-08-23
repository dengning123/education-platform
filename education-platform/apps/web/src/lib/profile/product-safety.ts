export type SemanticGuardViolation = Readonly<{
  rule: string;
  excerpt: string;
}>;

export function isProfileFormDirty(current: Readonly<Record<string, unknown>>, authoritative: Readonly<Record<string, unknown>>): boolean {
  return JSON.stringify(current) !== JSON.stringify(authoritative);
}

const AFFIRMATIVE_PRODUCT_CLAIMS: readonly Readonly<{ rule: string; pattern: RegExp }>[] = Object.freeze([
  { rule: "OVERALL_PROFILE_SCORE", pattern: /\b(?:profile|application|admission|competitiveness|prestige)\s+(?:score|percentage|rating)\b/i },
  { rule: "OVERALL_COMPLETION_CLAIM", pattern: /\b(?:(?:profile )?(?:completion|completeness)\s*(?:score|percentage|:)\s*\d+%?|(?:100%|fully) complete|profile is complete)\b/i },
  { rule: "APPLICATION_READINESS", pattern: /\b(?:application|admission)\s+ready\b/i },
  { rule: "VERIFICATION_CLAIM", pattern: /\b(?:verified profile|fully verified|profile is verified|evidence (?:is|means) verified)\b/i },
  { rule: "FIT_CLAIM", pattern: /\b(?:good fit|poor fit)\b/i },
  { rule: "APPLICANT_STRENGTH", pattern: /\b(?:strong applicant|weak applicant)\b/i },
  { rule: "ADMISSION_PREDICTION", pattern: /\b(?:admission chance|admission probability|likelihood of admission)\b/i },
  { rule: "SCHOOL_BUCKET", pattern: /\b(?:reach|target|safety) (?:school|program)\b/i },
  { rule: "RECOMMENDATION", pattern: /\brecommended (?:school|program)\b/i },
  { rule: "FROZEN_EQUIVALENCE", pattern: /\b(?:frozen|freezing)\b[^.!?]*(?:means|is|makes)[^.!?]*\b(?:verified|complete|eligible)\b/i },
  { rule: "COMPLETENESS_EQUIVALENCE", pattern: /\bprofile completeness\b[^.!?]*(?:means|is|proves)[^.!?]*\b(?:eligib|verif)/i },
  { rule: "UNKNOWN_PARTIAL_FAILURE", pattern: /\b(?:unknown|partial)\b[^.!?]*(?:means|is|counts as)[^.!?]*\b(?:failure|invalid|failed)\b/i },
  { rule: "COUNT_COMPLETENESS", pattern: /\brecord count\b[^.!?]*(?:means|determines|proves)[^.!?]*\bcomplete/i },
  { rule: "GPA_COMPETITIVENESS", pattern: /\bgpa\b[^.!?]*(?:means|determines|proves|indicates)[^.!?]*\bcompetit/i },
  { rule: "INSTITUTION_PRESTIGE", pattern: /\binstitution\b[^.!?]*(?:means|determines|proves|indicates)[^.!?]*\bprestige/i },
  { rule: "COURSE_EQUIVALENCY", pattern: /\bcourse title\b[^.!?]*(?:means|determines|proves|establishes)[^.!?]*\b(?:prerequisite|equivalen)/i },
]);

const NEGATION_PATTERN = /\b(?:not|never|no|cannot|can't|does not|doesn't|do not|don't|without|neither|nor)\b/i;
const NEGATION_GLOBAL_PATTERN = /\b(?:not|never|no|cannot|can't|does not|doesn't|do not|don't|without|neither|nor)\b/gi;
const CONTRAST_PATTERN = /\b(?:but|however|instead|yet)\b/i;

function sentences(text: string): readonly string[] {
  return text.split(/(?<=[.!?])\s+|[\r\n]+/).map((sentence) => sentence.trim()).filter(Boolean);
}

function hasGoverningNegation(sentence: string, matchIndex: number, matchLength: number): boolean {
  const scopeStart = Math.max(0, matchIndex - 240);
  const scope = sentence.slice(scopeStart, matchIndex + matchLength);
  const negations = [...scope.matchAll(NEGATION_GLOBAL_PATTERN)];
  const last = negations.at(-1);
  if (!last || last.index === undefined || !NEGATION_PATTERN.test(last[0])) return false;
  const bridge = scope.slice(last.index + last[0].length, matchIndex - scopeStart);
  return !CONTRAST_PATTERN.test(bridge);
}

export function profileSemanticViolations(text: string): readonly SemanticGuardViolation[] {
  const violations: SemanticGuardViolation[] = [];
  for (const sentence of sentences(text)) {
    for (const rule of AFFIRMATIVE_PRODUCT_CLAIMS) {
      const match = sentence.match(rule.pattern);
      if (!match || match.index === undefined) continue;
      if (!hasGoverningNegation(sentence, match.index, match[0].length)) violations.push(Object.freeze({ rule: rule.rule, excerpt: sentence.slice(0, 240) }));
    }
  }
  return Object.freeze(violations);
}

export const PROHIBITED_PROFILE_AI_MODULE_PREFIXES = Object.freeze([
  "openai",
  "@anthropic-ai/",
  "@google/generative-ai",
  "@google/genai",
  "ai",
  "@ai-sdk/",
  "langchain",
  "@langchain/",
  "cohere-ai",
] as const);

export const PROHIBITED_PROFILE_AI_CAPABILITY_PATTERN = /\b(?:ai[_-]?(?:autofill|suggest|generate)|llm[_-]?|infer[_-]?(?:profile|degree|major|prestige|equivalency)|auto[_-]?(?:translate|convert|equivalency))\b/i;

export function isProhibitedProfileAiModule(specifier: string): boolean {
  return PROHIBITED_PROFILE_AI_MODULE_PREFIXES.some((prefix) => specifier === prefix || specifier.startsWith(prefix));
}

export function profileAiSourceViolations(source: string): readonly string[] {
  const violations: string[] = [];
  for (const match of source.matchAll(/(?:from\s+|import\s*\(|require\s*\()\s*["']([^"']+)["']/g)) {
    if (isProhibitedProfileAiModule(match[1])) violations.push(`AI_PROVIDER_IMPORT:${match[1]}`);
  }
  if (PROHIBITED_PROFILE_AI_CAPABILITY_PATTERN.test(source)) violations.push("AI_AUTOFILL_CAPABILITY");
  if (/\b(?:infer|generate|translate|convert)[A-Za-z0-9_]*\s*\([^)]*\)[\s\S]{0,240}\bpostProfileRequest\s*<[^>]*>?\s*\(\s*["']mutate["']/i.test(source)) {
    violations.push("INFERRED_AUTHORITATIVE_WRITE");
  }
  return Object.freeze(violations);
}
