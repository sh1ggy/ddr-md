import { StyleSheet, useColorScheme } from "react-native";

import Card from "@/components/Card";
import { Text, View } from "@/components/Themed";
import ThemeSwitch from "@/components/ThemeSwitch";
import { theme } from "@/stores/global";
import { useAtom } from "jotai";

export default function TabOneScreen() {
  const [appTheme] = useAtom(theme);
  const colorScheme = useColorScheme();
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Tab One</Text>
      <View
        style={styles.separator}
        lightColor="#eee"
        darkColor="rgba(255,255,255,0.1)"
      />
      <Card title={appTheme} />
      {colorScheme && <Card title={colorScheme} />}
      <ThemeSwitch />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
  },
  title: {
    fontSize: 20,
    fontWeight: "bold",
  },
  separator: {
    marginVertical: 30,
    height: 1,
    width: "80%",
  },
});
