import { Text } from "@/components/Themed";

interface Props {
  title: string;
}

export default function Card({ title }: Props) {
  return <Text lightColor="#000">{title}</Text>;
}
