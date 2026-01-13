import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// C function signatures
typedef _CVersionFunc = Pointer<Utf8> Function();
typedef _CProcessImageFunc = Void Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _CCameraSnapshotFunc = Void Function(
  Pointer<Utf8>,
);

// Dart function signatures
typedef _VersionFunc = Pointer<Utf8> Function();
typedef _ProcessImageFunc = void Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _CameraSnapshotFunc = void Function(Pointer<Utf8>);

// Getting a library that holds needed symbols
DynamicLibrary _openDynamicLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libnative_opencv.so');
  }

  return DynamicLibrary.process();
}

DynamicLibrary _lib = _openDynamicLibrary();

// Looking for the functions
final _VersionFunc _version =
    _lib.lookup<NativeFunction<_CVersionFunc>>('version').asFunction();
final _ProcessImageFunc _processImage = _lib
    .lookup<NativeFunction<_CProcessImageFunc>>('process_image')
    .asFunction();
final _CameraSnapshotFunc _cameraSnapshot = _lib
    .lookup<NativeFunction<_CCameraSnapshotFunc>>('camera_snapshot')
    .asFunction();

String opencvVersion() {
  return _version().toDartString();
}

void processImage(ProcessImageArguments args) {
  _processImage(args.inputPath.toNativeUtf8(), args.outputPath.toNativeUtf8());
}

void cameraSnapshot(String outputPath) {
  _cameraSnapshot(outputPath.toNativeUtf8());
}

class ProcessImageArguments {
  final String inputPath;
  final String outputPath;

  ProcessImageArguments(this.inputPath, this.outputPath);
}
