"use client";

import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";

import { clearAllProfileRecovery } from "@/lib/profile/profile-recovery";
import { PROFILE_SEMANTIC_COPY } from "@/lib/profile/semantic-copy";

type DirtyEntry = Readonly<{
  label: string;
  discard(): void | Promise<void>;
}>;

type DiscardRequest = Readonly<{
  message: string;
  keys?: readonly string[];
}>;

type PendingDiscard = Readonly<{
  message: string;
  keys: readonly string[];
  resolve(confirmed: boolean): void;
}>;

type ProfileSafetyContextValue = Readonly<{
  registerDirty(key: string, dirty: boolean, entry: DirtyEntry): void;
  unregisterDirty(key: string): void;
  requestDiscard(request: DiscardRequest): Promise<boolean>;
  clearRecoveryAfterSessionEnd(): void;
}>;

const ProfileSafetyContext = createContext<ProfileSafetyContextValue | null>(null);

function samePage(left: URL, right: URL): boolean {
  return left.origin === right.origin && left.pathname === right.pathname && left.search === right.search && left.hash === right.hash;
}

export function ProfileSafetyProvider({ children }: Readonly<{ children: ReactNode }>) {
  const dirtyEntries = useRef(new Map<string, DirtyEntry>());
  const [pending, setPending] = useState<PendingDiscard | null>(null);

  const registerDirty = useCallback((key: string, dirty: boolean, entry: DirtyEntry) => {
    if (dirty) dirtyEntries.current.set(key, entry);
    else dirtyEntries.current.delete(key);
  }, []);

  const unregisterDirty = useCallback((key: string) => {
    dirtyEntries.current.delete(key);
  }, []);

  const requestDiscard = useCallback((request: DiscardRequest): Promise<boolean> => {
    const keys = request.keys ?? [...dirtyEntries.current.keys()];
    if (!keys.some((key) => dirtyEntries.current.has(key))) return Promise.resolve(true);
    return new Promise<boolean>((resolve) => {
      setPending((current) => {
        if (current) {
          resolve(false);
          return current;
        }
        return Object.freeze({ message: request.message, keys: Object.freeze([...keys]), resolve });
      });
    });
  }, []);

  const cancelDiscard = useCallback(() => {
    setPending((current) => {
      current?.resolve(false);
      return null;
    });
  }, []);

  const confirmDiscard = useCallback(async () => {
    const current = pending;
    if (!current) return;
    setPending(null);
    const entries = current.keys.map((key) => dirtyEntries.current.get(key)).filter((entry): entry is DirtyEntry => entry !== undefined);
    await Promise.all(entries.map((entry) => entry.discard()));
    current.resolve(true);
  }, [pending]);

  const clearRecoveryAfterSessionEnd = useCallback(() => {
    if (typeof window !== "undefined") clearAllProfileRecovery(window.sessionStorage);
  }, []);

  useEffect(() => {
    const warn = (event: BeforeUnloadEvent) => {
      if (dirtyEntries.current.size === 0) return;
      event.preventDefault();
      event.returnValue = "";
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, []);

  useEffect(() => {
    const protectSameOriginLink = (event: MouseEvent) => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || dirtyEntries.current.size === 0) return;
      const target = event.target;
      if (!(target instanceof Element)) return;
      const anchor = target.closest<HTMLAnchorElement>("a[href]");
      if (!anchor || anchor.target === "_blank" || anchor.hasAttribute("download")) return;
      const destination = new URL(anchor.href, window.location.href);
      const current = new URL(window.location.href);
      if (destination.origin !== current.origin || samePage(destination, current)) return;
      event.preventDefault();
      void requestDiscard({ message: PROFILE_SEMANTIC_COPY.unsaved.navigation }).then((confirmed) => {
        if (!confirmed) return;
        clearAllProfileRecovery(window.sessionStorage);
        window.location.assign(destination.href);
      });
    };
    document.addEventListener("click", protectSameOriginLink, true);
    return () => document.removeEventListener("click", protectSameOriginLink, true);
  }, [requestDiscard]);

  const value = useMemo<ProfileSafetyContextValue>(() => ({
    registerDirty,
    unregisterDirty,
    requestDiscard,
    clearRecoveryAfterSessionEnd,
  }), [clearRecoveryAfterSessionEnd, registerDirty, requestDiscard, unregisterDirty]);

  return (
    <ProfileSafetyContext.Provider value={value}>
      {children}
      {pending ? (
        <div className="profile-dialog-backdrop">
          <div className="profile-dialog" role="dialog" aria-modal="true" aria-labelledby="profile-unsaved-dialog-title" data-testid="profile-unsaved-dialog">
            <h2 id="profile-unsaved-dialog-title">{PROFILE_SEMANTIC_COPY.unsaved.title}</h2>
            <p>{pending.message}</p>
            <div className="profile-dialog-actions">
              <button className="secondary-button" type="button" autoFocus onClick={cancelDiscard}>{PROFILE_SEMANTIC_COPY.unsaved.keepEditing}</button>
              <button className="danger-button" type="button" onClick={() => void confirmDiscard()}>{PROFILE_SEMANTIC_COPY.unsaved.discard}</button>
            </div>
          </div>
        </div>
      ) : null}
    </ProfileSafetyContext.Provider>
  );
}

export function useProfileSafety(): ProfileSafetyContextValue {
  const value = useContext(ProfileSafetyContext);
  if (!value) throw new Error("PROFILE_SAFETY_PROVIDER_REQUIRED");
  return value;
}

export function useOptionalProfileSafety(): ProfileSafetyContextValue | null {
  return useContext(ProfileSafetyContext);
}

export function useProfileDirtyRegistration(
  key: string,
  dirty: boolean,
  label: string,
  discard: () => void | Promise<void>,
): void {
  const safety = useProfileSafety();

  useEffect(() => {
    safety.registerDirty(key, dirty, Object.freeze({ label, discard }));
    return () => safety.unregisterDirty(key);
  }, [dirty, key, label, safety, discard]);
}

export function RecoveryPrompt({ revisionChanged, onRestore, onDiscard }: Readonly<{
  revisionChanged: boolean;
  onRestore(): void;
  onDiscard(): void;
}>) {
  return (
    <div className="profile-conflict-card" role="status" data-testid="profile-recovery-prompt">
      <strong>{PROFILE_SEMANTIC_COPY.recovery.title}</strong>
      <p>{PROFILE_SEMANTIC_COPY.recovery.body}</p>
      {revisionChanged ? <p>{PROFILE_SEMANTIC_COPY.recovery.staleBody}</p> : null}
      <div className="profile-inline-actions">
        <button className="primary-button" type="button" onClick={onRestore}>{PROFILE_SEMANTIC_COPY.recovery.restore}</button>
        <button className="secondary-button" type="button" onClick={onDiscard}>{PROFILE_SEMANTIC_COPY.recovery.discard}</button>
      </div>
    </div>
  );
}
