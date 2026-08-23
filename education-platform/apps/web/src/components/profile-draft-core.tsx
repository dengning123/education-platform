"use client";

import {
  type FormEvent,
  type KeyboardEvent,
  type ReactNode,
  useCallback,
  useEffect,
  useReducer,
  useRef,
  useState,
} from "react";

import {
  RecoveryPrompt,
  useProfileDirtyRegistration,
  useProfileSafety,
} from "@/components/profile-safety-provider";
import { newProfileOperationId, postProfileRequest } from "@/lib/profile/client";
import {
  PROFILE_COMPLETENESS_VALUES,
  PROFILE_COURSE_STATUSES,
  PROFILE_DEGREE_LEVELS,
  PROFILE_DEGREE_STATUSES,
  PROFILE_EVIDENCE_TYPES,
  parseProfileDocument,
  parseProfileOperationResult,
  type ProfileCommand,
  type ProfileCommandPayloads,
  type ProfileDocument,
  type ProfileMutationCommand,
  type ProfileOperationResult,
} from "@/lib/profile/contracts";
import {
  PROFILE_DOMAIN_LABELS,
  PROFILE_DRAFT_SECTIONS,
  completenessDescription,
  completenessScopes,
  courseUpdatePayload,
  courses,
  degreeLabel,
  degreeUpdatePayload,
  degrees,
  evidenceItems,
  evidenceUpdatePayload,
  evidenceUsage,
  mappingReadinessFor,
  profileOverview,
  sourceDescription,
  type ProfileCompletenessScope,
  type ProfileCourse,
  type ProfileDegree,
  type ProfileDraftSection,
  type ProfileEvidenceItem,
} from "@/lib/profile/draft-core";
import {
  clearAllProfileRecovery,
  ensureProfileRecoveryContext,
  type CompletenessRecoveryPayload,
  type CourseRecoveryPayload,
  type EducationRecoveryPayload,
} from "@/lib/profile/profile-recovery";
import { isProfileFormDirty } from "@/lib/profile/product-safety";
import { PROFILE_SEMANTIC_COPY } from "@/lib/profile/semantic-copy";
import { useProfileLocalRecovery } from "@/lib/profile/use-profile-recovery";

type UiPhase = "loading" | "empty" | "ready" | "frozen" | "error";
type NoticeTone = "neutral" | "success" | "warning" | "error";

type MutationRequest = Readonly<{
  profileVersionId: string;
  operationId: string;
  expectedRevision: number;
} & ProfileMutationCommand>;

type RevisionConflict = Readonly<{
  command: ProfileCommand;
  payload: ProfileCommandPayloads[ProfileCommand];
  description: string;
}>;

type ExactRetry = Readonly<{
  capability: "mutate" | "freeze";
  body: MutationRequest | Readonly<{ profileVersionId: string; operationId: string; expectedRevision: number }>;
  description: string;
}>;

type UiState = Readonly<{
  phase: UiPhase;
  document: ProfileDocument | null;
  section: ProfileDraftSection;
  pending: boolean;
  notice: string;
  noticeTone: NoticeTone;
  requestId: string | null;
  revisionConflict: RevisionConflict | null;
  exactRetry: ExactRetry | null;
}>;

type UiAction =
  | Readonly<{ type: "BEGIN"; notice: string }>
  | Readonly<{ type: "EMPTY"; notice: string; requestId: string }>
  | Readonly<{ type: "DOCUMENT"; document: ProfileDocument; notice: string; requestId: string | null }>
  | Readonly<{ type: "FROZEN"; document: ProfileDocument; notice: string; requestId: string }>
  | Readonly<{ type: "FAIL"; notice: string; requestId: string | null; exactRetry?: ExactRetry | null }>
  | Readonly<{ type: "SECTION"; section: ProfileDraftSection }>
  | Readonly<{ type: "CONFLICT"; document: ProfileDocument; conflict: RevisionConflict; requestId: string }>
  | Readonly<{ type: "CLEAR_ISSUE" }>;

const initialState: UiState = Object.freeze({
  phase: "loading",
  document: null,
  section: "overview",
  pending: false,
  notice: "Opening your Profile workspace…",
  noticeTone: "neutral",
  requestId: null,
  revisionConflict: null,
  exactRetry: null,
});

function reducer(state: UiState, action: UiAction): UiState {
  switch (action.type) {
    case "BEGIN":
      return { ...state, pending: true, notice: action.notice, noticeTone: "neutral", revisionConflict: null, exactRetry: null };
    case "EMPTY":
      return { ...state, phase: "empty", document: null, pending: false, notice: action.notice, noticeTone: "neutral", requestId: action.requestId, revisionConflict: null, exactRetry: null };
    case "DOCUMENT":
      return { ...state, phase: action.document.status === "FROZEN" ? "frozen" : "ready", document: action.document, pending: false, notice: action.notice, noticeTone: "success", requestId: action.requestId, revisionConflict: null, exactRetry: null };
    case "FROZEN":
      return { ...state, phase: "frozen", document: action.document, pending: false, notice: action.notice, noticeTone: "success", requestId: action.requestId, revisionConflict: null, exactRetry: null };
    case "FAIL":
      return { ...state, phase: state.document ? state.phase : "error", pending: false, notice: action.notice, noticeTone: "error", requestId: action.requestId, exactRetry: action.exactRetry ?? null };
    case "SECTION":
      return { ...state, section: action.section, noticeTone: state.noticeTone === "error" ? "neutral" : state.noticeTone };
    case "CONFLICT":
      return { ...state, phase: "ready", document: action.document, pending: false, notice: PROFILE_SEMANTIC_COPY.conflict.revisionNotice, noticeTone: "warning", requestId: action.requestId, revisionConflict: action.conflict, exactRetry: null };
    case "CLEAR_ISSUE":
      return { ...state, revisionConflict: null, exactRetry: null, notice: "The latest authoritative Profile is displayed.", noticeTone: "neutral" };
  }
}

const sectionLabels: Readonly<Record<ProfileDraftSection, string>> = Object.freeze({
  overview: "Overview",
  sources: "Sources",
  education: "Education",
  courses: "Courses",
  completeness: "Completeness",
  review: "Review & Freeze",
});

function nullableText(value: string): string | null {
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

function nullableNumber(value: string): number | null {
  const trimmed = value.trim();
  if (trimmed === "") return null;
  const parsed = Number(trimmed);
  if (!Number.isFinite(parsed)) throw new TypeError("Enter a valid number.");
  return parsed;
}

function observedTimestamp(value: string): string | null {
  if (value.trim() === "") return null;
  const parsed = new Date(`${value}:00Z`);
  if (Number.isNaN(parsed.getTime())) throw new TypeError("Enter a valid observed date and time.");
  return parsed.toISOString();
}

function observedInput(value: string | null): string {
  if (!value) return "";
  return value.replace(/Z$/, "").slice(0, 16);
}

function statusIcon(value: string): string {
  if (value === "COMPLETE" || value === "VERIFIED") return "✓";
  if (value === "PARTIAL" || value === "PROPOSED") return "◐";
  if (value === "UNKNOWN" || value === "MISSING_DECLARATION") return "?";
  return "•";
}

function StatusPill({ value }: Readonly<{ value: string }>) {
  return (
    <span className={`profile-status-pill status-${value.toLowerCase()}`}>
      <span aria-hidden="true">{statusIcon(value)}</span>
      {value.replaceAll("_", " ")}
    </span>
  );
}

function Field({ label, hint, error, children }: Readonly<{ label: string; hint?: string; error?: string; children: ReactNode }>) {
  return (
    <label className="profile-field">
      <span className="profile-field-label">{label}</span>
      {children}
      {hint ? <span className="profile-field-hint">{hint}</span> : null}
      {error ? <span className="profile-field-error">{error}</span> : null}
    </label>
  );
}

function FormErrorSummary({ message }: Readonly<{ message: string | null }>) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (message) ref.current?.focus();
  }, [message]);
  if (!message) return null;
  return <div className="profile-error-summary" role="alert" tabIndex={-1} ref={ref}>{message}</div>;
}

