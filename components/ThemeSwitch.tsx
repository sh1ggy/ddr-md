import { theme } from "@/stores/global";
import { useAtom } from "jotai";
import { Switch, SwitchChangeEvent } from "react-native";
import { Text, View } from "./Themed";

interface Props {}
export default function ({}: Props) {
  const [appTheme, setAppTheme] = useAtom(theme);

  function handleSwitchChange(e: SwitchChangeEvent) {
    setAppTheme(e.nativeEvent.value ? "dark" : "light");
  }

  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
      <Text>Dark Mode</Text>
      <Switch
        onChange={(e) => handleSwitchChange(e)}
        value={appTheme === "light" ? false : true}
      />
    </View>
  );
}
