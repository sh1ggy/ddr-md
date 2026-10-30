/// Name: EditionArtworkPicker
/// Parent: EditionLabPage, EditionFixtureBrowser
/// Description: Search all loaded songs without decoding an artwork gallery.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';

Widget editionArtwork(SongInfo? song) => song == null
    ? const DecoratedBox(
        decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
        Color(0xFF354260),
        Color(0xFFD7CDBA),
        Color(0xFF22293D)
      ], begin: Alignment.topLeft, end: Alignment.bottomRight)))
    : SongArtwork(
        songName: song.name,
        title: song.title,
        fullResolution: true,
        fade: Duration.zero);

class EditionArtworkPicker extends StatelessWidget {
  const EditionArtworkPicker(
      {super.key, required this.song, required this.onChanged});
  final SongInfo? song;
  final ValueChanged<SongInfo?>? onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(song?.title ?? 'Neutral test jacket'),
      subtitle: Text('Choose jacket • ${Songs.list.length} songs'),
      trailing: const Icon(Icons.search),
      onTap: onChanged == null
          ? null
          : () async {
              // A null return also means cancellation. The neutral row returns a
              // separate result so back navigation keeps the current selection.
              final result = await showSearch<({SongInfo? song})?>(
                  context: context, delegate: _JacketSearch());
              if (result != null) onChanged?.call(result.song);
            });
}

class _JacketSearch extends SearchDelegate<({SongInfo? song})?> {
  _JacketSearch() : super(searchFieldLabel: 'Search song title or artist');
  @override
  List<Widget> buildActions(BuildContext context) => [
        IconButton(
            tooltip: 'Clear search',
            icon: const Icon(Icons.clear),
            onPressed: () => query = '')
      ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null));
  @override
  Widget buildResults(BuildContext context) => _results(context);
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);
  Widget _results(BuildContext context) {
    final search = query.trim().toLowerCase();
    final songs = search.isEmpty
        ? Songs.list
        : Songs.list
            .where((song) =>
                '${song.title} ${song.titletranslit} ${song.artist} ${song.name}'
                    .toLowerCase()
                    .contains(search))
            .toList();
    return ListView.builder(
        itemCount: songs.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return ListTile(
                title: const Text('Neutral test jacket'),
                onTap: () => close(context, (song: null)));
          }
          final song = songs[index - 1];
          return ListTile(
              title: Text(song.title),
              subtitle: Text(song.artist),
              onTap: () => close(context, (song: song)));
        });
  }
}
