import { redirect } from "next/navigation";
import Link from "next/link";

import { SignOutButton } from "@/components/sign-out-button";
import { getVerifiedUser } from "@/lib/auth/verified-user";

export const dynamic = "force-dynamic";

export default async function AccountPage() {
  const user = await getVerifiedUser();
  if (!user) redirect("/sign-in?next=%2Faccount");

  return (
    <section className="account-layout">
      <div className="account-heading">
        <div>
          <p className="eyebrow">ACCOUNT STATE</p>
          <h1>Session verified</h1>
          <p className="intro-copy">
            Your identity is active. Product data flows are intentionally unavailable in Phase 4B-1A.
          </p>
        </div>
        <span className="status-badge" data-testid="auth-status">Authenticated</span>
      </div>

      <div className="account-card">
        <div>
          <span className="field-label">Signed in as</span>
          <strong data-testid="account-email">{user.email ?? "Verified account"}</strong>
        </div>
        <SignOutButton />
      </div>

      <div className="boundary-card" data-testid="authorization-boundary">
        <p className="eyebrow">SECURITY BOUNDARY</p>
        <h2>Authentication is not authorization</h2>
        <p>
          Route protection improves navigation safety, but it grants no database privileges.
          Future student-data requests must still pass existing RLS and server-side ownership checks.
        </p>
      </div>

      <Link className="primary-button account-link" href="/profile">
        Open local Profile connection
      </Link>
    </section>
  );
}
