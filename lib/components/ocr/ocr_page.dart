import 'package:ddr_md/native_ocr_ffi.dart';
import 'package:flutter/material.dart';

class OcrPage extends StatefulWidget {
  const OcrPage({super.key});

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  void showVersion() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final snackbar = SnackBar(
      content: Text('OpenCV version: ${opencvVersion()}'),
    );

    scaffoldMessenger
      ..removeCurrentSnackBar(reason: SnackBarClosedReason.dismiss)
      ..showSnackBar(snackbar);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("OCR Page")),
      body: Stack(
        children: <Widget>[
          Center(
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: showVersion,
                      child: const Text('Show version'),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
