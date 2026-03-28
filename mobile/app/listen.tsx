// app/listen.tsx — Audio playlist screen
// Plays today's articles one after another, like a podcast.
// Auto-advances to next article when current one finishes.
// Uses expo-av for audio playback.

import React, { useEffect, useRef, useState } from "react";
import {
  View, Text, TouchableOpacity, StyleSheet, ActivityIndicator,
} from "react-native";
import { useRouter } from "expo-router";
import { Audio } from "expo-av";
import { Ionicons } from "@expo/vector-icons";
import { getPlaylist, PlaylistItem } from "../lib/api";

const SOURCE_LABEL: Record<string, string> = {
  tldr: "TLDR", tldr_ai: "TLDR AI", dailyfin: "DailyFin",
};
const SOURCE_COLOR: Record<string, string> = {
  tldr: "#3B82F6", tldr_ai: "#8B5CF6", dailyfin: "#10B981",
};

export default function ListenScreen() {
  const router = useRouter();
  const soundRef = useRef<Audio.Sound | null>(null);
  const [playlist, setPlaylist] = useState<PlaylistItem[]>([]);
  const [index, setIndex] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const [duration, setDuration] = useState(0);
  const [position, setPosition] = useState(0);
  const [loading, setLoading] = useState(true);
  const [audioLoading, setAudioLoading] = useState(false);

  useEffect(() => {
    getPlaylist().then((d) => setPlaylist(d.playlist)).finally(() => setLoading(false));
    return () => { soundRef.current?.unloadAsync(); };
  }, []);

  useEffect(() => {
    // Auto-load and play when index changes (handles auto-advance)
    if (playlist.length > 0 && !loading) {
      loadAndPlay(index);
    }
  }, [index, playlist]);

  async function loadAndPlay(i: number) {
    setAudioLoading(true);
    await soundRef.current?.unloadAsync();
    soundRef.current = null;

    try {
      await Audio.setAudioModeAsync({ playsInSilentModeIOS: true });
      const { sound } = await Audio.Sound.createAsync(
        { uri: playlist[i].audio_url },
        { shouldPlay: true },
        (status) => {
          if (!status.isLoaded) return;
          setPosition(status.positionMillis);
          setDuration(status.durationMillis ?? 0);
          setProgress(status.durationMillis ? status.positionMillis / status.durationMillis : 0);
          setPlaying(status.isPlaying);
          // Auto-advance when article ends
          if (status.didJustFinish && i < playlist.length - 1) {
            setIndex((prev) => prev + 1);
          }
        }
      );
      soundRef.current = sound;
      setPlaying(true);
    } catch (e) {
      setPlaying(false);
    } finally {
      setAudioLoading(false);
    }
  }

  async function togglePlay() {
    if (!soundRef.current) return;
    playing ? await soundRef.current.pauseAsync() : await soundRef.current.playAsync();
  }

  function fmt(ms: number) {
    const s = Math.floor(ms / 1000);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  }

  if (loading) {
    return <View style={styles.center}><ActivityIndicator size="large" color="#FF6B2B" /></View>;
  }

  if (playlist.length === 0) {
    return (
      <View style={styles.center}>
        <Text style={styles.empty}>No audio available today.{"\n"}Run the pipeline first.</Text>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <Text style={styles.backText}>← Back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const current = playlist[index];
  const color = SOURCE_COLOR[current.source] ?? "#FF6B2B";

  return (
    <View style={styles.screen}>
      {/* Back */}
      <TouchableOpacity onPress={() => router.back()} style={styles.topBack}>
        <Ionicons name="arrow-back" size={24} color="#EEEEF5" />
      </TouchableOpacity>

      {/* Source badge */}
      <View style={[styles.badge, { backgroundColor: color + "22" }]}>
        <Text style={[styles.badgeText, { color }]}>{SOURCE_LABEL[current.source] ?? current.source}</Text>
      </View>

      {/* Current article title */}
      <Text style={styles.title}>{current.title}</Text>

      {/* Track counter */}
      <Text style={styles.counter}>{index + 1} / {playlist.length}</Text>

      {/* Progress bar */}
      <View style={styles.track}>
        <View style={[styles.fill, { width: `${progress * 100}%` }]} />
      </View>
      <View style={styles.timeRow}>
        <Text style={styles.time}>{fmt(position)}</Text>
        <Text style={styles.time}>{fmt(duration)}</Text>
      </View>

      {/* Controls */}
      <View style={styles.controls}>
        <TouchableOpacity onPress={() => setIndex((i) => Math.max(0, i - 1))} disabled={index === 0}>
          <Ionicons name="play-skip-back" size={36} color={index === 0 ? "#3A3E55" : "#EEEEF5"} />
        </TouchableOpacity>

        <TouchableOpacity onPress={togglePlay} style={styles.playBtn}>
          {audioLoading
            ? <ActivityIndicator color="#FFFFFF" size="large" />
            : <Ionicons name={playing ? "pause" : "play"} size={36} color="#FFFFFF" />
          }
        </TouchableOpacity>

        <TouchableOpacity
          onPress={() => setIndex((i) => Math.min(playlist.length - 1, i + 1))}
          disabled={index === playlist.length - 1}
        >
          <Ionicons name="play-skip-forward" size={36} color={index === playlist.length - 1 ? "#3A3E55" : "#EEEEF5"} />
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: "#1C2033", padding: 28, paddingTop: 60, alignItems: "center" },
  center: { flex: 1, backgroundColor: "#1C2033", alignItems: "center", justifyContent: "center", padding: 24 },
  topBack: { alignSelf: "flex-start", marginBottom: 40 },
  badge: { borderRadius: 6, paddingHorizontal: 12, paddingVertical: 4, marginBottom: 20 },
  badgeText: { fontSize: 12, fontWeight: "700", letterSpacing: 1 },
  title: { color: "#EEEEF5", fontSize: 20, fontWeight: "600", textAlign: "center", lineHeight: 28, marginBottom: 12 },
  counter: { color: "#8B8FAF", fontSize: 14, marginBottom: 32 },
  track: { width: "100%", height: 4, backgroundColor: "#262A40", borderRadius: 2, marginBottom: 8 },
  fill: { height: 4, backgroundColor: "#FF6B2B", borderRadius: 2 },
  timeRow: { flexDirection: "row", justifyContent: "space-between", width: "100%", marginBottom: 40 },
  time: { color: "#8B8FAF", fontSize: 12 },
  controls: { flexDirection: "row", alignItems: "center", gap: 40 },
  playBtn: { backgroundColor: "#FF6B2B", width: 72, height: 72, borderRadius: 36, alignItems: "center", justifyContent: "center" },
  empty: { color: "#8B8FAF", textAlign: "center", fontSize: 16, lineHeight: 24, marginBottom: 24 },
  backBtn: { padding: 12 },
  backText: { color: "#FF6B2B", fontSize: 16 },
});
