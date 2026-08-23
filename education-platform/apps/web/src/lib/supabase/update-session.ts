import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { decideRoute } from "@/lib/auth/route-policy";
import { getPublicSupabaseConfig } from "@/lib/supabase/config";

function copyCookies(source: NextResponse, target: NextResponse): void {
  for (const { name, value, ...options } of source.cookies.getAll()) {
    target.cookies.set(name, value, options);
  }
}

export async function updateSession(request: NextRequest): Promise<NextResponse> {
  let response = NextResponse.next({ request });
  const config = getPublicSupabaseConfig();

  const supabase = createServerClient(config.url, config.publishableKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
      },
    },
  });

  // This verifies identity with Supabase Auth. It is not an authorization check.
  const { data, error } = await supabase.auth.getUser();
  const decision = decideRoute(request.nextUrl.pathname, !error && data.user !== null);

  if (decision.kind === "redirect") {
    const redirectResponse = NextResponse.redirect(new URL(decision.destination, request.url));
    copyCookies(response, redirectResponse);
    return redirectResponse;
  }

  return response;
}