function ConfirmDialog({ title, message, confirmLabel, onConfirm, onCancel }: Readonly<{
  title: string;
  message: string;
  confirmLabel: string;
  onConfirm(): void;
  onCancel(): void;
}>) {
  const cancelRef = useRef<HTMLButtonElement>(null);
  const confirmRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    cancelRef.current?.focus();
  }, []);

  function containFocus(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      onCancel();
      return;
    }
    if (event.key !== "Tab") return;
    const first = cancelRef.current;
    const last = confirmRef.current;
    if (!first || !last) return;
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  return (
    <div className="profile-dialog-backdrop">
      <div className="profile-dialog" role="dialog" aria-modal="true" aria-labelledby="profile-dialog-title" onKeyDown={containFocus}>
        <h2 id="profile-dialog-title">{title}</h2>
        <p>{message}</p>
        <div className="profile-dialog-actions">
          <button className="secondary-button" type="button" ref={cancelRef} onClick={onCancel}>Cancel</button>
          <button className="danger-button" type="button" ref={confirmRef} onClick={onConfirm}>{confirmLabel}</button>
        </div>
      </div>
    </div>
  );
}

type Mutate = <Command extends ProfileCommand>(command: Command, payload: ProfileCommandPayloads[Command], description: string) => Promise<boolean>;

export function ProfileDraftCore() {
  const profileSafety = useProfileSafety();
  const [state, dispatch] = useReducer(reducer, initialState);
  const mutationLock = useRef(false);
  const documentRef = useRef<ProfileDocument | null>(null);

  useEffect(() => {
    documentRef.current = state.document;
  }, [state.document]);

  useEffect(() => {
    if (!state.document || state.document.status !== "DRAFT") return;
    void ensureProfileRecoveryContext(window.sessionStorage, {
      profileVersionId: state.document.profileVersionId,
      versionNumber: state.document.versionNumber,
    });
  }, [state.document]);

  const readDocument = useCallback(async (successNotice: string): Promise<ProfileDocument | null> => {
    const result = await postProfileRequest<ProfileDocument>("document", {});
    if (!result.ok) {
      dispatch({ type: "FAIL", notice: result.message ?? "The authoritative Profile could not be read.", requestId: result.requestId });
      return null;
    }
    try {
      const document = parseProfileDocument(result.data);
      dispatch({ type: "DOCUMENT", document, notice: successNotice, requestId: result.requestId });
      return document;
    } catch {
      dispatch({ type: "FAIL", notice: "The Profile response did not match the expected public contract.", requestId: result.requestId });
      return null;
    }
  }, []);

  const openWorkspace = useCallback(async () => {
    dispatch({ type: "BEGIN", notice: "Opening your Profile workspace…" });
    const bootstrap = await postProfileRequest<{ schemaVersion: "PROFILE_ACCOUNT_V019"; accountState: "ACTIVE"; hasCurrentDraft: boolean }>("bootstrap", {});
    if (!bootstrap.ok) {
      dispatch({ type: "FAIL", notice: bootstrap.message ?? "The Profile workspace could not be opened.", requestId: bootstrap.requestId });
      return;
    }
    if (!bootstrap.data.hasCurrentDraft) {
      dispatch({ type: "EMPTY", notice: "No active Profile draft exists yet.", requestId: bootstrap.requestId });
      return;
    }
    await readDocument("Your authoritative Profile draft is loaded.");
  }, [readDocument]);

  useEffect(() => {
    void openWorkspace();
  }, [openWorkspace]);

  async function startDraft() {
    if (mutationLock.current) return;
    mutationLock.current = true;
    dispatch({ type: "BEGIN", notice: "Creating or resuming your Profile draft…" });
    const operationId = newProfileOperationId();
    const result = await postProfileRequest<ProfileOperationResult>("draft", { operationId }, { ambiguousRetries: 1 });
    if (!result.ok) {
      dispatch({ type: "FAIL", notice: result.message ?? "The Profile draft could not be created.", requestId: result.requestId });
      mutationLock.current = false;
      return;
    }
    try {
      parseProfileOperationResult(result.data);
      await readDocument("Profile draft created. Add only information you can support from a source.");
    } catch {
      dispatch({ type: "FAIL", notice: "The draft response did not match the expected public contract.", requestId: result.requestId });
    } finally {
      mutationLock.current = false;
    }
  }

  async function refreshAfterConflict(conflict: RevisionConflict, requestId: string) {
    const result = await postProfileRequest<ProfileDocument>("document", {});
    if (!result.ok) {
      dispatch({ type: "FAIL", notice: result.message ?? "The latest Profile could not be read after the conflict.", requestId: result.requestId });
      return;
    }
    try {
      dispatch({ type: "CONFLICT", document: parseProfileDocument(result.data), conflict, requestId });
    } catch {
      dispatch({ type: "FAIL", notice: "The latest Profile did not match the expected public contract.", requestId: result.requestId });
    }
  }

  async function performMutation(request: MutationRequest, description: string): Promise<boolean> {
    dispatch({ type: "BEGIN", notice: `${description}…` });
    const result = await postProfileRequest<ProfileOperationResult>("mutate", request, { ambiguousRetries: 1 });
    if (!result.ok) {
      const conflict = { command: request.command, payload: request.payload, description } as RevisionConflict;
      if (result.error === "PROFILE_REVISION_CONFLICT") {
        await refreshAfterConflict(conflict, result.requestId);
      } else if (result.error === "PROFILE_OPERATION_CONFLICT") {
        await readDocument(PROFILE_SEMANTIC_COPY.conflict.operationNotice);
      } else {
        dispatch({
          type: "FAIL",
          notice: result.message ?? "Your changes were not applied. Your local form has been preserved.",
          requestId: result.requestId,
          exactRetry: result.error === "REQUEST_TIMEOUT" ? { capability: "mutate", body: request, description } : null,
        });
      }
      return false;
    }
    try {
      const operation = parseProfileOperationResult(result.data);
      if (operation.revision <= request.expectedRevision) throw new TypeError("INVALID_REVISION_ADVANCE");
      return (await readDocument(`${description} saved from the authoritative Profile.`)) !== null;
    } catch {
      dispatch({ type: "FAIL", notice: "The mutation result did not match the expected public contract.", requestId: result.requestId });
      return false;
    }
  }

  const mutate: Mutate = async (command, payload, description) => {
    if (mutationLock.current) return false;
    const document = documentRef.current;
    if (!document || document.status !== "DRAFT") return false;
    mutationLock.current = true;
    const request = Object.freeze({
      profileVersionId: document.profileVersionId,
      operationId: newProfileOperationId(),
      expectedRevision: document.revision,
      command,
      payload,
    }) as MutationRequest;
    try {
      return await performMutation(request, description);
    } finally {
      mutationLock.current = false;
    }
  };

  async function confirmRevisionRetry() {
    if (mutationLock.current || !state.revisionConflict || !state.document || state.document.status !== "DRAFT") return;
    mutationLock.current = true;
    const request = Object.freeze({
      profileVersionId: state.document.profileVersionId,
      operationId: newProfileOperationId(),
      expectedRevision: state.document.revision,
      command: state.revisionConflict.command,
      payload: state.revisionConflict.payload,
    }) as MutationRequest;
    try {
      await performMutation(request, state.revisionConflict.description);
    } finally {
      mutationLock.current = false;
    }
  }

  async function retryExactRequest() {
    if (mutationLock.current || !state.exactRetry) return;
    mutationLock.current = true;
    const retry = state.exactRetry;
    try {
      if (retry.capability === "mutate") {
        await performMutation(retry.body as MutationRequest, retry.description);
        return;
      }
      await performFreeze(retry.body as Readonly<{ profileVersionId: string; operationId: string; expectedRevision: number }>);
    } finally {
      mutationLock.current = false;
    }
  }

  async function performFreeze(body: Readonly<{ profileVersionId: string; operationId: string; expectedRevision: number }>) {
    dispatch({ type: "BEGIN", notice: "Freezing this exact Profile version…" });
    const result = await postProfileRequest<ProfileOperationResult>("freeze", body, { ambiguousRetries: 1 });
    if (!result.ok) {
      if (result.error === "PROFILE_REVISION_CONFLICT") {
        const latest = await readDocument("This Profile changed before it could be frozen. Review the latest version and confirm again.");
        if (latest) dispatch({ type: "SECTION", section: "review" });
      } else {
        dispatch({
          type: "FAIL",
          notice: result.message ?? "This Profile was not frozen.",
          requestId: result.requestId,
          exactRetry: result.error === "REQUEST_TIMEOUT" ? { capability: "freeze", body, description: "Freeze Profile" } : null,
        });
      }
      return false;
    }
    try {
      const operation = parseProfileOperationResult(result.data);
      if (operation.operation !== "FREEZE") throw new TypeError("INVALID_FREEZE_RESULT");
      const document = parseProfileDocument(operation.document);
      clearAllProfileRecovery(window.sessionStorage);
      dispatch({ type: "FROZEN", document, notice: "Immutable Profile version created.", requestId: result.requestId });
      return true;
    } catch {
      dispatch({ type: "FAIL", notice: "The freeze result did not match the expected public contract.", requestId: result.requestId });
      return false;
    }
  }

  async function freezeProfile() {
    if (mutationLock.current || !state.document || state.document.status !== "DRAFT") return;
    mutationLock.current = true;
    const body = Object.freeze({
      profileVersionId: state.document.profileVersionId,
      operationId: newProfileOperationId(),
      expectedRevision: state.document.revision,
    });
    try {
      await performFreeze(body);
    } finally {
      mutationLock.current = false;
    }
  }

  async function changeSection(section: ProfileDraftSection) {
    if (section === state.section) return;
    if (!await profileSafety.requestDiscard({ message: PROFILE_SEMANTIC_COPY.unsaved.section })) return;
    dispatch({ type: "SECTION", section });
    window.requestAnimationFrame(() => document.getElementById("profile-section-heading")?.focus());
  }

  if (state.phase === "loading" || (state.pending && !state.document)) {
    return <ProfileLoading notice={state.notice} />;
  }

  if (state.phase === "empty") {
    return (
      <div className="profile-empty-card" data-testid="profile-draft-empty">
        <p className="eyebrow">PROFILE DRAFT</p>
        <h2>Build from sources, not assumptions</h2>
        <p>Create a narrow Profile draft for your education and course history. Nothing is inferred from your institution, GPA, course names, or record count.</p>
        <button className="primary-button" type="button" onClick={startDraft}>Start Profile draft</button>
        <ProfileLiveStatus state={state} />
      </div>
    );
  }

  if (state.phase === "error" && !state.document) {
    return (
      <div className="profile-empty-card" data-testid="profile-draft-error">
        <p className="eyebrow">PROFILE UNAVAILABLE</p>
        <h2>The workspace could not be opened</h2>
        <ProfileLiveStatus state={state} />
        <button className="secondary-button" type="button" onClick={() => void openWorkspace()}>Try again</button>
      </div>
    );
  }

  if (!state.document) return null;

  if (state.phase === "frozen" || state.document.status === "FROZEN") {
    return <FrozenProfileView document={state.document} state={state} />;
  }

  return (
    <div className="profile-workspace" data-testid="profile-draft-core">
      <aside className="profile-sidebar" aria-label="Profile sections">
        <div className="profile-version-card">
          <span className="field-label">Profile version</span>
          <strong>Draft v{state.document.versionNumber}</strong>
          <span>Revision {state.document.revision}</span>
          <StatusPill value={state.document.status} />
        </div>
        <nav className="profile-section-nav">
          {PROFILE_DRAFT_SECTIONS.map((section) => (
            <button
              className={state.section === section ? "active" : ""}
              type="button"
              key={section}
              aria-current={state.section === section ? "page" : undefined}
              onClick={() => void changeSection(section)}
            >
              {sectionLabels[section]}
            </button>
          ))}
        </nav>
        <div className="profile-mvp-note">
          <strong>{PROFILE_SEMANTIC_COPY.unsupported.heading}</strong>
          <span>{PROFILE_SEMANTIC_COPY.unsupported.sections}</span>
        </div>
      </aside>

      <div className="profile-main-panel">
        <ProfileLiveStatus state={state} />
        {state.revisionConflict ? (
          <div className="profile-conflict-card" role="alert">
            <strong>{PROFILE_SEMANTIC_COPY.conflict.revisionTitle}</strong>
            <p>{PROFILE_SEMANTIC_COPY.conflict.revisionBody}</p>
            <div className="profile-inline-actions">
              <button className="primary-button" type="button" disabled={state.pending} onClick={() => void confirmRevisionRetry()}>Confirm against revision {state.document.revision}</button>
              <button className="secondary-button" type="button" onClick={() => dispatch({ type: "CLEAR_ISSUE" })}>Keep reviewing</button>
            </div>
          </div>
        ) : null}
        {state.exactRetry ? (
          <div className="profile-conflict-card" role="alert">
            <strong>{PROFILE_SEMANTIC_COPY.conflict.timeoutTitle}</strong>
            <p>{PROFILE_SEMANTIC_COPY.conflict.timeoutBody}</p>
            <button className="secondary-button" type="button" disabled={state.pending} onClick={() => void retryExactRequest()}>Retry exact request</button>
          </div>
        ) : null}

        {state.section === "overview" ? <OverviewSection document={state.document} onNavigate={(section) => void changeSection(section)} /> : null}
        {state.section === "sources" ? <SourcesSection document={state.document} mutate={mutate} pending={state.pending} /> : null}
        {state.section === "education" ? <EducationSection document={state.document} mutate={mutate} pending={state.pending} /> : null}
        {state.section === "courses" ? <CoursesSection document={state.document} mutate={mutate} pending={state.pending} /> : null}
        {state.section === "completeness" ? <CompletenessSection document={state.document} mutate={mutate} pending={state.pending} /> : null}
        {state.section === "review" ? <ReviewSection document={state.document} pending={state.pending} onFreeze={() => void freezeProfile()} /> : null}
      </div>
    </div>
  );
}

