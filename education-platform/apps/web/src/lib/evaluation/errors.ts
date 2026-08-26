export const EVALUATION_PUBLIC_ERROR_CATALOG = Object.freeze({
  AUTH_REQUIRED: Object.freeze({ status: 401, message: "Sign in to continue." }),
  ACCESS_DENIED: Object.freeze({ status: 403, message: "This request is not allowed." }),
  RESOURCE_NOT_FOUND: Object.freeze({ status: 404, message: "The requested evaluation resource was not found." }),
  PROFILE_NOT_FOUND: Object.freeze({ status: 404, message: "The requested frozen Profile was not found." }),
  PROFILE_NOT_FROZEN: Object.freeze({ status: 409, message: "Eligibility requires a frozen Profile version." }),
  PROGRAM_NOT_FOUND: Object.freeze({ status: 404, message: "The requested program version was not found." }),
  INVALID_REQUEST: Object.freeze({ status: 422, message: "The evaluation request is invalid." }),
  ELIGIBILITY_RULESET_NOT_FOUND: Object.freeze({ status: 422, message: "No verified Eligibility rules are available for this program version." }),
  ELIGIBILITY_RULESET_AMBIGUOUS: Object.freeze({ status: 409, message: "The program has conflicting verified Eligibility rules." }),
  ELIGIBILITY_INPUT_INVALID: Object.freeze({ status: 422, message: "The frozen Profile and verified program requirements cannot form a valid Eligibility input." }),
  ELIGIBILITY_ASSEMBLY_CONFLICT: Object.freeze({ status: 409, message: "This Eligibility operation conflicts with an earlier request." }),
  ELIGIBILITY_EVALUATION_CONFLICT: Object.freeze({ status: 409, message: "The Eligibility evaluation could not be completed from the current frozen inputs." }),
  METHOD_NOT_ALLOWED: Object.freeze({ status: 405, message: "This request method is not allowed." }),
  UNSUPPORTED_MEDIA_TYPE: Object.freeze({ status: 415, message: "Send this request as application/json." }),
  PAYLOAD_TOO_LARGE: Object.freeze({ status: 413, message: "The evaluation request is too large." }),
  INVALID_JSON: Object.freeze({ status: 400, message: "The request body is not valid JSON." }),
  REQUEST_TIMEOUT: Object.freeze({ status: 504, message: "The evaluation request timed out." }),
  INTERNAL_ERROR: Object.freeze({ status: 500, message: "The evaluation service could not complete the request." }),
});

export type PublicEvaluationErrorCode = keyof typeof EVALUATION_PUBLIC_ERROR_CATALOG;

export class EvaluationServiceError extends Error {
  constructor(readonly code: PublicEvaluationErrorCode) {
    super(code);
    this.name = "EvaluationServiceError";
  }
}

export function publicEvaluationError(code: PublicEvaluationErrorCode) {
  return EVALUATION_PUBLIC_ERROR_CATALOG[code];
}
