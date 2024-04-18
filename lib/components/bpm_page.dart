/// Name: BpmPage
/// Parent: Main
/// Description: Page that displays BPM wheel selector
library;

import 'package:ddr_md/models/bpm_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ddr_md/constants.dart' as constants;

class BpmPage extends StatelessWidget {
  const BpmPage({super.key});

  @override
  Widget build(BuildContext context) {
    var bpmState = context.watch<BpmState>();
    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              surfaceTintColor: Colors.black,
              shadowColor: Colors.black,
              elevation: 2,
              title: const Text(
                'BPM',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.blueGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              iconTheme: const IconThemeData(color: Colors.blueGrey),
            ),
            body: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    maxLength: 3,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: (value) => bpmState.setBpm(value),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      hintText: bpmState.bpm.toString(),
                    ),
                  ),
                  Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                              width: 50,
                              child: Text(
                                'Mod',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              )),
                          SizedBox(width: 30),
                          SizedBox(
                              width: 50,
                              child: Text(
                                'Speed',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              )),
                        ],
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).size.height / 2,
                        child: ListWheelScrollView(
                          useMagnifier: true,
                          magnification: 1.1,
                          diameterRatio: 1.5,
                          itemExtent: 22,
                          children: constants.mods.map<Widget>((e) {
                            var mod = e * bpmState.bpm;
                            return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(width: 50, child: Text('$e')),
                                  SizedBox(width: 50, child: Text('$mod')),
                                ]
                                    .expand(
                                        (x) => [const SizedBox(width: 30), x])
                                    .skip(1)
                                    .toList());
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
