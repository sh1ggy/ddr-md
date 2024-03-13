import 'package:flutter/material.dart';

Container note() {
  return Container(
    padding: const EdgeInsets.all(7.0),
    decoration: BoxDecoration(
        color: Colors.white,
        // border: Border.all(
        //   color: Colors.amber,
        // ),
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, .1),
            blurRadius: 3,
            color: Colors.grey,
          ),
        ],
        borderRadius: BorderRadius.circular(5)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            children: [
              Text(
                "Previous Note",
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                child: Text(
                    "The crossovers in this song are surprisingly hard, I keep leading with the wrong first foot in after the jumps. Song should be played with those in mind.",
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
