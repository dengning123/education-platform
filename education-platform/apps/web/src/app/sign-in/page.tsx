import { SignInForm } from "@/components/sign-in-form";
import { safePostSignInPath } from "@/lib/auth/route-policy";

type SignInPageProps = Readonly<{
  searchParams: Promise<{ next?: string | string[] }>;
}>;

export default async function SignInPage({ searchParams }: SignInPageProps) {
  const params = await searchParams;

  return (
    <section className="auth-grid">
      <div className="intro-panel">
        <p className="eyebrow">PHASE 4B · SECURE ACCESS</p>
        <h1>Your planning workspace starts with a verified session.</h1>
        <p className="intro-copy">
          Sign in to reach the protected account area. This shell confirms identity only;
          it does not create, simulate, or expose student planning data.
        </p>
        <ul className="boundary-list" aria-label="Security boundaries">
          <li>Browser-safe Supabase configuration only</li>
          <li>Server-verified session on protected routes</li>
          <li>Authorization remains with RLS and server ownership checks</li>
        </ul>
      </div>
      <SignInForm nextPath={safePostSignInPath(params.next)} />
    </section>
  );
}
