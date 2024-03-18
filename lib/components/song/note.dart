import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:ddr_md/constants.dart' as Constants;

class NotePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Scaffold(
          appBar: AppBar(
            elevation: 5,
            title: const Text(
              'Notes',
              style: TextStyle(fontSize: 15),
            ),
          ),
          body: Container(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (var i = 0; i < 10; i++)
                            SizedBox(
                                width: MediaQuery.of(context).size.width,
                                child: const Card(
                                  color: Colors.orangeAccent,
                                  child: Padding(
                                    padding: EdgeInsets.all(20.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '24/05/2021',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Text(Constants.note),
                                      ],
                                    ),
                                  ),
                                )),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 10,
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(15),
                    child: const TextField(
                      maxLines: 3,
                      keyboardType: TextInputType.text,
                      textAlign: TextAlign.center,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        hintText: 'Enter new note here...',
                      ),
                    ),
                  ),
                ],
              )),
        ),
      );
}
