// lib/api.ts — All calls to the ARDOR backend REST API
// One function per endpoint. Throws on non-2xx responses so callers can handle errors cleanly.

const BASE_URL = process.env.EXPO_PUBLIC_API_URL ?? "http://localhost:8000";

export interface LearningPoint {
  concept: string;
  why_it_matters: string;
  practical_use: string;
}

export interface Article {
  id: string;
  title: string;
  source: "tldr" | "tldr_ai" | "dailyfin";
  original_url: string;
  summary: string;
  learning_points: LearningPoint[];
  conversation_tip: string;
  tags: string[];
  audio_url: string | null;
  published_at: string;
  created_at: string;
}

export interface PlaylistItem {
  id: string;
  title: string;
  source: string;
  audio_url: string;
}

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (!res.ok) {
    throw new Error(`API ${path} returned ${res.status}`);
  }
  return res.json();
}

export function getTodaysArticles(): Promise<{ articles: Article[]; count: number }> {
  return request("/api/articles/today");
}

export function getPlaylist(): Promise<{ playlist: PlaylistItem[]; count: number }> {
  return request("/api/audio/playlist");
}

export function triggerFetchNow(): Promise<{ status: string; message: string }> {
  return request("/api/fetch-now", { method: "POST" });
}
