"use client";

import { useState } from "react";

import type { ProfileAccount, ProfileDocument, ProfileOperationResult } from "@/lib/profile/contracts";
import { newProfileOperationId, postProfileRequest } from "@/lib/profile/client";

type ConnectionState = "idle" | "working" | "ready" | "error";

export function ProfileConnectionPanel() {
  const [state, setState] = useState<ConnectionState>("idle");
  const [summary, setSummary] = useState("No Profile capability request has been sent.");
  const [requestId, setRequestId] = useState<string | null>(null);

  async function bootstrap() {
    setState("working");
    const result = await postProfileRequest<ProfileAccount>("bootstrap", {});
    setRequestId(result.requestId);
    if (!result.ok) {
      setState("error");
      setSummary(result.message ?? "The Profile connection could not be initialized.");
      return;
    }
    setState("ready");
    setSummary(result.data.hasCurrentDraft ? "Profile identity active; a current draft exists." : "Profile identity active; no current draft exists.");
  }

  async function createOrResume() {
    setState("working");
    const operationId = newProfileOperationId();
    const result = await postProfileRequest<ProfileOperationResult>(
      "draft",
      { operationId },
      { ambiguousRetries: 1 },
    );
    setRequestId(result.requestId);
    if (!result.ok) {
      setState("error");
      setSummary(result.message ?? "The draft operation could not be completed.");
      return;
    }
    setState("ready");
    setSummary(`Draft v${String(result.data.versionNumber)} is available at revision ${String(result.data.revision)}.`);
  }

  async function loadCurrent() {
    setState("working");
    const result = await postProfileRequest<ProfileDocument>("document", {});
    setRequestId(result.requestId);
    if (!result.ok) {
      setState("error");
      setSummary(result.message ?? "The current draft could not be loaded.");
      return;
    }
    setState("ready");
    setSummary(`Current ${result.data.status.toLowerCase()} v${result.data.versionNumber}, revision ${result.data.revision}; ${result.data.readiness.declaredRequiredScopeCount}/${result.data.readiness.requiredScopeCount} completeness declarations recorded.`);
  }

  return (
    <div className="profile-connection-card" data-testid="profile-connection-shell">
      <div>
        <p className="eyebrow">LOCAL CONNECTION FOUNDATION</p>
        <h2>Profile capability boundary</h2>
        <p className="muted">
          These controls exercise the session-scoped Next.js boundary. They do not add Profile form fields or infer readiness.
        </p>
      </div>

      <div className="profile-actions">
        <button className="secondary-button" type="button" disabled={state === "working"} onClick={bootstrap}>
          Initialize profile connection
        </button>
        <button className="primary-button" type="button" disabled={state === "working"} onClick={createOrResume}>
          Create or resume draft
        </button>
        <button className="secondary-button" type="button" disabled={state === "working"} onClick={loadCurrent}>
          Load current draft
        </button>
      </div>

      <div className="profile-connection-result" aria-live="polite">
        <span className="field-label">Connection state</span>
        <strong data-testid="profile-connection-state">{state}</strong>
        <p data-testid="profile-connection-summary">{summary}</p>
        {requestId ? <small data-testid="profile-request-id">Request ID: {requestId}</small> : null}
      </div>
    </div>
  );
}
