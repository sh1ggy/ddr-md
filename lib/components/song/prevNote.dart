import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:ddr_md/constants.dart' as Constants;

Card note(context) {
  return Card(
    child: Container(
      padding: const EdgeInsets.all(15.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, 'NotePage');
                  },
                  child: const Text("Previous Note",
                      style: TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                ),
                const SizedBox(
                  child: Text(
                      Constants.note,
                      softWrap: true,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          noteScore(),
        ].expand((x) => [const SizedBox(width: 20), x]).skip(1).toList(),
      ),
    ),
  );
}

Column noteScore() {
  return const Column(
    children: [
      Text(
        "Recent Score:",
        style: TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image(
              image: AssetImage('assets/rank_s_aaa.png'),
            ),
            Image(
              image: AssetImage('assets/full_mar.png'),
            ),
          ],
        ),
      ),
      Text(
        '1,000,000',
        style: TextStyle(fontFamily: 'Handel'),
      ),
    ],
  );
}
