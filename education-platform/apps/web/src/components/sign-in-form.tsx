"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";

import { publicAuthErrorMessage } from "@/lib/auth/public-errors";
import { createClient } from "@/lib/supabase/client";

type FormState = "idle" | "submitting" | "error";

export function SignInForm({ nextPath }: Readonly<{ nextPath: string }>) {
  const router = useRouter();
  const [state, setState] = useState<FormState>("idle");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setState("submitting");

    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") ?? "").trim();
    const password = String(form.get("password") ?? "");
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });

    if (error) {
      setState("error");
      return;
    }

    router.replace(nextPath);
    router.refresh();
  }

  return (
    <form className="auth-card" onSubmit={handleSubmit} data-testid="sign-in-form">
      <div>
        <p className="eyebrow">SIGN IN</p>
        <h2>Continue securely</h2>
        <p className="muted">Use the account already provisioned for this private workspace.</p>
      </div>

      <label>
        <span>Email</span>
        <input
          name="email"
          type="email"
          autoComplete="email"
          inputMode="email"
          required
          disabled={state === "submitting"}
        />
      </label>

      <label>
        <span>Password</span>
        <input
          name="password"
          type="password"
          autoComplete="current-password"
          minLength={8}
          required
          disabled={state === "submitting"}
        />
      </label>

      {state === "error" ? (
        <p className="form-error" role="alert" data-testid="auth-error">
          {publicAuthErrorMessage("AUTHENTICATION_FAILED")}
        </p>
      ) : null}

      <button className="primary-button" type="submit" disabled={state === "submitting"}>
        {state === "submitting" ? "Signing in…" : "Sign in"}
      </button>
    </form>
  );
}