function ProfileLoading({ notice }: Readonly<{ notice: string }>) {
  return (
    <div className="profile-empty-card" aria-live="polite" data-testid="profile-loading">
      <span className="spinner" aria-hidden="true" />
      <div><p className="eyebrow">PROFILE DRAFT</p><h2>{notice}</h2></div>
    </div>
  );
}

function ProfileLiveStatus({ state }: Readonly<{ state: UiState }>) {
  return (
    <div className={`profile-live-status tone-${state.noticeTone}`} aria-live="polite" aria-atomic="true" data-testid="profile-live-status">
      <span aria-hidden="true">{state.pending ? "…" : state.noticeTone === "error" ? "!" : state.noticeTone === "warning" ? "?" : "✓"}</span>
      <span>{state.notice}</span>
      {state.requestId ? <small>Request ID: {state.requestId}</small> : null}
    </div>
  );
}

function SectionHeading({ eyebrow, title, description }: Readonly<{ eyebrow: string; title: string; description: string }>) {
  return (
    <header className="profile-section-heading">
      <p className="eyebrow">{eyebrow}</p>
      <h2 id="profile-section-heading" tabIndex={-1}>{title}</h2>
      <p>{description}</p>
    </header>
  );
}

function OverviewSection({ document, onNavigate }: Readonly<{ document: ProfileDocument; onNavigate(section: ProfileDraftSection): void }>) {
  const overview = profileOverview(document);
  const partial = overview.completenessScopes.filter((scope) => scope.completeness === "PARTIAL").length;
  const unknown = overview.completenessScopes.filter((scope) => scope.completeness === "UNKNOWN").length;
  const missing = document.readiness.missingDeclarations.length;
  return (
    <section>
      <SectionHeading eyebrow="OVERVIEW" title="What this Profile contains" description="Record counts and completeness declarations are shown separately. A count never determines whether a data scope is complete." />
      <div className="profile-metric-grid" data-testid="profile-record-counts">
        <Metric label="Sources" value={overview.counts.sources} />
        <Metric label="Education records" value={overview.counts.education} />
        <Metric label="Course records" value={overview.counts.courses} />
        <Metric label="Required declarations" value={`${document.readiness.declaredRequiredScopeCount} recorded`} />
      </div>
      <div className="profile-two-column">
        <article className="profile-section-card">
          <h3>Authoritative completeness</h3>
          <p>{missing} missing · {partial} partial · {unknown} unknown</p>
          <p className="profile-card-note">PARTIAL and UNKNOWN are legitimate declarations. {PROFILE_SEMANTIC_COPY.completeness.law}</p>
          <button className="secondary-button" type="button" onClick={() => onNavigate("completeness")}>Review declarations</button>
        </article>
        <article className="profile-section-card">
          <h3>Mapping readiness</h3>
          <p>{document.readiness.mappingReadiness.filter((item) => item.verified).length} records have a VERIFIED mapping state.</p>
          <p className="profile-card-note">{PROFILE_SEMANTIC_COPY.mapping.readiness}</p>
          <button className="secondary-button" type="button" onClick={() => onNavigate("review")}>Review Profile</button>
        </article>
      </div>
    </section>
  );
}

