import { redirect } from "next/navigation";

import { ProfileDraftCore } from "@/components/profile-draft-core";
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
          <p className="eyebrow">PROFILE DRAFT</p>
          <h1>Build what you can support</h1>
          <p className="intro-copy">
            Record sources, education, courses, and explicit completeness declarations without inferred facts or converted grades.
          </p>
        </div>
        <SignOutButton />
      </div>
      <ProfileDraftCore />
    </section>
  );
}
