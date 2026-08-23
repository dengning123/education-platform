import { describe, expect, it } from "vitest";

import { decideRoute, isProtectedPath, safePostSignInPath } from "./route-policy";

describe("route policy", () => {
  it("redirects anonymous users away from protected routes", () => {
    expect(decideRoute("/account", false)).toEqual({
      kind: "redirect",
      destination: "/sign-in?next=%2Faccount",
    });
  });

  it("allows authenticated users into the protected account route", () => {
    expect(decideRoute("/account", true)).toEqual({ kind: "allow" });
  });

  it("moves an authenticated user away from sign-in", () => {
    expect(decideRoute("/sign-in", true)).toEqual({
      kind: "redirect",
      destination: "/account",
    });
  });

  it("does not treat route visibility as a data permission", () => {
    expect(decideRoute("/", false)).toEqual({ kind: "allow" });
    expect(isProtectedPath("/account/settings")).toBe(true);
    expect(isProtectedPath("/profile")).toBe(true);
    expect(isProtectedPath("/profile/history")).toBe(true);
  });

  it("rejects external and query-bearing post-sign-in targets", () => {
    expect(safePostSignInPath("https://attacker.example")).toBe("/account");
    expect(safePostSignInPath("//attacker.example/account")).toBe("/account");
    expect(safePostSignInPath("/account?admin=true")).toBe("/account");
    expect(safePostSignInPath(["/account"])).toBe("/account");
    expect(safePostSignInPath("/profile")).toBe("/profile");
  });
});
