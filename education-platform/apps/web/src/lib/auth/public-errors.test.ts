import { describe, expect, it } from "vitest";

import { publicAuthErrorMessage } from "./public-errors";

describe("public auth error catalog", () => {
  it("returns catalog-authored messages without accepting raw dependency text", () => {
    expect(publicAuthErrorMessage("AUTHENTICATION_FAILED")).toBe(
      "We could not sign you in. Check your credentials and try again.",
    );
    expect(publicAuthErrorMessage("SIGN_OUT_FAILED")).toBe(
      "We could not complete sign-out. Please try again.",
    );
  });
});
