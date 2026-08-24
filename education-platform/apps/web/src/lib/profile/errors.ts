export const PROFILE_PUBLIC_ERROR_CATALOG = Object.freeze({
  AUTH_REQUIRED: Object.freeze({ status: 401, message: "Sign in to continue." }),
  ACCESS_DENIED: Object.freeze({ status: 403, message: "This request is not allowed." }),
  RESOURCE_NOT_FOUND: Object.freeze({ status: 404, message: "The requested profile resource was not found." }),
  INVALID_REQUEST: Object.freeze({ status: 422, message: "The profile request is invalid." }),
  METHOD_NOT_ALLOWED: Object.freeze({ status: 405, message: "This request method is not allowed." }),
  UNSUPPORTED_MEDIA_TYPE: Object.freeze({ status: 415, message: "Send this request as application/json." }),
  PAYLOAD_TOO_LARGE: Object.freeze({ status: 413, message: "The profile request is too large." }),
  INVALID_JSON: Object.freeze({ status: 400, message: "The request body is not valid JSON." }),
  PROFILE_REVISION_CONFLICT: Object.freeze({ status: 409, message: "This profile changed. Reload it before trying again." }),
  PROFILE_OPERATION_CONFLICT: Object.freeze({ status: 409, message: "This operation identifier was already used for a different request." }),
  PROFILE_ACTIVE_DRAFT_EXISTS: Object.freeze({ status: 409, message: "An active profile draft already exists." }),
  PROFILE_LIFECYCLE_CONFLICT: Object.freeze({ status: 409, message: "The profile is not in the required lifecycle state." }),
  REQUEST_TIMEOUT: Object.freeze({ status: 504, message: "The profile request timed out. It can be retried safely with the same operation identifier." }),
  INTERNAL_ERROR: Object.freeze({ status: 500, message: "The profile service could not complete the request." }),
});

export type PublicProfileErrorCode = keyof typeof PROFILE_PUBLIC_ERROR_CATALOG;

export class ProfileServiceError extends Error {
  readonly code: PublicProfileErrorCode;

  constructor(code: PublicProfileErrorCode) {
    super(code);
    this.name = "ProfileServiceError";
    this.code = code;
  }
}

const invalidRequestIdentities = new Set([
  "PROFILE_COMMAND_UNSUPPORTED",
  "PROFILE_COMPLETENESS_EXPLANATION_REQUIRED",
  "PROFILE_COUNTRY_CODES_REQUIRED",
  "PROFILE_DELIVERY_MODES_REQUIRED",
  "PROFILE_EDUCATION_CONTEXT_NOT_ALLOWED",
  "PROFILE_EDUCATION_CONTEXT_REQUIRED",
  "PROFILE_FORK_ARGUMENT_REQUIRED",
  "PROFILE_FREEZE_ARGUMENT_REQUIRED",
  "PROFILE_INVALID_BUDGET_PREFERENCE",
  "PROFILE_INVALID_COUNTRY_CODE",
  "PROFILE_INVALID_DELIVERY_MODE",
  "PROFILE_INVALID_PROGRAM_LENGTH",
  "PROFILE_INVALID_SECTION_SCORE",
  "PROFILE_MUTATION_ARGUMENT_REQUIRED",
  "PROFILE_OPERATION_ID_REQUIRED",
  "PROFILE_PAYLOAD_OBJECT_REQUIRED",
  "PROFILE_PREFERENCE_OBJECT_REQUIRED",
  "PROFILE_PROGRAM_LENGTH_BOUND_REQUIRED",
  "PROFILE_REQUIRED_FIELD_MISSING",
  "PROFILE_SECTION_SCORES_OBJECT_REQUIRED",
  "PROFILE_TAXONOMY_KIND_NOT_ALLOWED",
  "PROFILE_UNKNOWN_FIELD",
  "PROFILE_UNKNOWN_SECTION_SCORE",
  "PROFILE_UNSUPPORTED_PREFERENCE_TYPE",
]);

const lifecycleIdentities = new Set([
  "PROFILE_DRAFT_REQUIRED",
  "PROFILE_EVIDENCE_IN_USE",
  "PROFILE_FROZEN_REQUIRED",
  "PROFILE_RECORD_HAS_MAPPING",
]);

const internalClosedIdentities = new Set([
  "PROFILE_FORK_GRAPH_INVALID",
  "PROFILE_FORK_MAPPING_GRAPH_INVALID",
  "PROFILE_FORK_OLD_ID_ALIAS",
  "PROFILE_TAXONOMY_OPTION_LIMIT_EXCEEDED",
  "PROFILE_TAXONOMY_OPTION_VALUE_TOO_LONG",
]);

export function mapProfileRpcError(error: unknown): PublicProfileErrorCode {
  if (error === null || typeof error !== "object") return "INTERNAL_ERROR";
  const message = "message" in error && typeof error.message === "string" ? error.message : null;
  if (message === "PROFILE_AUTH_REQUIRED") return "AUTH_REQUIRED";
  if (message === "PROFILE_ACCOUNT_INACTIVE") return "ACCESS_DENIED";
  if (message === "PROFILE_NOT_FOUND" || message === "PROFILE_CHILD_NOT_FOUND") return "RESOURCE_NOT_FOUND";
  if (message === "PROFILE_REVISION_CONFLICT") return "PROFILE_REVISION_CONFLICT";
  if (message === "PROFILE_OPERATION_CONFLICT") return "PROFILE_OPERATION_CONFLICT";
  if (message === "PROFILE_ACTIVE_DRAFT_EXISTS") return "PROFILE_ACTIVE_DRAFT_EXISTS";
  if (message !== null && invalidRequestIdentities.has(message)) return "INVALID_REQUEST";
  if (message !== null && lifecycleIdentities.has(message)) return "PROFILE_LIFECYCLE_CONFLICT";
  if (message !== null && internalClosedIdentities.has(message)) return "INTERNAL_ERROR";
  return "INTERNAL_ERROR";
}

export function publicProfileError(code: PublicProfileErrorCode): Readonly<{ status: number; message: string }> {
  return PROFILE_PUBLIC_ERROR_CATALOG[code];
}
