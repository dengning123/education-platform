import { describe, expect, it } from "vitest";

import { mapProfileRpcError, publicProfileError } from "./errors";

describe("Profile public error catalog", () => {
  it("maps only closed RPC identities", () => {
    expect(mapProfileRpcError({ message: "PROFILE_REVISION_CONFLICT", code: "40001" })).toBe("PROFILE_REVISION_CONFLICT");
    expect(mapProfileRpcError({ message: "PROFILE_OPERATION_CONFLICT", detail: "internal operation row" })).toBe("PROFILE_OPERATION_CONFLICT");
    expect(mapProfileRpcError({ message: "PROFILE_NOT_FOUND", hint: "owner row exists" })).toBe("RESOURCE_NOT_FOUND");
    expect(mapProfileRpcError({ message: "PROFILE_UNKNOWN_FIELD", detail: "reviewedBy" })).toBe("INVALID_REQUEST");
  });

  it("fails unknown messages, details, hints, SQLSTATE, and nested causes closed", () => {
    const raw = { message: "relation private.student_identities does not exist", detail: "student@example.test", hint: "use service_role", code: "42P01", cause: { stack: "secret" } };
    expect(mapProfileRpcError(raw)).toBe("INTERNAL_ERROR");
    expect(publicProfileError(mapProfileRpcError(raw))).toEqual({ status: 500, message: "The profile service could not complete the request." });
  });
});