function Metric({ label, value }: Readonly<{ label: string; value: string | number }>) {
  return <div className="profile-metric"><span>{label}</span><strong>{value}</strong></div>;
}

function SourcesSection({ document, mutate, pending }: Readonly<{ document: ProfileDocument; mutate: Mutate; pending: boolean }>) {
  const items = evidenceItems(document);
  const [editing, setEditing] = useState<ProfileEvidenceItem | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<ProfileEvidenceItem | null>(null);
  const deleteOpener = useRef<HTMLButtonElement | null>(null);

  async function remove() {
    if (!deleteTarget) return;
    const success = await mutate("EVIDENCE_DELETE", { evidenceId: deleteTarget.evidenceId }, "Delete source");
    if (success) setDeleteTarget(null);
  }

  return (
    <section>
      <SectionHeading eyebrow="SOURCES" title="Where your information comes from" description={PROFILE_SEMANTIC_COPY.source.provenance} />
      <div className="profile-section-toolbar">
        <p>{items.length} source record{items.length === 1 ? "" : "s"}</p>
        <button className="primary-button" type="button" disabled={pending} onClick={() => { setEditing(null); setShowForm(true); }}>Add source</button>
      </div>
      {showForm ? <SourceForm item={editing} pending={pending} mutate={mutate} onClose={() => { setShowForm(false); setEditing(null); }} /> : null}
      <div className="profile-card-list">
        {items.length === 0 ? <EmptyMessage>Add a source before creating Education or Course records.</EmptyMessage> : items.map((item) => {
          const usage = evidenceUsage(document, item.evidenceId);
          return (
            <article className="profile-record-card" key={item.evidenceId}>
              <div className="profile-record-heading"><div><span className="field-label">Source type</span><h3>{item.evidenceType.replaceAll("_", " ")}</h3></div><span className="source-badge">Source</span></div>
              <p>{sourceDescription(item)}</p>
              <dl className="profile-detail-list">
                <div><dt>Reference</dt><dd>{item.locator ?? "No reference entered"}</dd></div>
                <div><dt>Observed</dt><dd>{new Date(item.observedAt).toLocaleString()}</dd></div>
                <div><dt>Records using source</dt><dd>{usage.total}</dd></div>
              </dl>
              <div className="profile-inline-actions">
                <button className="secondary-button" type="button" disabled={pending} onClick={() => { setEditing(item); setShowForm(true); }}>Edit source</button>
                <button className="text-danger-button" type="button" disabled={pending} ref={(node) => { if (deleteTarget?.evidenceId === item.evidenceId) deleteOpener.current = node; }} onClick={(event) => { deleteOpener.current = event.currentTarget; setDeleteTarget(item); }}>Delete</button>
              </div>
            </article>
          );
        })}
      </div>
      {deleteTarget ? <ConfirmDialog title="Delete this source?" message="The backend will refuse deletion if any Profile record still uses it." confirmLabel="Delete source" onCancel={() => { setDeleteTarget(null); deleteOpener.current?.focus(); }} onConfirm={() => void remove()} /> : null}
    </section>
  );
}

function SourceForm({ item, mutate, pending, onClose }: Readonly<{ item: ProfileEvidenceItem | null; mutate: Mutate; pending: boolean; onClose(): void }>) {
  const safety = useProfileSafety();
  const preserved = item ? evidenceUpdatePayload(item) : null;
  const baselineEvidenceType = item?.evidenceType ?? "SELF_REPORT";
  const baselineLocator = item?.locator ?? "";
  const baselineObservedAt = observedInput(item?.observedAt ?? null);
  const [evidenceType, setEvidenceType] = useState<ProfileEvidenceItem["evidenceType"]>(baselineEvidenceType);
  const [locator, setLocator] = useState(baselineLocator);
  const [observedAt, setObservedAt] = useState(baselineObservedAt);
  const [error, setError] = useState<string | null>(null);
  const dirty = evidenceType !== baselineEvidenceType || locator !== baselineLocator || observedAt !== baselineObservedAt;
  const dirtyKey = `SOURCE:${item?.evidenceId ?? "CREATE"}`;

  function discard() {
    setEvidenceType(baselineEvidenceType);
    setLocator(baselineLocator);
    setObservedAt(baselineObservedAt);
    setError(null);
  }

  useProfileDirtyRegistration(dirtyKey, dirty, "Source", discard);

  async function close() {
    if (!await safety.requestDiscard({ message: PROFILE_SEMANTIC_COPY.unsaved.close, keys: [dirtyKey] })) return;
    onClose();
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      const base = { evidenceType, locator: nullableText(locator), contentHash: preserved?.contentHash ?? null, observedAt: observedTimestamp(observedAt) };
      const success = item
        ? await mutate("EVIDENCE_UPDATE", { evidenceId: item.evidenceId, ...base }, "Update source")
        : await mutate("EVIDENCE_CREATE", base, "Create source");
      if (success) onClose();
    } catch (cause) {
      setError(cause instanceof TypeError ? cause.message : "Review the source fields.");
    }
  }

  return (
    <form className="profile-editor" onSubmit={submit}>
      <div className="profile-editor-heading"><div><span className="field-label">{item ? "Edit source" : "New source"}</span><h3>Source details</h3></div><button className="close-button" type="button" aria-label="Close source form" onClick={() => void close()}>×</button></div>
      <FormErrorSummary message={error} />
      <div className="profile-form-grid">
        <Field label="Source type"><select value={evidenceType} onChange={(event) => setEvidenceType(event.target.value as ProfileEvidenceItem["evidenceType"])}>{PROFILE_EVIDENCE_TYPES.map((value) => <option value={value} key={value}>{value.replaceAll("_", " ")}</option>)}</select></Field>
        <Field label="Locator or reference" hint="A reference you recognize; no file is uploaded."><input value={locator} onChange={(event) => setLocator(event.target.value)} /></Field>
        <Field label="Observed date and time" hint="Optional; recorded as entered, without external verification."><input type="datetime-local" value={observedAt} onChange={(event) => setObservedAt(event.target.value)} /></Field>
      </div>
      <p className="profile-disclosure">{sourceDescription({ evidenceId: item?.evidenceId ?? "", evidenceType, locator: null, contentHash: null, observedAt: "" })}</p>
      <button className="primary-button" type="submit" disabled={pending}>{pending ? "Saving…" : "Save source"}</button>
    </form>
  );
}

