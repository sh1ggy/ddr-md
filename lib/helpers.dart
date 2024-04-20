/// Name: helpers.dart
/// Description: A file to store helper functions
library;
import 'package:ddr_md/constants.dart' as constants;

int findNearestReadSpeed(int songBpm, List array, int readSpeed) {
  var nearest = 0;
  array.asMap().entries.forEach((entry) {
    var i = entry.key;
    if (array[i] * songBpm <= readSpeed + constants.buffer) {
      nearest = i;
    }
  });
  return nearest;
}
