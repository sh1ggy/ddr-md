/// Name: helpers.dart
/// Description: A file to store helper functions
library;

import 'package:ddr_md/constants.dart' as constants;
import 'package:flutter/material.dart';

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

// Helper function to show snackbar toast
void showToast(BuildContext context, String message) {
  final scaffold = ScaffoldMessenger.of(context);
  scaffold.showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(
          label: 'DISMISS', onPressed: scaffold.hideCurrentSnackBar),
    ),
  );
}

// Helper function to format date
String formatDate(DateTime date) {
  return "${date.year}-${date.month}-${date.day} ${date.hour}:${date.minute.toString().length == 1 ? "0${date.minute}" : "date.minute"}";
}
