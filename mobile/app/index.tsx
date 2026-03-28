// app/index.tsx — Home screen
// Shows ARDOR logo, today's date, article count, and two big action buttons.
// LISTEN plays the audio playlist. READ opens the scrollable article list.
// Colors extracted from Logo.jpeg: dark navy bg, fire orange + golden accent.

import React, { useEffect, useState } from "react";
import {
  View, Text, TouchableOpacity, StyleSheet, Image, ActivityIndicator,
} from "react-native";
import { useRouter } from "expo-router";
import { getTodaysArticles } from "../lib/api";

function todayLabel() {
  return new Date().toLocaleDateString("en-US", {
    weekday: "long", month: "long", day: "numeric",
  });
}

export default function HomeScreen() {
  const router = useRouter();
  const [count, setCount] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getTodaysArticles()
      .then((data) => setCount(data.count))
      .catch(() => setCount(0))
      .finally(() => setLoading(false));
  }, []);

  const hasArticles = count !== null && count > 0;

  return (
    <View style={styles.screen}>
      {/* Logo */}
      <Image source={require("../assets/logo.jpeg")} style={styles.logo} resizeMode="contain" />

      {/* App name */}
      <Text style={styles.appName}>ARDOR</Text>
      <Text style={styles.tagline}>Your daily tech briefing</Text>

      {/* Date + article count */}
      <Text style={styles.date}>{todayLabel()}</Text>
      {loading ? (
        <ActivityIndicator color="#F5A623" style={{ marginVertical: 8 }} />
      ) : (
        <Text style={styles.count}>
          {hasArticles ? `${count} articles today` : "No articles yet today"}
        </Text>
      )}

      {/* Action buttons */}
      <View style={styles.buttons}>
        <TouchableOpacity
          style={[styles.btn, styles.btnPrimary, !hasArticles && styles.btnDisabled]}
          onPress={() => router.push("/listen")}
          disabled={!hasArticles}
          activeOpacity={0.8}
        >
          <Text style={styles.btnIcon}>🎧</Text>
          <Text style={styles.btnLabelPrimary}>LISTEN</Text>
          <Text style={styles.btnSub}>Play all as audio</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.btn, styles.btnSecondary, !hasArticles && styles.btnDisabled]}
          onPress={() => router.push("/read")}
          disabled={!hasArticles}
          activeOpacity={0.8}
        >
          <Text style={styles.btnIcon}>📰</Text>
          <Text style={styles.btnLabelSecondary}>READ</Text>
          <Text style={styles.btnSubSecondary}>Browse all articles</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: "#1C2033",
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 28,
    paddingBottom: 40,
  },
  logo: { width: 100, height: 100, borderRadius: 22, marginBottom: 16 },
  appName: {
    color: "#EEEEF5",
    fontSize: 36,
    fontWeight: "800",
    letterSpacing: 8,
    marginBottom: 4,
  },
  tagline: { color: "#8B8FAF", fontSize: 14, marginBottom: 28 },
  date: { color: "#EEEEF5", fontSize: 18, fontWeight: "500", marginBottom: 6 },
  count: { color: "#8B8FAF", fontSize: 15, marginBottom: 40 },
  buttons: { width: "100%", gap: 14 },
  btn: {
    borderRadius: 18,
    paddingVertical: 22,
    alignItems: "center",
    paddingHorizontal: 20,
  },
  btnPrimary: { backgroundColor: "#FF6B2B" },
  btnSecondary: { backgroundColor: "#262A40", borderWidth: 1.5, borderColor: "#F5A623" },
  btnDisabled: { opacity: 0.4 },
  btnIcon: { fontSize: 28, marginBottom: 4 },
  btnLabelPrimary: { color: "#FFFFFF", fontSize: 22, fontWeight: "800", letterSpacing: 3 },
  btnLabelSecondary: { color: "#F5A623", fontSize: 22, fontWeight: "800", letterSpacing: 3 },
  btnSub: { color: "#FFD4C2", fontSize: 13, marginTop: 2 },
  btnSubSecondary: { color: "#8B8FAF", fontSize: 13, marginTop: 2 },
});
