import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as Constants;

class NotePage extends StatelessWidget {
  const NotePage({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Scaffold(
          appBar: AppBar(
            surfaceTintColor: Colors.black,
            shadowColor: Colors.black,
            elevation: 2,
            title: const Text(
              'Notes',
              style: TextStyle(fontSize: 15),
            ),
            iconTheme: const IconThemeData(color: Colors.blueGrey),
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: Colors.red,
            child: const Icon(Icons.edit, color: Colors.white),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (BuildContext context) {
                  return const NewNoteField();
                },
              );
            },
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(
                          height: 10,
                        ),
                        for (var i = 0; i < 10; i++)
                          GestureDetector(
                            onTap: () {
                              showModalBottomSheet<void>(
                                context: context,
                                builder: (BuildContext context) {
                                  return const NewNoteField();
                                },
                              );
                            },
                            child: SizedBox(
                                width: MediaQuery.of(context).size.width,
                                child: const Card(
                                  shadowColor: Colors.black,
                                  elevation: 3,
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
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class NewNoteField extends StatelessWidget {
  const NewNoteField({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      width: MediaQuery.of(context).size.width,
      child: SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
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
                  hintStyle: TextStyle(color: Theme.of(context).textTheme.headlineMedium?.color)
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.save),
                  tooltip: "Save note",
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }
}
