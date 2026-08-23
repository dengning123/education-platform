export type RouteDecision =
  | Readonly<{ kind: "allow" }>
  | Readonly<{ kind: "redirect"; destination: string }>;

const signInPath = "/sign-in";
const defaultProtectedPath = "/account";
const protectedRoots = [defaultProtectedPath, "/profile"] as const;

export function isProtectedPath(pathname: string): boolean {
  return protectedRoots.some((root) => pathname === root || pathname.startsWith(`${root}/`));
}

export function safePostSignInPath(value: string | string[] | undefined): string {
  if (typeof value !== "string" || !isProtectedPath(value) || value.includes("?") || value.includes("#")) {
    return defaultProtectedPath;
  }
  return value;
}

export function decideRoute(pathname: string, authenticated: boolean): RouteDecision {
  if (!authenticated && isProtectedPath(pathname)) {
    return {
      kind: "redirect",
      destination: `${signInPath}?next=${encodeURIComponent(pathname)}`,
    };
  }

  if (authenticated && pathname === signInPath) {
    return { kind: "redirect", destination: defaultProtectedPath };
  }

  return { kind: "allow" };
}