function EducationSection({ document, mutate, pending }: Readonly<{ document: ProfileDocument; mutate: Mutate; pending: boolean }>) {
  const records = degrees(document);
  const sources = evidenceItems(document);
  const [editing, setEditing] = useState<ProfileDegree | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<ProfileDegree | null>(null);

  return (
    <section>
      <SectionHeading eyebrow="EDUCATION" title="Academic records as they appear at the source" description="Use the institution, degree, dates, country code, and raw GPA shown in your record. This MVP has no authoritative major or field-of-study field." />
      <div className="profile-section-toolbar"><p>{records.length} education record{records.length === 1 ? "" : "s"}</p><button className="primary-button" type="button" disabled={pending || sources.length === 0} onClick={() => { setEditing(null); setShowForm(true); }}>Add education</button></div>
      {sources.length === 0 ? <InlineNote>Create a Source first. Every Education record must reference one.</InlineNote> : null}
      {showForm ? <EducationForm document={document} record={editing} sources={sources} mutate={mutate} pending={pending} onClose={() => { setShowForm(false); setEditing(null); }} /> : null}
      <div className="profile-card-list">
        {records.length === 0 ? <EmptyMessage>No Education records have been entered.</EmptyMessage> : records.map((record) => {
          const mapping = mappingReadinessFor(document, record.degreeId);
          return (
            <article className="profile-record-card" key={record.degreeId}>
              <div className="profile-record-heading"><div><span className="field-label">{record.degreeLevel}</span><h3>{record.institutionName}</h3><p>{record.degreeName}</p></div>{mapping ? <StatusPill value={mapping.verified ? "VERIFIED" : mapping.mappingStatuses[0] ?? "UNKNOWN"} /> : <StatusPill value="UNKNOWN" />}</div>
              <dl className="profile-detail-list">
                <div><dt>Status</dt><dd>{record.degreeStatus.replaceAll("_", " ")}</dd></div>
                <div><dt>Dates</dt><dd>{record.startDate ?? "Not entered"} → {record.completionDate ?? "Not entered"}</dd></div>
                <div><dt>Country</dt><dd>{record.countryCode ?? "Not entered"}</dd></div>
                <div><dt>GPA as entered</dt><dd>{record.gpaValue === null ? "Not entered" : `${record.gpaValue} / ${record.gpaScale}`}</dd></div>
              </dl>
              <p className="profile-card-note">Mapping readiness: {mapping?.mappingStatuses.join(", ") || "No mapping state"}. {PROFILE_SEMANTIC_COPY.mapping.unavailable}</p>
              <div className="profile-inline-actions"><button className="secondary-button" type="button" disabled={pending} onClick={() => { setEditing(record); setShowForm(true); }}>Edit education</button><button className="text-danger-button" type="button" disabled={pending} onClick={() => setDeleteTarget(record)}>Delete</button></div>
            </article>
          );
        })}
      </div>
      {deleteTarget ? <ConfirmDialog title="Delete this Education record?" message="Linked Courses, completeness contexts, or mappings may prevent or broaden this deletion. Review the backend result before continuing." confirmLabel="Delete education" onCancel={() => setDeleteTarget(null)} onConfirm={() => void mutate("DEGREE_DELETE", { degreeId: deleteTarget.degreeId }, "Delete education").then((success) => { if (success) setDeleteTarget(null); })} /> : null}
    </section>
  );
}

type DegreeFormState = Readonly<{ institutionName: string; degreeName: string; degreeLevel: ProfileDegree["degreeLevel"]; degreeStatus: ProfileDegree["degreeStatus"]; startDate: string; completionDate: string; countryCode: string; gpaValue: string; gpaScale: string; evidenceId: string }>;

function EducationForm({ document, record, sources, mutate, pending, onClose }: Readonly<{ document: ProfileDocument; record: ProfileDegree | null; sources: readonly ProfileEvidenceItem[]; mutate: Mutate; pending: boolean; onClose(): void }>) {
  const safety = useProfileSafety();
  const base = record ? degreeUpdatePayload(record) : null;
  const baseline: DegreeFormState = { institutionName: base?.institutionName ?? "", degreeName: base?.degreeName ?? "", degreeLevel: base?.degreeLevel ?? "BACHELORS", degreeStatus: base?.degreeStatus ?? "IN_PROGRESS", startDate: base?.startDate ?? "", completionDate: base?.completionDate ?? "", countryCode: base?.countryCode ?? "", gpaValue: base?.gpaValue?.toString() ?? "", gpaScale: base?.gpaScale?.toString() ?? "", evidenceId: base?.evidenceId ?? sources[0]?.evidenceId ?? "" };
  const [form, setForm] = useState<DegreeFormState>(baseline);
  const [error, setError] = useState<string | null>(null);
  const dirty = isProfileFormDirty(form, baseline);
  const dirtyKey = `EDUCATION:${record?.degreeId ?? "CREATE"}`;
  const set = <Key extends keyof DegreeFormState>(key: Key, value: DegreeFormState[Key]) => setForm((current) => ({ ...current, [key]: value }));
  const recoveryPayload: EducationRecoveryPayload = {
    institutionName: form.institutionName,
    degreeName: form.degreeName,
    degreeLevel: form.degreeLevel,
    degreeStatus: form.degreeStatus,
    startDate: form.startDate,
    completionDate: form.completionDate,
    countryCode: form.countryCode,
    gpaValue: form.gpaValue,
    gpaScale: form.gpaScale,
  };
  const recovery = useProfileLocalRecovery({
    identity: {
      kind: "EDUCATION",
      profileVersionId: document.profileVersionId,
      versionNumber: document.versionNumber,
      currentRevision: document.revision,
      formContextId: record?.degreeId ?? "CREATE",
    },
    dirty,
    payload: recoveryPayload,
    apply: (payload) => setForm((current) => ({ ...current, ...payload })),
    reset: () => { setForm(baseline); setError(null); },
  });

  useProfileDirtyRegistration(dirtyKey, dirty, "Education", recovery.discard);

  async function close() {
    if (!await safety.requestDiscard({ message: PROFILE_SEMANTIC_COPY.unsaved.close, keys: [dirtyKey] })) return;
    onClose();
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      const gpaValue = nullableNumber(form.gpaValue);
      const gpaScale = nullableNumber(form.gpaScale);
      if ((gpaValue === null) !== (gpaScale === null)) throw new TypeError("Enter both GPA value and GPA scale, or leave both blank.");
      if (gpaValue !== null && gpaScale !== null && (gpaScale <= 0 || gpaValue < 0 || gpaValue > gpaScale)) throw new TypeError("Enter the GPA exactly within its stated scale.");
      const payload = { institutionName: form.institutionName.trim(), degreeName: form.degreeName.trim(), degreeLevel: form.degreeLevel, degreeStatus: form.degreeStatus, startDate: nullableText(form.startDate), completionDate: nullableText(form.completionDate), countryCode: nullableText(form.countryCode)?.toUpperCase() ?? null, gpaValue, gpaScale, evidenceId: form.evidenceId };
      if (!payload.institutionName || !payload.degreeName || !payload.evidenceId) throw new TypeError("Institution, degree name, and source are required.");
      if (payload.countryCode && !/^[A-Z]{2}$/.test(payload.countryCode)) throw new TypeError("Country code must contain two letters, such as CN or US.");
      const success = record ? await mutate("DEGREE_UPDATE", { degreeId: record.degreeId, ...payload }, "Update education") : await mutate("DEGREE_CREATE", payload, "Create education");
      if (success) { await recovery.clear(); onClose(); }
    } catch (cause) {
      setError(cause instanceof TypeError ? cause.message : "Review the Education fields.");
    }
  }

  return (
    <form className="profile-editor" onSubmit={submit}>
      <div className="profile-editor-heading"><div><span className="field-label">{record ? "Edit education" : "New education"}</span><h3>Academic record</h3></div><button className="close-button" type="button" aria-label="Close education form" onClick={() => void close()}>×</button></div>
      <FormErrorSummary message={error} />
      {recovery.candidate ? <RecoveryPrompt revisionChanged={recovery.candidate.revisionChanged} onRestore={recovery.restore} onDiscard={() => void recovery.discard()} /> : null}
      <fieldset className="profile-recovery-fieldset" disabled={recovery.candidate !== null}>
        <div className="profile-form-grid">
          <Field label="Institution name" hint="Chinese, an official English name, or the transcript wording are accepted."><input required value={form.institutionName} onChange={(event) => set("institutionName", event.target.value)} /></Field>
          <Field label="Degree name" hint="Enter the actual degree, such as 工学学士. Do not put a major here."><input required value={form.degreeName} onChange={(event) => set("degreeName", event.target.value)} /></Field>
          <Field label="Degree level"><select value={form.degreeLevel} onChange={(event) => set("degreeLevel", event.target.value as ProfileDegree["degreeLevel"])}>{PROFILE_DEGREE_LEVELS.map((value) => <option value={value} key={value}>{value}</option>)}</select></Field>
          <Field label="Degree status"><select value={form.degreeStatus} onChange={(event) => set("degreeStatus", event.target.value as ProfileDegree["degreeStatus"])}>{PROFILE_DEGREE_STATUSES.map((value) => <option value={value} key={value}>{value.replaceAll("_", " ")}</option>)}</select></Field>
          <Field label="Start date"><input type="date" value={form.startDate} onChange={(event) => set("startDate", event.target.value)} /></Field>
          <Field label="Completion date"><input type="date" value={form.completionDate} onChange={(event) => set("completionDate", event.target.value)} /></Field>
          <Field label="Country code" hint="Two-letter source country code, for example CN."><input maxLength={2} value={form.countryCode} onChange={(event) => set("countryCode", event.target.value)} /></Field>
          <Field label="Source"><select required value={form.evidenceId} onChange={(event) => set("evidenceId", event.target.value)}><option value="">Select source</option>{sources.map((source, index) => <option value={source.evidenceId} key={source.evidenceId}>{source.evidenceType.replaceAll("_", " ")} {source.locator ? `— ${source.locator}` : `#${index + 1}`}</option>)}</select></Field>
          <Field label="GPA value" hint="Enter exactly as shown; no 4.0 conversion."><input inputMode="decimal" value={form.gpaValue} onChange={(event) => set("gpaValue", event.target.value)} placeholder="85" /></Field>
          <Field label="GPA scale" hint="Keep the original scale."><input inputMode="decimal" value={form.gpaScale} onChange={(event) => set("gpaScale", event.target.value)} placeholder="100" /></Field>
        </div>
        <p className="profile-disclosure">{PROFILE_SEMANTIC_COPY.inference.gpaRepresentation}</p>
        <button className="primary-button" type="submit" disabled={pending}>{pending ? "Saving…" : "Save education"}</button>
      </fieldset>
    </form>
  );
}

