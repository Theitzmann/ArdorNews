// app/read.tsx — Scrollable article list grouped by source
// Each article shows: source badge, title, full summary, expandable learning points,
// conversation tip (highlighted box), and tags.
// Grouped: TLDR section → TLDR AI section → DailyFin section.

import React, { useCallback, useState } from "react";
import {
  View, Text, ScrollView, StyleSheet, TouchableOpacity,
  RefreshControl, ActivityIndicator, Alert, Clipboard,
} from "react-native";
import { useFocusEffect, useRouter } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { getTodaysArticles, Article } from "../lib/api";

const SOURCE_ORDER = ["tldr", "tldr_ai", "dailyfin"];
const SOURCE_META: Record<string, { label: string; color: string }> = {
  tldr:    { label: "TLDR",     color: "#3B82F6" },
  tldr_ai: { label: "TLDR AI",  color: "#8B5CF6" },
  dailyfin:{ label: "DailyFin", color: "#10B981" },
};

export default function ReadScreen() {
  const router = useRouter();
  const [articles, setArticles] = useState<Article[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

  async function load(silent = false) {
    if (!silent) setLoading(true);
    try {
      const data = await getTodaysArticles();
      setArticles(data.articles);
    } catch {
      // Keep existing articles on refresh failure
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }

  useFocusEffect(useCallback(() => { load(true); }, []));

  function toggleExpand(id: string) {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }

  function copyTip(tip: string) {
    Clipboard.setString(tip);
    Alert.alert("Copied!", "Conversation tip copied to clipboard.");
  }

  if (loading) {
    return <View style={styles.center}><ActivityIndicator size="large" color="#FF6B2B" /></View>;
  }

  // Group by source, maintaining display order
  const grouped = SOURCE_ORDER.reduce<Record<string, Article[]>>((acc, src) => {
    const group = articles.filter((a) => a.source === src);
    if (group.length > 0) acc[src] = group;
    return acc;
  }, {});

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      refreshControl={
        <RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); load(true); }} tintColor="#FF6B2B" />
      }
    >
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={24} color="#EEEEF5" />
        </TouchableOpacity>
        <Text style={styles.heading}>Today's Articles</Text>
      </View>

      {articles.length === 0 && (
        <Text style={styles.empty}>No articles yet today.{"\n"}Pull down to refresh.</Text>
      )}

      {/* Grouped sections */}
      {Object.entries(grouped).map(([source, group]) => {
        const meta = SOURCE_META[source] ?? { label: source, color: "#8B8FAF" };
        return (
          <View key={source} style={styles.section}>
            <View style={[styles.sectionHeader, { borderLeftColor: meta.color }]}>
              <Text style={[styles.sectionTitle, { color: meta.color }]}>{meta.label}</Text>
              <Text style={styles.sectionCount}>{group.length} articles</Text>
            </View>

            {group.map((article) => (
              <ArticleCard
                key={article.id}
                article={article}
                expanded={expandedIds.has(article.id)}
                onToggle={() => toggleExpand(article.id)}
                onCopyTip={() => copyTip(article.conversation_tip)}
                accentColor={meta.color}
              />
            ))}
          </View>
        );
      })}
    </ScrollView>
  );
}

// ─── Article card (inline — only used here) ───────────────────────────────────

