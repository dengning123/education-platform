"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import {
  clearProfileRecovery,
  loadProfileRecovery,
  saveProfileRecovery,
  type ProfileRecoveryCandidate,
  type ProfileRecoveryIdentity,
  type ProfileRecoveryKind,
  type ProfileRecoveryPayloads,
} from "./profile-recovery";

export function useProfileLocalRecovery<Kind extends ProfileRecoveryKind>(options: Readonly<{
  identity: ProfileRecoveryIdentity & Readonly<{ kind: Kind }>;
  dirty: boolean;
  payload: ProfileRecoveryPayloads[Kind];
  apply(payload: ProfileRecoveryPayloads[Kind]): void;
  reset(): void;
}>) {
  const [candidate, setCandidate] = useState<ProfileRecoveryCandidate<Kind> | null>(null);
  const wasDirty = useRef(false);
  const capturedRevision = useRef<number | null>(null);
  const { currentRevision, formContextId, kind, profileVersionId, versionNumber } = options.identity;
  const identityKey = `${kind}:${profileVersionId}:${versionNumber}:${formContextId}`;
  const identity = useMemo(() => ({ currentRevision, formContextId, kind, profileVersionId, versionNumber }), [
    currentRevision,
    formContextId,
    kind,
    profileVersionId,
    versionNumber,
  ]);

  useEffect(() => {
    let active = true;
    let expiryTimer: ReturnType<typeof setTimeout> | null = null;
    void loadProfileRecovery(window.sessionStorage, identity).then((loaded) => {
      if (!active || !loaded) return;
      setCandidate(loaded);
      expiryTimer = setTimeout(() => {
        setCandidate(null);
        void clearProfileRecovery(window.sessionStorage, identity);
      }, Math.max(0, loaded.expiresAt - Date.now()));
    });
    return () => {
      active = false;
      if (expiryTimer) clearTimeout(expiryTimer);
    };
  }, [identity, identityKey]);

  useEffect(() => {
    if (!options.dirty) {
      if (wasDirty.current) {
        wasDirty.current = false;
        capturedRevision.current = null;
        void clearProfileRecovery(window.sessionStorage, identity);
      }
      return;
    }
    if (!wasDirty.current) {
      wasDirty.current = true;
      capturedRevision.current ??= identity.currentRevision;
    }
    if (candidate) return;
    const timer = setTimeout(() => {
      void saveProfileRecovery(
        window.sessionStorage,
        identity,
        options.payload,
        capturedRevision.current ?? identity.currentRevision,
      );
    }, 75);
    return () => clearTimeout(timer);
  }, [candidate, identity, identityKey, options.dirty, options.payload]);

  const restore = useCallback(() => {
    if (!candidate) return;
    capturedRevision.current = candidate.capturedRevision;
    options.apply(candidate.payload);
    setCandidate(null);
  }, [candidate, options]);

  const discard = useCallback(async () => {
    await clearProfileRecovery(window.sessionStorage, identity);
    capturedRevision.current = null;
    wasDirty.current = false;
    setCandidate(null);
    options.reset();
  }, [identity, options]);

  const clear = useCallback(async () => {
    await clearProfileRecovery(window.sessionStorage, identity);
    capturedRevision.current = null;
    wasDirty.current = false;
    setCandidate(null);
  }, [identity]);

  return { candidate, restore, discard, clear };
}
