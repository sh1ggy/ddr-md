import 'package:ddr_md/components/song/song_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SongListItem extends StatelessWidget {
  const SongListItem(
      {super.key, required this.songInfo, required this.isSearch});
  final SongInfo songInfo;
  final bool isSearch;

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    return ListTile(
      visualDensity: VisualDensity.adaptivePlatformDensity,
      leading: Image(
        image: AssetImage('assets/jackets-lowres/${songInfo.name}-jacket.png'),
      ),
      title: Text(
        songInfo.title,
        style: TextStyle(
            fontSize: 15,
            overflow: isSearch ? TextOverflow.visible : TextOverflow.ellipsis),
      ),
      subtitle: Row(
        children: [
          Text(
            songInfo.levels.single.beginner != null
                ? songInfo.levels.single.beginner.toString()
                : "",
            style: const TextStyle(
                color: Colors.cyan, fontWeight: FontWeight.bold),
          ),
          Text(
            songInfo.levels.single.easy != null
                ? songInfo.levels.single.easy.toString()
                : "",
            style: const TextStyle(
                color: Colors.orange, fontWeight: FontWeight.bold),
          ),
          Text(
            songInfo.levels.single.medium != null
                ? songInfo.levels.single.medium.toString()
                : "",
            style:
                const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          if (songInfo.levels.single.hard != null)
            Text(
              songInfo.levels.single.hard.toString(),
              style: const TextStyle(
                  color: Colors.green, fontWeight: FontWeight.bold),
            ),
          if (songInfo.levels.single.expert != null)
            Text(songInfo.levels.single.expert.toString(),
                style: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold)),
          Text(
              songInfo.levels.single.challenge != null
                  ? songInfo.levels.single.challenge.toString()
                  : "",
              style: const TextStyle(
                  color: Colors.purple, fontWeight: FontWeight.bold)),
        ].expand((x) => [const SizedBox(width: 10), x]).skip(1).toList(),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(songInfo.version),
          Text(songInfo.chart[0].dominantBpm.toString()),
        ],
      ),
      onTap: () => {
        songState.setSongInfo(songInfo),
        Navigator.push(
            context, MaterialPageRoute(builder: (context) => const SongPage()))
      },
    );
  }
}
