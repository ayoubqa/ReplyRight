"use client";

import { useCallback, useSyncExternalStore } from "react";
import { DEFAULT_PROFILE, profileSchema, type CommunicationProfile } from "@/lib/domain/profile";

/**
 * Storage abstraction for the communication profile. The MVP keeps it on the
 * device (localStorage). When authentication lands, add a remote store that
 * implements the same interface (e.g. backed by Supabase).
 */
export interface ProfileStore {
  load(): CommunicationProfile;
  save(profile: CommunicationProfile): void;
  subscribe(listener: () => void): () => void;
}

const STORAGE_KEY = "replyright.profile.v1";

function createLocalProfileStore(): ProfileStore {
  const listeners = new Set<() => void>();
  let cache: CommunicationProfile | null = null;

  const read = (): CommunicationProfile => {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (!raw) return DEFAULT_PROFILE;
      const parsed = profileSchema.safeParse({ ...DEFAULT_PROFILE, ...JSON.parse(raw) });
      return parsed.success ? parsed.data : DEFAULT_PROFILE;
    } catch {
      return DEFAULT_PROFILE;
    }
  };

  return {
    load() {
      if (!cache) cache = read();
      return cache;
    },
    save(profile) {
      cache = profile;
      try {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(profile));
      } catch {
        // Storage can be unavailable (private mode, quota). Keep the in-memory copy.
      }
      listeners.forEach((l) => l());
    },
    subscribe(listener) {
      listeners.add(listener);
      const onStorage = (event: StorageEvent) => {
        if (event.key === STORAGE_KEY) {
          cache = null;
          listener();
        }
      };
      window.addEventListener("storage", onStorage);
      return () => {
        listeners.delete(listener);
        window.removeEventListener("storage", onStorage);
      };
    },
  };
}

let store: ProfileStore | null = null;
function getStore(): ProfileStore {
  if (!store) store = createLocalProfileStore();
  return store;
}

const serverSnapshot = () => DEFAULT_PROFILE;

/** Returns `[profile, save, hydrated]`. `hydrated` is false during SSR/first paint. */
export function useProfile(): [CommunicationProfile, (p: CommunicationProfile) => void, boolean] {
  const profile = useSyncExternalStore(
    (listener) => getStore().subscribe(listener),
    () => getStore().load(),
    serverSnapshot,
  );
  const hydrated = useSyncExternalStore(
    noopSubscribe,
    () => true,
    () => false,
  );
  const save = useCallback((p: CommunicationProfile) => getStore().save(p), []);
  return [profile, save, hydrated];
}

const noopSubscribe = () => () => {};
