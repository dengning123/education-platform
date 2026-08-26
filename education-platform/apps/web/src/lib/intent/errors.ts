export const INTENT_PUBLIC_ERROR_CATALOG = Object.freeze({
  AUTH_REQUIRED: Object.freeze({ status: 401, message: "Sign in to continue." }),
  ACCESS_DENIED: Object.freeze({ status: 403, message: "This request is not allowed." }),
  RESOURCE_NOT_FOUND: Object.freeze({ status: 404, message: "The requested intent resource was not found." }),
  INVALID_REQUEST: Object.freeze({ status: 422, message: "The intent request is invalid." }),
  METHOD_NOT_ALLOWED: Object.freeze({ status: 405, message: "This request method is not allowed." }),
  UNSUPPORTED_MEDIA_TYPE: Object.freeze({ status: 415, message: "Send this request as application/json." }),
  PAYLOAD_TOO_LARGE: Object.freeze({ status: 413, message: "The intent request is too large." }),
  INVALID_JSON: Object.freeze({ status: 400, message: "The request body is not valid JSON." }),
  INTENT_REVISION_CONFLICT: Object.freeze({ status: 409, message: "This intent changed. Reload it before trying again." }),
  INTENT_OPERATION_CONFLICT: Object.freeze({ status: 409, message: "This operation identifier was already used for a different request." }),
  INTENT_NOT_READY: Object.freeze({ status: 409, message: "Every intent dimension must be declared or explicitly left unsupplied before freezing." }),
  INTENT_LIFECYCLE_CONFLICT: Object.freeze({ status: 409, message: "The intent is not in the required lifecycle state." }),
  REQUEST_TIMEOUT: Object.freeze({ status: 504, message: "The intent request timed out. Retry an ambiguous mutation with the same operation identifier and request." }),
  INTERNAL_ERROR: Object.freeze({ status: 500, message: "The intent service could not complete the request." }),
});

export type PublicIntentErrorCode = keyof typeof INTENT_PUBLIC_ERROR_CATALOG;

export class IntentServiceError extends Error {
  constructor(readonly code: PublicIntentErrorCode) {
    super(code);
    this.name = "IntentServiceError";
  }
}

const invalid = new Set([
  "FIT_INTENT_ACCESS_DECLARATION_REQUIRED", "FIT_INTENT_ACCESS_OPTION_UNAVAILABLE",
  "FIT_INTENT_COMMAND_UNSUPPORTED", "FIT_INTENT_CREATE_ARGUMENT_REQUIRED",
  "FIT_INTENT_DECLARATION_IDENTITY_IMMUTABLE", "FIT_INTENT_DECLARATION_LIMIT_EXCEEDED",
  "FIT_INTENT_DELIVERY_UNKNOWN_FORBIDDEN", "FIT_INTENT_DIMENSION_TYPE_MISMATCH",
  "FIT_INTENT_FEATURE_V027_UNSUPPORTED", "FIT_INTENT_FINANCIAL_TUPLE_INVALID",
  "FIT_INTENT_FINANCIAL_V027_UNSUPPORTED", "FIT_INTENT_FREEZE_ARGUMENT_REQUIRED",
  "FIT_INTENT_MUTATION_ARGUMENT_REQUIRED", "FIT_INTENT_NOT_SUPPLIED_CONFLICT",
  "FIT_INTENT_PAYLOAD_INVALID", "FIT_INTENT_PAYLOAD_KEY_FORBIDDEN",
  "FIT_INTENT_PAYLOAD_KEY_REQUIRED", "FIT_INTENT_REQUIRED_CONFIRMATION_REQUIRED",
  "FIT_INTENT_REQUIRED_DELIVERY_CONFLICT", "FIT_INTENT_REQUIRED_SEMANTICS_INVALID",
  "FIT_INTENT_SEMANTIC_TYPE_UNSUPPORTED", "FIT_INTENT_TAXONOMY_CONCEPT_INACTIVE",
  "FIT_INTENT_TAXONOMY_COVERAGE_UNAVAILABLE", "FIT_INTENT_TAXONOMY_DIMENSION_FORBIDDEN",
  "FIT_INTENT_TAXONOMY_KIND_FORBIDDEN", "FIT_INTENT_TYPED_CHILD_REQUIRED",
  "FIT_INTENT_TYPED_VALUE_INVALID",
]);

const internal = new Set([
  "FIT_INTENT_ASSERTION_INVALID", "FIT_INTENT_DIMENSION_STATE_CONFLICT",
  "FIT_INTENT_OPTION_LIMIT_EXCEEDED", "FIT_INTENT_OPTION_VALUE_TOO_LONG",
  "FIT_INTENT_PRODUCT_COMMAND_REQUIRED", "FIT_INTENT_PRODUCT_FREEZE_REQUIRED",
  "FIT_INTENT_VERIFIED_TAXONOMY_REQUIRED",
]);

export function mapIntentRpcError(error: unknown): PublicIntentErrorCode {
  if (error === null || typeof error !== "object" || !("message" in error) || typeof error.message !== "string") return "INTERNAL_ERROR";
  const message = error.message;
  if (["FIT_INTENT_NOT_FOUND", "FIT_INTENT_PROFILE_NOT_FOUND", "FIT_INTENT_DECLARATION_NOT_FOUND", "FIT_INTENT_ACCESS_CONTEXT_NOT_FOUND"].includes(message)) return "RESOURCE_NOT_FOUND";
  if (message === "FIT_INTENT_REVISION_CONFLICT") return "INTENT_REVISION_CONFLICT";
  if (message === "FIT_INTENT_OPERATION_CONFLICT") return "INTENT_OPERATION_CONFLICT";
  if (message === "FIT_INTENT_DIMENSIONS_INCOMPLETE") return "INTENT_NOT_READY";
  if (["FIT_INTENT_DRAFT_REQUIRED", "FIT_INTENT_FROZEN_PROFILE_REQUIRED"].includes(message)) return "INTENT_LIFECYCLE_CONFLICT";
  if (invalid.has(message)) return "INVALID_REQUEST";
  if (internal.has(message)) return "INTERNAL_ERROR";
  return "INTERNAL_ERROR";
}

export function publicIntentError(code: PublicIntentErrorCode) {
  return INTENT_PUBLIC_ERROR_CATALOG[code];
}
