import 'package:ddr_md/components/song/song_difficulties.dart';
import 'package:ddr_md/components/song/song_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

class SongListItem extends StatefulWidget {
  const SongListItem(
      {super.key,
      required this.songInfo,
      required this.isFav,
      required this.isSearch, 
      required this.generateSongItems
      });
  final SongInfo songInfo;
  final bool isFav;
  final bool isSearch;
  final void Function() generateSongItems;

  @override
  State<SongListItem> createState() => _SongListItemState();
}

class _SongListItemState extends State<SongListItem>
    with SingleTickerProviderStateMixin {
  late final controller = SlidableController(this);

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    // TODO: ideally this would be like Spotify queue
    // https://github.com/letsar/flutter_slidable/issues/273
    // return Slidable(
    //   key: UniqueKey(),
    //   closeOnScroll: true,
    //   endActionPane: ActionPane(
    //     motion: const ScrollMotion(),
    //     dragDismissible: true,
    //     children: [
    //       SlidableAction(
    //         flex: 2,
    //         onPressed: (_) async {
    //           controller.close();
    //           SongInfo? songStateInfo = songState.songInfo;
    //           if (songStateInfo != null) {
    //             await DatabaseProvider.addFavorite(Favorite(
    //                 id: 0,
    //                 isFav: true,
    //                 songTitle: songStateInfo.titletranslit));
    //           }
    //         },
    //         autoClose: true,
    //         backgroundColor: Colors.yellow,
    //         foregroundColor: Colors.black,
    //         icon: Icons.star,
    //         label: 'Favourite',
    //       ),
    //     ],
    //   ),
    return ListTile(
      visualDensity: VisualDensity.adaptivePlatformDensity,
      leading: Stack(
        children: [
          Image(
            image: AssetImage(
                'assets/jackets-lowres/${widget.songInfo.name}-jacket.png'),
          ),
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
              ? widget.songInfo.modes.singles
              : widget.songInfo.modes.doubles),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(widget.songInfo.version),
          Text(widget.songInfo.chart[0].dominantBpm.toString()),
        ],
      ),
      onTap: () async {
        songState.setSongInfo(widget.songInfo);
        songState.setChosenDifficulty(0);
        await Navigator.push(
            context, MaterialPageRoute(builder: (context) => const SongPage()));
        widget.generateSongItems();
      },
    );
  }
}