function ArticleCard({ article, expanded, onToggle, onCopyTip, accentColor }: {
  article: Article;
  expanded: boolean;
  onToggle: () => void;
  onCopyTip: () => void;
  accentColor: string;
}) {
  return (
    <View style={styles.card}>
      <Text style={styles.cardTitle}>{article.title}</Text>
      <Text style={styles.cardSummary}>{article.summary}</Text>

      {/* Learning points toggle */}
      {article.learning_points?.length > 0 && (
        <TouchableOpacity style={styles.expandRow} onPress={onToggle}>
          <Text style={[styles.expandLabel, { color: accentColor }]}>
            {expanded ? "Hide" : "Show"} key concepts ({article.learning_points.length})
          </Text>
          <Ionicons name={expanded ? "chevron-up" : "chevron-down"} size={14} color={accentColor} />
        </TouchableOpacity>
      )}

      {expanded && (
        <View style={styles.points}>
          {article.learning_points.map((pt, i) => (
            <View key={i} style={styles.point}>
              <Text style={styles.concept}>{pt.concept}</Text>
              <Text style={styles.pointDetail}>Why: {pt.why_it_matters}</Text>
              <Text style={styles.pointDetail}>Use: {pt.practical_use}</Text>
            </View>
          ))}
        </View>
      )}

      {/* Conversation tip */}
      {article.conversation_tip && (
        <View style={[styles.tip, { borderLeftColor: accentColor }]}>
          <Text style={styles.tipText}>{article.conversation_tip}</Text>
          <TouchableOpacity onPress={onCopyTip} style={styles.copyRow}>
            <Ionicons name="copy-outline" size={14} color={accentColor} />
            <Text style={[styles.copyText, { color: accentColor }]}>Copy tip</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Tags */}
      {article.tags?.length > 0 && (
        <View style={styles.tags}>
          {article.tags.slice(0, 4).map((tag) => (
            <View key={tag} style={styles.tag}><Text style={styles.tagText}>{tag}</Text></View>
          ))}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: "#1C2033" },
  content: { padding: 20, paddingTop: 60, paddingBottom: 40 },
  center: { flex: 1, backgroundColor: "#1C2033", alignItems: "center", justifyContent: "center" },
  header: { flexDirection: "row", alignItems: "center", gap: 16, marginBottom: 28 },
  heading: { color: "#EEEEF5", fontSize: 22, fontWeight: "700" },
  empty: { color: "#8B8FAF", textAlign: "center", fontSize: 16, lineHeight: 24, marginTop: 60 },
  section: { marginBottom: 32 },
  sectionHeader: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", borderLeftWidth: 3, paddingLeft: 10, marginBottom: 14 },
  sectionTitle: { fontSize: 14, fontWeight: "700", letterSpacing: 1, textTransform: "uppercase" },
  sectionCount: { color: "#8B8FAF", fontSize: 13 },
  card: { backgroundColor: "#262A40", borderRadius: 14, padding: 16, marginBottom: 12 },
  cardTitle: { color: "#EEEEF5", fontSize: 16, fontWeight: "700", lineHeight: 22, marginBottom: 8 },
  cardSummary: { color: "#B0B4CC", fontSize: 14, lineHeight: 21, marginBottom: 12 },
  expandRow: { flexDirection: "row", alignItems: "center", gap: 4, marginBottom: 8 },
  expandLabel: { fontSize: 13, fontWeight: "600" },
  points: { gap: 10, marginBottom: 12 },
  point: { backgroundColor: "#1C2033", borderRadius: 8, padding: 12 },
  concept: { color: "#EEEEF5", fontSize: 14, fontWeight: "600", marginBottom: 4 },
  pointDetail: { color: "#8B8FAF", fontSize: 13, lineHeight: 18 },
  tip: { backgroundColor: "#1C2033", borderLeftWidth: 3, borderRadius: 8, padding: 12, marginBottom: 10 },
  tipText: { color: "#D1D5DB", fontSize: 14, lineHeight: 20, fontStyle: "italic", marginBottom: 8 },
  copyRow: { flexDirection: "row", alignItems: "center", gap: 4 },
  copyText: { fontSize: 12, fontWeight: "600" },
  tags: { flexDirection: "row", flexWrap: "wrap", gap: 6 },
  tag: { backgroundColor: "#1C2033", borderRadius: 4, paddingHorizontal: 8, paddingVertical: 3 },
  tagText: { color: "#8B8FAF", fontSize: 12 },
});