function CoursesSection({ document, mutate, pending }: Readonly<{ document: ProfileDocument; mutate: Mutate; pending: boolean }>) {
  const records = courses(document);
  const sources = evidenceItems(document);
  const education = degrees(document);
  const [editing, setEditing] = useState<ProfileCourse | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<ProfileCourse | null>(null);
  return (
    <section>
      <SectionHeading eyebrow="COURSES" title="Course history without equivalency guesses" description="Keep course titles, credits, terms, and grades in their source representation. The UI does not translate courses or convert credits and grades." />
      <div className="profile-section-toolbar"><p>{records.length} course record{records.length === 1 ? "" : "s"}</p><button className="primary-button" type="button" disabled={pending || sources.length === 0} onClick={() => { setEditing(null); setShowForm(true); }}>Add course</button></div>
      {sources.length === 0 ? <InlineNote>Create a Source first. Every Course record must reference one.</InlineNote> : null}
      {showForm ? <CourseForm document={document} record={editing} sources={sources} education={education} mutate={mutate} pending={pending} onClose={() => { setShowForm(false); setEditing(null); }} /> : null}
      <div className="profile-course-list">
        {records.length === 0 ? <EmptyMessage>No Course records have been entered.</EmptyMessage> : records.map((record) => {
          const mapping = mappingReadinessFor(document, record.courseId);
          return (
            <article className="profile-record-card" key={record.courseId}>
              <div className="profile-record-heading"><div><span className="field-label">{record.courseCode ?? "No course code"}</span><h3>{record.courseTitle}</h3><p>{degreeLabel(document, record.degreeId)}</p></div>{mapping ? <StatusPill value={mapping.verified ? "VERIFIED" : mapping.mappingStatuses[0] ?? "UNKNOWN"} /> : <StatusPill value="UNKNOWN" />}</div>
              <dl className="profile-detail-list">
                <div><dt>Status</dt><dd>{record.courseStatus.replaceAll("_", " ")}</dd></div>
                <div><dt>Term</dt><dd>{record.term ?? "Not entered"}</dd></div>
                <div><dt>Credits as entered</dt><dd>{record.credits ?? "Not entered"}</dd></div>
                <div><dt>Grade as entered</dt><dd>{record.gradeValue === null ? record.gradeText ?? "Not entered" : `${record.gradeValue} / ${record.gradeScale}${record.gradeText ? ` · ${record.gradeText}` : ""}`}</dd></div>
              </dl>
              <p className="profile-card-note">Mapping readiness: {mapping?.mappingStatuses.join(", ") || "No mapping state"}. {PROFILE_SEMANTIC_COPY.mapping.unavailable}</p>
              <div className="profile-inline-actions"><button className="secondary-button" type="button" disabled={pending} onClick={() => { setEditing(record); setShowForm(true); }}>Edit course</button><button className="text-danger-button" type="button" disabled={pending} onClick={() => setDeleteTarget(record)}>Delete</button></div>
            </article>
          );
        })}
      </div>
      {deleteTarget ? <ConfirmDialog title="Delete this Course record?" message="The backend will refuse deletion when a mapping still references this Course." confirmLabel="Delete course" onCancel={() => setDeleteTarget(null)} onConfirm={() => void mutate("COURSE_DELETE", { courseId: deleteTarget.courseId }, "Delete course").then((success) => { if (success) setDeleteTarget(null); })} /> : null}
    </section>
  );
}

type CourseFormState = Readonly<{ degreeId: string; courseCode: string; courseTitle: string; courseStatus: ProfileCourse["courseStatus"]; term: string; completionDate: string; credits: string; gradeValue: string; gradeScale: string; gradeText: string; evidenceId: string }>;

