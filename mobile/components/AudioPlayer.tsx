// components/AudioPlayer.tsx — Simple play/pause + progress bar for article audio
// Uses expo-av. Loads audio from a URL (Supabase Storage).
// Auto-unloads when the component unmounts to avoid memory leaks.

import React, { useEffect, useRef, useState } from "react";
import { View, Text, TouchableOpacity, StyleSheet } from "react-native";
import { Audio } from "expo-av";
import { Ionicons } from "@expo/vector-icons";

interface Props {
  audioUrl: string;
}

export default function AudioPlayer({ audioUrl }: Props) {
  const soundRef = useRef<Audio.Sound | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [progress, setProgress] = useState(0); // 0–1
  const [duration, setDuration] = useState(0);  // ms
  const [position, setPosition] = useState(0);  // ms
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    return () => {
      // Unload audio when component unmounts (e.g. navigating away)
      soundRef.current?.unloadAsync();
    };
  }, []);

  async function handlePlayPause() {
    if (loading) return;

    if (!soundRef.current) {
      // First tap — load and play
      setLoading(true);
      try {
        await Audio.setAudioModeAsync({ playsInSilentModeIOS: true });
        const { sound } = await Audio.Sound.createAsync(
          { uri: audioUrl },
          { shouldPlay: true },
          (status) => {
            if (status.isLoaded) {
              setPosition(status.positionMillis);
              setDuration(status.durationMillis ?? 0);
              setProgress(status.durationMillis ? status.positionMillis / status.durationMillis : 0);
              setIsPlaying(status.isPlaying);
              if (status.didJustFinish) {
                setIsPlaying(false);
                setProgress(0);
              }
            }
          }
        );
        soundRef.current = sound;
        setIsPlaying(true);
      } catch {
        // Audio load failed — could be network issue
      } finally {
        setLoading(false);
      }
      return;
    }

    // Already loaded — just toggle
    if (isPlaying) {
      await soundRef.current.pauseAsync();
    } else {
      await soundRef.current.playAsync();
    }
  }

  function formatTime(ms: number) {
    const s = Math.floor(ms / 1000);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  }

  return (
    <View style={styles.container}>
      <TouchableOpacity onPress={handlePlayPause} style={styles.button} activeOpacity={0.8}>
        <Ionicons
          name={loading ? "hourglass-outline" : isPlaying ? "pause-circle" : "play-circle"}
          size={44}
          color="#F59E0B"
        />
      </TouchableOpacity>

      <View style={styles.right}>
        {/* Progress bar */}
        <View style={styles.track}>
          <View style={[styles.fill, { width: `${progress * 100}%` }]} />
        </View>
        <Text style={styles.time}>
          {formatTime(position)} / {formatTime(duration)}
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flexDirection: "row", alignItems: "center", gap: 12, paddingVertical: 8 },
  button: { padding: 4 },
  right: { flex: 1, gap: 4 },
  track: { height: 4, backgroundColor: "#2A3441", borderRadius: 2 },
  fill: { height: 4, backgroundColor: "#F59E0B", borderRadius: 2 },
  time: { color: "#6B7280", fontSize: 12 },
});
