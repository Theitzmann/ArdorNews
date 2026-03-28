// app/_layout.tsx — Root layout for all screens
// Sets dark navy background everywhere and hides the default header.
// Expo Router uses this as the entry wrapper for the file-based navigation tree.

import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";

export default function RootLayout() {
  return (
    <>
      <StatusBar style="light" />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: "#1C2033" },
          animation: "slide_from_right",
        }}
      />
    </>
  );
}
