/// Name: SongListItem
/// Parent: SongListPage, FavoriteListPage
/// Description: Rendering out the song item itself.
library;

import 'package:ddr_md/components/song/song_difficulties.dart';
import 'package:ddr_md/components/song/song_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SongListItem extends StatefulWidget {
  const SongListItem(
      {super.key,
      required this.songInfo,
      required this.isFav,
      required this.isSearch,
      this.regenFavsCallback});
  final SongInfo songInfo;
  final bool isFav;
  final bool isSearch;
  final void Function()? regenFavsCallback; // callback function for navigator

  @override
  State<SongListItem> createState() => _SongListItemState();
}

class _SongListItemState extends State<SongListItem> {
  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    return ListTile(
      visualDensity: VisualDensity.adaptivePlatformDensity,
      leading: Stack(
        children: [
          Image(
            image: AssetImage(
                'assets/jackets-lowres/${widget.songInfo.name}.png'),
          ),
          if (!widget.isSearch)
            Positioned(
              top: 0,
              left: 0,
              height: 5,
              width: 5,
              child: Icon(
                widget.isFav ? Icons.star : Icons.star_border,
                color: Colors.yellow,
                size: 15,
              ),
            ),
        ],
      ),
      title: Text(
        widget.songInfo.title,
        style: TextStyle(
            fontSize: 15,
            overflow:
                widget.isSearch ? TextOverflow.visible : TextOverflow.ellipsis),
      ),
      subtitle: SongDifficulty(
          difficulty: songState.modes == Modes.singles
              ? widget.songInfo.singles
              : widget.songInfo.doubles),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(widget.songInfo.version),
          Text(widget.songInfo.charts[0].dominantBpm.toString()),
        ],
      ),
      onTap: () async {
        songState.setSongInfo(widget.songInfo);
        songState.setChosenDifficulty(0);
        await Navigator.push(context,
                MaterialPageRoute(builder: (context) => const SongPage()))
            .then((_) {
          if (widget.regenFavsCallback != null) {
            widget.regenFavsCallback!();
          }
        });
      },
    );
  }
}
