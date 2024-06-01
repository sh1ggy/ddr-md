import 'package:ddr_md/components/song/song_difficulties.dart';
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
      subtitle: SongDifficulty(
          difficulty: songState.modes == Modes.singles
              ? songInfo.modes.singles
              : songInfo.modes.doubles),
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
        songState.setChosenDifficulty(0),
        Navigator.push(
            context, MaterialPageRoute(builder: (context) => const SongPage()))
      },
    );
  }
}