function CourseForm({ document, record, sources, education, mutate, pending, onClose }: Readonly<{ document: ProfileDocument; record: ProfileCourse | null; sources: readonly ProfileEvidenceItem[]; education: readonly ProfileDegree[]; mutate: Mutate; pending: boolean; onClose(): void }>) {
  const safety = useProfileSafety();
  const base = record ? courseUpdatePayload(record) : null;
  const baseline: CourseFormState = { degreeId: base?.degreeId ?? education[0]?.degreeId ?? "", courseCode: base?.courseCode ?? "", courseTitle: base?.courseTitle ?? "", courseStatus: base?.courseStatus ?? "COMPLETED", term: base?.term ?? "", completionDate: base?.completionDate ?? "", credits: base?.credits?.toString() ?? "", gradeValue: base?.gradeValue?.toString() ?? "", gradeScale: base?.gradeScale?.toString() ?? "", gradeText: base?.gradeText ?? "", evidenceId: base?.evidenceId ?? sources[0]?.evidenceId ?? "" };
  const [form, setForm] = useState<CourseFormState>(baseline);
  const [error, setError] = useState<string | null>(null);
  const dirty = isProfileFormDirty(form, baseline);
  const dirtyKey = `COURSE:${record?.courseId ?? "CREATE"}`;
  const set = <Key extends keyof CourseFormState>(key: Key, value: CourseFormState[Key]) => setForm((current) => ({ ...current, [key]: value }));
  const recoveryPayload: CourseRecoveryPayload = {
    courseCode: form.courseCode,
    courseTitle: form.courseTitle,
    courseStatus: form.courseStatus,
    term: form.term,
    completionDate: form.completionDate,
    credits: form.credits,
    gradeValue: form.gradeValue,
    gradeScale: form.gradeScale,
    gradeText: form.gradeText,
  };
  const recovery = useProfileLocalRecovery({
    identity: {
      kind: "COURSE",
      profileVersionId: document.profileVersionId,
      versionNumber: document.versionNumber,
      currentRevision: document.revision,
      formContextId: record?.courseId ?? "CREATE",
    },
    dirty,
    payload: recoveryPayload,
    apply: (payload) => setForm((current) => ({ ...current, ...payload })),
    reset: () => { setForm(baseline); setError(null); },
  });

  useProfileDirtyRegistration(dirtyKey, dirty, "Course", recovery.discard);

  async function close() {
    if (!await safety.requestDiscard({ message: PROFILE_SEMANTIC_COPY.unsaved.close, keys: [dirtyKey] })) return;
    onClose();
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      const gradeValue = nullableNumber(form.gradeValue);
      const gradeScale = nullableNumber(form.gradeScale);
      if ((gradeValue === null) !== (gradeScale === null)) throw new TypeError("Enter both numeric grade value and grade scale, or leave both blank.");
      const credits = nullableNumber(form.credits);
      if (credits !== null && credits <= 0) throw new TypeError("Credits must be greater than zero when entered.");
      if (gradeValue !== null && gradeScale !== null && (gradeScale <= 0 || gradeValue < 0 || gradeValue > gradeScale)) throw new TypeError("Enter the grade exactly within its stated scale.");
      const payload = { degreeId: nullableText(form.degreeId), courseCode: nullableText(form.courseCode), courseTitle: form.courseTitle.trim(), courseStatus: form.courseStatus, term: nullableText(form.term), completionDate: nullableText(form.completionDate), credits, gradeValue, gradeScale, gradeText: nullableText(form.gradeText), evidenceId: form.evidenceId };
      if (!payload.courseTitle || !payload.evidenceId) throw new TypeError("Course title and source are required.");
      const success = record ? await mutate("COURSE_UPDATE", { courseId: record.courseId, ...payload }, "Update course") : await mutate("COURSE_CREATE", payload, "Create course");
      if (success) { await recovery.clear(); onClose(); }
    } catch (cause) {
      setError(cause instanceof TypeError ? cause.message : "Review the Course fields.");
    }
  }

  return (
    <form className="profile-editor" onSubmit={submit}>
      <div className="profile-editor-heading"><div><span className="field-label">{record ? "Edit course" : "New course"}</span><h3>Course record</h3></div><button className="close-button" type="button" aria-label="Close course form" onClick={() => void close()}>×</button></div>
      <FormErrorSummary message={error} />
      {recovery.candidate ? <RecoveryPrompt revisionChanged={recovery.candidate.revisionChanged} onRestore={recovery.restore} onDiscard={() => void recovery.discard()} /> : null}
      <fieldset className="profile-recovery-fieldset" disabled={recovery.candidate !== null}>
        <div className="profile-form-grid">
          <Field label="Education context"><select value={form.degreeId} onChange={(event) => set("degreeId", event.target.value)}><option value="">Profile-wide course history</option>{education.map((degree) => <option value={degree.degreeId} key={degree.degreeId}>{degree.institutionName} — {degree.degreeName}</option>)}</select></Field>
          <Field label="Source"><select required value={form.evidenceId} onChange={(event) => set("evidenceId", event.target.value)}><option value="">Select source</option>{sources.map((source, index) => <option value={source.evidenceId} key={source.evidenceId}>{source.evidenceType.replaceAll("_", " ")} {source.locator ? `— ${source.locator}` : `#${index + 1}`}</option>)}</select></Field>
          <Field label="Course code"><input value={form.courseCode} onChange={(event) => set("courseCode", event.target.value)} /></Field>
          <Field label="Course title" hint={PROFILE_SEMANTIC_COPY.inference.courseTranslation}><input required value={form.courseTitle} onChange={(event) => set("courseTitle", event.target.value)} /></Field>
          <Field label="Course status"><select value={form.courseStatus} onChange={(event) => set("courseStatus", event.target.value as ProfileCourse["courseStatus"])}>{PROFILE_COURSE_STATUSES.map((value) => <option value={value} key={value}>{value.replaceAll("_", " ")}</option>)}</select></Field>
          <Field label="Term" hint="Free text such as 2024 秋 is accepted."><input value={form.term} onChange={(event) => set("term", event.target.value)} /></Field>
          <Field label="Completion date"><input type="date" value={form.completionDate} onChange={(event) => set("completionDate", event.target.value)} /></Field>
          <Field label="Credits as shown" hint="No conversion to U.S. semester credits."><input inputMode="decimal" value={form.credits} onChange={(event) => set("credits", event.target.value)} /></Field>
          <Field label="Numeric grade value"><input inputMode="decimal" value={form.gradeValue} onChange={(event) => set("gradeValue", event.target.value)} placeholder="92" /></Field>
          <Field label="Numeric grade scale"><input inputMode="decimal" value={form.gradeScale} onChange={(event) => set("gradeScale", event.target.value)} placeholder="100" /></Field>
          <Field label="Grade text" hint="A, 优秀, 良好, or other source text."><input value={form.gradeText} onChange={(event) => set("gradeText", event.target.value)} /></Field>
        </div>
        <p className="profile-disclosure">{PROFILE_SEMANTIC_COPY.inference.courseRepresentation}</p>
        <button className="primary-button" type="submit" disabled={pending}>{pending ? "Saving…" : "Save course"}</button>
      </fieldset>
    </form>
  );
}

function CompletenessSection({ document, mutate, pending }: Readonly<{ document: ProfileDocument; mutate: Mutate; pending: boolean }>) {
  const scopes = completenessScopes(document);
  return (
    <section>
      <SectionHeading eyebrow="COMPLETENESS" title="Declare what you can confirm" description="Completeness is your explicit statement about a defined data scope. It is not calculated from record counts and does not describe any program requirement." />
      <div className="profile-completeness-law"><strong>{PROFILE_SEMANTIC_COPY.completeness.law}</strong><span>{PROFILE_SEMANTIC_COPY.completeness.lawDetail}</span></div>
      <div className="profile-card-list">
        {scopes.map((scope) => <CompletenessCard key={scope.key} scope={scope} document={document} mutate={mutate} pending={pending} />)}
      </div>
    </section>
  );
}

function CompletenessCard({ scope, document, mutate, pending }: Readonly<{ scope: ProfileCompletenessScope; document: ProfileDocument; mutate: Mutate; pending: boolean }>) {
  const baselineValue = scope.completeness === "MISSING_DECLARATION" ? "UNKNOWN" : scope.completeness;
  const baselineExplanation = scope.explanation ?? "";
  const [value, setValue] = useState<"COMPLETE" | "PARTIAL" | "UNKNOWN">(baselineValue);
  const [explanation, setExplanation] = useState(baselineExplanation);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(scope.completeness === "MISSING_DECLARATION");
  const context = scope.educationContextId ? degreeLabel(document, scope.educationContextId) : "Profile-wide scope";
  const dirty = value !== baselineValue || explanation !== baselineExplanation;
  const formContextId = `${scope.educationContextId ?? "GLOBAL"}:${scope.domain}`;
  const dirtyKey = `COMPLETENESS:${formContextId}`;
  const recoveryPayload: CompletenessRecoveryPayload = { value, explanation };
  const reset = () => {
    setValue(baselineValue);
    setExplanation(baselineExplanation);
    setError(null);
    if (scope.completeness !== "MISSING_DECLARATION") setEditing(false);
  };
  const recovery = useProfileLocalRecovery({
    identity: {
      kind: "COMPLETENESS",
      profileVersionId: document.profileVersionId,
      versionNumber: document.versionNumber,
      currentRevision: document.revision,
      formContextId,
    },
    dirty,
    payload: recoveryPayload,
    apply: (payload) => { setValue(payload.value); setExplanation(payload.explanation); setEditing(true); },
    reset,
  });

  useProfileDirtyRegistration(dirtyKey, dirty, `Completeness: ${scope.domain}`, recovery.discard);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const normalizedExplanation = value === "COMPLETE" ? null : nullableText(explanation);
    if (value !== "COMPLETE" && !normalizedExplanation) {
      setError("Explain why this scope is PARTIAL or UNKNOWN.");
      return;
    }
    const success = await mutate("COMPLETENESS_UPSERT", { educationContextId: scope.educationContextId, domain: scope.domain, completeness: value, explanation: normalizedExplanation }, `Save ${PROFILE_DOMAIN_LABELS[scope.domain]} declaration`);
    if (success) { await recovery.clear(); setError(null); setEditing(false); }
  }

  return (
    <article className="profile-record-card completeness-card" data-completeness={scope.completeness}>
      <div className="profile-record-heading"><div><span className="field-label">{context}</span><h3>{PROFILE_DOMAIN_LABELS[scope.domain]}</h3></div><StatusPill value={scope.completeness} /></div>
      <p>{completenessDescription(scope.completeness)}</p>
      {scope.explanation ? <blockquote>{scope.explanation}</blockquote> : null}
      {!editing ? <button className="secondary-button" type="button" disabled={pending} onClick={() => setEditing(true)}>Change declaration</button> : (
        <form className="completeness-form" onSubmit={submit}>
          <FormErrorSummary message={error} />
          {recovery.candidate ? <RecoveryPrompt revisionChanged={recovery.candidate.revisionChanged} onRestore={recovery.restore} onDiscard={() => void recovery.discard()} /> : null}
          <fieldset disabled={recovery.candidate !== null}><legend>How complete is the {PROFILE_DOMAIN_LABELS[scope.domain].toLowerCase()} entered for this Profile?</legend>{PROFILE_COMPLETENESS_VALUES.map((option) => <label className="profile-radio" key={option}><input type="radio" name={`completeness-${scope.key}`} value={option} checked={value === option} onChange={() => { setValue(option); if (option === "COMPLETE") setExplanation(""); }} /><span><strong>{option}</strong><small>{completenessDescription(option)}</small></span></label>)}</fieldset>
          {value !== "COMPLETE" ? <Field label={`${value} explanation`}><textarea required rows={3} disabled={recovery.candidate !== null} value={explanation} onChange={(event) => setExplanation(event.target.value)} /></Field> : null}
          <div className="profile-inline-actions"><button className="primary-button" type="submit" disabled={pending || recovery.candidate !== null}>Save declaration</button>{dirty || scope.completeness !== "MISSING_DECLARATION" ? <button className="secondary-button" type="button" onClick={() => void recovery.discard()}>{PROFILE_SEMANTIC_COPY.unsaved.discard}</button> : null}</div>
        </form>
      )}
    </article>
  );
}

