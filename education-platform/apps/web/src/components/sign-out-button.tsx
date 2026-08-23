"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { publicAuthErrorMessage } from "@/lib/auth/public-errors";
import { createClient } from "@/lib/supabase/client";

export function SignOutButton() {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [failed, setFailed] = useState(false);

  async function signOut() {
    setPending(true);
    setFailed(false);
    const { error } = await createClient().auth.signOut({ scope: "local" });

    if (error) {
      setPending(false);
      setFailed(true);
      return;
    }

    router.replace("/sign-in");
    router.refresh();
  }

  return (
    <div className="sign-out-control">
      <button className="secondary-button" type="button" onClick={signOut} disabled={pending}>
        {pending ? "Signing out…" : "Sign out"}
      </button>
      {failed ? <p className="form-error" role="alert">{publicAuthErrorMessage("SIGN_OUT_FAILED")}</p> : null}
    </div>
  );
}
