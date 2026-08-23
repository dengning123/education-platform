import { redirect } from "next/navigation";

import { ProfileConnectionPanel } from "@/components/profile-connection-panel";
import { SignOutButton } from "@/components/sign-out-button";
import { getVerifiedUser } from "@/lib/auth/verified-user";

export const dynamic = "force-dynamic";

export default async function ProfilePage() {
  const user = await getVerifiedUser();
  if (!user) redirect("/sign-in?next=%2Fprofile");

  return (
    <section className="account-layout">
      <div className="account-heading">
        <div>
          <p className="eyebrow">PROFILE CONNECTION</p>
          <h1>Secure Profile transport</h1>
          <p className="intro-copy">
            Local-only connection shell for the owner-scoped Migration 019/020 capabilities.
          </p>
        </div>
        <SignOutButton />
      </div>
      <ProfileConnectionPanel />
    </section>
  );
}
