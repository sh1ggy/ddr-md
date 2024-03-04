import 'package:bpm_clicker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class BPMPage extends StatelessWidget {
  const BPMPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'BPM Wheel',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  TextField(
                    maxLength: 3,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: (value) => appState.setBpm(value),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      hintText: '200',
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
                          diameterRatio: 1.25,
                          itemExtent: 22,
                          children: appState.mods.map<Widget>((e) {
                            var mod = e * appState.bpm;
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
