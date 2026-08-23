export type PublicAuthErrorCode = "AUTHENTICATION_FAILED" | "SIGN_OUT_FAILED";

const messages: Readonly<Record<PublicAuthErrorCode, string>> = Object.freeze({
  AUTHENTICATION_FAILED: "We could not sign you in. Check your credentials and try again.",
  SIGN_OUT_FAILED: "We could not complete sign-out. Please try again.",
});

export function publicAuthErrorMessage(code: PublicAuthErrorCode): string {
  return messages[code];
}
