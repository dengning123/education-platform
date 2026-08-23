export const PROFILE_SEMANTIC_COPY = Object.freeze({
  completeness: Object.freeze({
    COMPLETE: "You have explicitly declared that this data scope is complete.",
    PARTIAL: "You have provided some information, but you have declared that this scope is not complete.",
    UNKNOWN: "You cannot currently confirm whether this data scope is complete.",
    MISSING_DECLARATION: "No completeness declaration has been provided for this required scope.",
    law: "Only a missing required declaration directly prevents freeze.",
    lawDetail: "PARTIAL and UNKNOWN remain valid declarations when their explanation is recorded.",
  }),
  frozen: Object.freeze({
    status: "FROZEN",
    heading: "IMMUTABLE PROFILE VERSION",
    explanation: "This is the authoritative document returned by the freeze operation. It cannot be edited in place.",
    disclosure: "This frozen state does not mean the information was externally verified, error-free, sufficient for any program, or assessed for admission likelihood.",
  }),
  source: Object.freeze({
    SELF_REPORT: "Student-provided information; not externally verified.",
    TRANSCRIPT: "Information referenced from a transcript source.",
    TEST_REPORT: "Information referenced from a test report source.",
    RESUME: "Information referenced from a resume source.",
    OTHER: "Information referenced from another student-identified source.",
    provenance: "A source records provenance. It is not proof that information was externally reviewed or confirmed.",
  }),
  mapping: Object.freeze({
    readiness: "Mapping readiness is separate from completeness and cannot be changed here.",
    noInference: "Mapping readiness is displayed separately and is not used by this UI to infer completeness.",
    unavailable: "No projected concept label is available for this record.",
    historical: "Historical at",
  }),
  conflict: Object.freeze({
    revisionTitle: "Review the latest version before saving again.",
    revisionBody: "Your unsaved form values are still present. Confirm only after comparing them with the reloaded Profile.",
    revisionNotice: "This Profile was updated in another page or operation. Review the latest version before saving again.",
    operationNotice: "The operation identifier was already used for different content. Your changes were not applied; the authoritative Profile has been reloaded.",
    timeoutTitle: "The outcome may be ambiguous.",
    timeoutBody: "The database operation may have continued. Retry sends the exact same operation identifier, revision, command, and payload.",
  }),
  unsaved: Object.freeze({
    title: "Discard unsaved changes?",
    section: "Switching Profile sections will discard the unsaved form values shown here.",
    navigation: "Leaving this page will discard the unsaved form values shown here.",
    logout: "Signing out will discard the unsaved form values shown here.",
    close: "Closing this form will discard its unsaved values.",
    keepEditing: "Keep editing",
    discard: "Discard changes",
  }),
  recovery: Object.freeze({
    title: "Unsaved local form draft found",
    body: "This tab kept a short-lived unsaved form draft. It is not saved Profile data and will never be submitted automatically.",
    staleBody: "The authoritative Profile revision has changed since this local draft was captured. Restore only after reviewing every value and relationship.",
    restore: "Restore local draft",
    discard: "Discard local draft",
  }),
  reviewFreeze: Object.freeze({
    heading: "What freezing means",
    explanation: "Freezing creates an immutable version of the information currently stored in this Profile for use by downstream evaluations.",
    warning: "Freezing does not mean that your information has been externally verified; your Profile is complete or error-free; you satisfy any program requirement; or your admission likelihood has been assessed.",
    confirmation: "I understand that this exact version becomes immutable and that freeze does not add verification or evaluation meaning.",
  }),
  unsupported: Object.freeze({
    heading: "Not available in this MVP",
    sections: "Tests · Experience · Skills · Goals · Preferences",
    reviewHeading: "Unsupported editing in this MVP",
  }),
  inference: Object.freeze({
    courseTranslation: "Use the source language. No AI translation is written to your Profile.",
    courseRepresentation: "Credits and grades remain in their original representation. No course equivalency is inferred.",
    gpaRepresentation: "Enter the GPA exactly as shown in your academic record. Do not convert it to a U.S. 4.0 scale.",
  }),
});

export type ProfileSemanticCopy = typeof PROFILE_SEMANTIC_COPY;

export function flattenProfileSemanticCopy(value: unknown = PROFILE_SEMANTIC_COPY): readonly string[] {
  if (typeof value === "string") return [value];
  if (value === null || typeof value !== "object") return [];
  return Object.values(value as Record<string, unknown>).flatMap((entry) => flattenProfileSemanticCopy(entry));
}
