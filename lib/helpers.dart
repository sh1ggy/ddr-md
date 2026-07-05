/// Name: helpers.dart
/// Description: A file to store helper functions
library;

import 'dart:math';

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

// Levenshtein edit distance between two strings (two-row iterative form).
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = min(min(curr[j] + 1, prev[j + 1] + 1), prev[j] + cost);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
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
  return "${date.year}-${date.month}-${date.day} (${date.hour}:${date.minute.toString().length == 1 ? "0${date.minute}" : date.minute})";
}