function ReviewSection({ document, pending, onFreeze }: Readonly<{ document: ProfileDocument; pending: boolean; onFreeze(): void }>) {
  const overview = profileOverview(document);
  const partial = overview.completenessScopes.filter((scope) => scope.completeness === "PARTIAL");
  const unknown = overview.completenessScopes.filter((scope) => scope.completeness === "UNKNOWN");
  const missing = overview.completenessScopes.filter((scope) => scope.completeness === "MISSING_DECLARATION");
  const [confirmed, setConfirmed] = useState(false);
  return (
    <section>
      <SectionHeading eyebrow="REVIEW & FREEZE" title="Review this exact Profile version" description="The backend remains the final authority for freeze. This page explains the current authoritative document and its declared gaps." />
      <div className="profile-review-banner"><div><span className="field-label">Version</span><strong>Draft v{document.versionNumber}</strong></div><div><span className="field-label">Revision</span><strong>{document.revision}</strong></div><div><span className="field-label">Freeze readiness</span><StatusPill value={document.readiness.freezeReady ? "READY" : "MISSING_DECLARATION"} /></div></div>
      <div className="profile-two-column">
        <ReviewList title="Profile records" items={[`${overview.counts.sources} Sources`, `${overview.counts.education} Education records`, `${overview.counts.courses} Course records`]} />
        <ReviewList title={PROFILE_SEMANTIC_COPY.unsupported.reviewHeading} items={["Tests", "Experience", "Skills", "Goals", "Preferences"]} />
      </div>
      <article className="profile-section-card">
        <h3>Completeness declarations</h3>
        <div className="profile-review-scopes">{overview.completenessScopes.map((scope) => <div key={scope.key}><span>{PROFILE_DOMAIN_LABELS[scope.domain]}<small>{scope.educationContextId ? degreeLabel(document, scope.educationContextId) : "Profile-wide"}</small></span><StatusPill value={scope.completeness} /></div>)}</div>
        {partial.length > 0 ? <InlineNote>{partial.length} scope{partial.length === 1 ? " is" : "s are"} PARTIAL. This warning does not itself block freeze.</InlineNote> : null}
        {unknown.length > 0 ? <InlineNote>{unknown.length} scope{unknown.length === 1 ? " is" : "s are"} UNKNOWN. This warning does not itself block freeze.</InlineNote> : null}
        {missing.length > 0 ? <div className="profile-blocker" role="status">{missing.length} required declaration{missing.length === 1 ? " is" : "s are"} missing. The UI disables freeze for this authoritative reason.</div> : null}
      </article>
      <article className="profile-section-card">
        <h3>Mapping readiness</h3>
        {document.readiness.mappingReadiness.length === 0 ? <p>No Degree or Course mapping state is present.</p> : <div className="profile-review-scopes">{document.readiness.mappingReadiness.map((mapping) => <div key={`${mapping.recordType}-${mapping.recordId}`}><span>{mapping.recordType === "DEGREE" ? degreeLabel(document, mapping.recordId) : courses(document).find((course) => course.courseId === mapping.recordId)?.courseTitle ?? "Course record"}<small>{PROFILE_SEMANTIC_COPY.mapping.unavailable}</small></span><StatusPill value={mapping.verified ? "VERIFIED" : mapping.mappingStatuses[0] ?? "UNKNOWN"} /></div>)}</div>}
        <p className="profile-card-note">{PROFILE_SEMANTIC_COPY.mapping.noInference}</p>
      </article>
      <article className="profile-freeze-card">
        <h3>{PROFILE_SEMANTIC_COPY.reviewFreeze.heading}</h3>
        <p>{PROFILE_SEMANTIC_COPY.reviewFreeze.explanation}</p>
        <p>{PROFILE_SEMANTIC_COPY.reviewFreeze.warning}</p>
        <label className="profile-confirm-check"><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /><span>{PROFILE_SEMANTIC_COPY.reviewFreeze.confirmation}</span></label>
        <button className="primary-button freeze-button" type="button" disabled={pending || !document.readiness.freezeReady || !confirmed} onClick={onFreeze}>{pending ? "Freezing…" : "Freeze this Profile version"}</button>
        {!document.readiness.freezeReady ? <small>Complete every required declaration before requesting freeze. PARTIAL and UNKNOWN are allowed when explained.</small> : null}
      </article>
    </section>
  );
}

function ReviewList({ title, items }: Readonly<{ title: string; items: readonly string[] }>) {
  return <article className="profile-section-card"><h3>{title}</h3><ul className="profile-review-list">{items.map((item) => <li key={item}>{item}</li>)}</ul></article>;
}

function FrozenProfileView({ document, state }: Readonly<{ document: ProfileDocument; state: UiState }>) {
  const overview = profileOverview(document);
  return (
    <div className="profile-frozen-view" data-testid="profile-frozen-view">
      <ProfileLiveStatus state={state} />
      <header className="profile-frozen-hero"><div><p className="eyebrow">{PROFILE_SEMANTIC_COPY.frozen.heading}</p><h2>Frozen v{document.versionNumber}</h2><p>{PROFILE_SEMANTIC_COPY.frozen.explanation}</p></div><StatusPill value={PROFILE_SEMANTIC_COPY.frozen.status} /></header>
      <div className="profile-review-banner"><div><span className="field-label">Frozen at</span><strong>{document.frozenAt ? new Date(document.frozenAt).toLocaleString() : "Unavailable"}</strong></div><div><span className="field-label">Sources</span><strong>{overview.counts.sources}</strong></div><div><span className="field-label">Education / Courses</span><strong>{overview.counts.education} / {overview.counts.courses}</strong></div></div>
      <div className="profile-two-column"><ReviewList title="Source provenance" items={evidenceItems(document).map((source) => `${source.evidenceType.replaceAll("_", " ")} — ${source.locator ?? "No reference entered"}`)} /><ReviewList title="Education" items={degrees(document).map((degree) => `${degree.institutionName} — ${degree.degreeName}`)} /></div>
      <article className="profile-section-card"><h3>Courses</h3>{courses(document).length === 0 ? <p>No Course records were stored.</p> : <ul className="profile-review-list">{courses(document).map((course) => <li key={course.courseId}>{course.courseTitle} · {course.gradeText ?? (course.gradeValue === null ? "No grade entered" : `${course.gradeValue} / ${course.gradeScale}`)}</li>)}</ul>}</article>
      <article className="profile-section-card"><h3>Completeness declarations</h3><div className="profile-review-scopes">{overview.completenessScopes.map((scope) => <div key={scope.key}><span>{PROFILE_DOMAIN_LABELS[scope.domain]}<small>{scope.explanation ?? completenessDescription(scope.completeness)}</small></span><StatusPill value={scope.completeness} /></div>)}</div></article>
      <InlineNote>Historical frozen-version discovery is not available in this MVP. This immediate view is available from the freeze response, but a refresh or later sign-in cannot currently rediscover it.</InlineNote>
      <p className="profile-disclosure">{PROFILE_SEMANTIC_COPY.frozen.disclosure}</p>
    </div>
  );
}

function EmptyMessage({ children }: Readonly<{ children: ReactNode }>) {
  return <div className="profile-empty-message">{children}</div>;
}

function InlineNote({ children }: Readonly<{ children: ReactNode }>) {
  return <div className="profile-inline-note" role="note">{children}</div>;
}
