/// Name: Music library test
/// Parent: MusicLibrary
/// Description: Which files count as which song.
library;

import 'package:ddr_md/models/music_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('files match songs by name, in any folder, and only one way', () {
    final scan = matchMusic(
      [
        '/m/Silent Hill-song.ogg',
        '/m/pack/Silent Hill/Silent Hill.mp3', // repeats Silent Hill
        '/m/.59-song.OGG', // starts with a dot, upper-case extension
        '/m/pack/Bad Maniacs/Bad Maniacs.flac', // raw pack layout
        '/m/pack/Bad Maniacs/Bad Maniacs.sm', // not audio
        '/m/._Bad Maniacs.flac', // AppleDouble
        '/m/homeneko sensation.ogg', // close to one song
        '/m/LOVE.ogg', // close to two songs
        '/m/Holiday-song.wav', // a song named with its own suffix
        '/m/nothing.ogg',
      ],
      [
        'Silent Hill',
        '.59',
        'Bad Maniacs',
        'Home neko sensation',
        'Love',
        'L.O.V.E',
        'Holiday-song',
        'Missing Song',
      ],
    );

    expect(scan.matched, {
      'Silent Hill': '/m/Silent Hill-song.ogg',
      '.59': '/m/.59-song.OGG',
      'Bad Maniacs': '/m/pack/Bad Maniacs/Bad Maniacs.flac',
      'Holiday-song': '/m/Holiday-song.wav',
    });
    expect(scan.close, {'Home neko sensation': '/m/homeneko sensation.ogg'});
    expect(
        scan.unused,
        unorderedEquals([
          '/m/pack/Silent Hill/Silent Hill.mp3',
          '/m/LOVE.ogg',
          '/m/nothing.ogg',
        ]));
    expect(
        scan.missing,
        unorderedEquals(
            ['Home neko sensation', 'L.O.V.E', 'Love', 'Missing Song']));
  });
}
