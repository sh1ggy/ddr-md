import Card from "@/components/Card";
import { Text, View } from "@/components/Themed";
import ThemeSwitch from "@/components/ThemeSwitch";
import { BLUR_HASH } from "@/constants/Constants";
import { Pokemon } from "@/lib/types";
import { theme } from "@/stores/global";
import { useQuery } from "@tanstack/react-query";
import { Image } from "expo-image";
import { useAtom } from "jotai";
import { StyleSheet, useColorScheme } from "react-native";

export default function TabOneScreen() {
  const [appTheme] = useAtom(theme);
  const colorScheme = useColorScheme();

  // Queries
  const { isPending, error, data, isFetching } = useQuery<Pokemon>({
    queryKey: ["pokedex"],
    queryFn: async () => {
      const r = await fetch("https://pokeapi.co/api/v2/pokemon/ditto");
      if (!r.ok) throw new Error("Failed to fetch Pokémon");
      return await r.json();
    },
  });

  if (isPending) return <Text>Loading...</Text>;

  if (error) return <Text>{"An error has occurred: " + error.message}</Text>;

  return (
    <View
      style={{
        flex: 1,
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <Text style={styles.title}>Tab One</Text>
      <View
        style={styles.separator}
        lightColor="#eee"
        darkColor="rgba(255,255,255,0.1)"
      />
      <Card title={appTheme} />
      {colorScheme && <Card title={colorScheme} />}
      {data && <Card title={data.name} />}
      <Image
        style={{
          width: "20%",
          height: "20%",
          backgroundColor: "#0553",
        }}
        source={data.sprites.front_default}
        placeholder={BLUR_HASH}
        contentFit="scale-down"
        transition={1000}
      />
      <ThemeSwitch />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {},
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
