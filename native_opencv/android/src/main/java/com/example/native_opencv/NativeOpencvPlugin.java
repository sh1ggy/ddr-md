package com.example.native_opencv;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.graphics.SurfaceTexture;
import android.view.Surface;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.view.TextureRegistry;

/**
 * Thin Android shim for the native camera + OCR pipeline.
 *
 * Its ONLY jobs are the things that genuinely require the Android embedding:
 *   • mint the Flutter preview texture (TextureRegistry is Java-only) and hand
 *     its Surface to the C++ session,
 *   • request the runtime CAMERA permission,
 *   • return the texture id + an opaque native session pointer to Dart.
 *
 * Everything else — start/stop/setDebug and every per-frame OCR result — goes
 * Dart ↔ C++ over FFI (see ocr_processor.dart + jni_bridge.cpp). No EventChannel
 * and no JNI in the result path.
 */
public class NativeOpencvPlugin
    implements FlutterPlugin, MethodCallHandler, ActivityAware,
               PluginRegistry.RequestPermissionsResultListener {

  static {
    System.loadLibrary("native_opencv");
  }

  private static final int CAMERA_PERMISSION_REQUEST = 0xCA3;

  private MethodChannel methodChannel;
  private TextureRegistry textures;
  private TextureRegistry.SurfaceTextureEntry textureEntry;
  private Surface previewSurface;

  private Activity activity;
  private ActivityPluginBinding activityBinding;

  private long nativePtr = 0;

  // A pending initialize() awaiting the camera-permission decision.
  private Result pendingInitResult;
  private MethodCall pendingInitCall;

  // ---- JNI: texture/Surface handoff + session lifecycle only ----------------
  // Returns {sessionPtr, previewWidth, previewHeight}.
  private native long[] nativeCreateSession(Surface surface, String dataPath,
                                            int[] cfgInts, double[] cfgDoubles);
  private native void nativeDestroySession(long handle);

  // ---- FlutterPlugin -------------------------------------------------------
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    textures = binding.getTextureRegistry();
    methodChannel = new MethodChannel(binding.getBinaryMessenger(), "native_opencv/camera_ocr");
    methodChannel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    methodChannel.setMethodCallHandler(null);
    disposeSession();
  }

  // ---- MethodCallHandler ---------------------------------------------------
  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "initialize":
        initialize(call, result);
        break;
      case "dispose":
        disposeSession();
        result.success(null);
        break;
      default:
        result.notImplemented();
    }
  }

  private void initialize(MethodCall call, Result result) {
    if (nativePtr != 0) {
      result.success(previewInfo());
      return;
    }
    // Camera permission must be granted before the FFI camera_start opens the
    // device, so request it here (the only Activity-bound step) before creating
    // the session.
    if (activity != null &&
        activity.checkSelfPermission(Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED) {
      pendingInitResult = result;
      pendingInitCall = call;
      activity.requestPermissions(new String[]{Manifest.permission.CAMERA},
                                  CAMERA_PERMISSION_REQUEST);
      return;
    }
    createSession(call, result);
  }

  private void createSession(MethodCall call, Result result) {
    String dataPath = call.argument("dataPath");
    int[] cfgInts = call.argument("cfgInts");
    double[] cfgDoubles = call.argument("cfgDoubles");

    textureEntry = textures.createSurfaceTexture();
    SurfaceTexture st = textureEntry.surfaceTexture();
    previewSurface = new Surface(st);

    long[] res = nativeCreateSession(previewSurface, dataPath == null ? "" : dataPath,
                                     cfgInts, cfgDoubles);
    nativePtr = res[0];
    lastPreviewWidth = (int) res[1];
    lastPreviewHeight = (int) res[2];
    result.success(previewInfo());
  }

  private int lastPreviewWidth = 0;
  private int lastPreviewHeight = 0;

  private Map<String, Object> previewInfo() {
    Map<String, Object> info = new HashMap<>();
    info.put("textureId", textureEntry.id());
    info.put("previewWidth", lastPreviewWidth);
    info.put("previewHeight", lastPreviewHeight);
    // Opaque pointer Dart uses for the FFI camera_* calls.
    info.put("sessionPtr", nativePtr);
    return info;
  }

  private void disposeSession() {
    if (nativePtr != 0) {
      nativeDestroySession(nativePtr);
      nativePtr = 0;
    }
    if (previewSurface != null) {
      previewSurface.release();
      previewSurface = null;
    }
    if (textureEntry != null) {
      textureEntry.release();
      textureEntry = null;
    }
  }

  // ---- ActivityAware -------------------------------------------------------
  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    activity = binding.getActivity();
    activityBinding = binding;
    binding.addRequestPermissionsResultListener(this);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    if (activityBinding != null) {
      activityBinding.removeRequestPermissionsResultListener(this);
    }
    activity = null;
    activityBinding = null;
  }

  // ---- RequestPermissionsResultListener ------------------------------------
  @Override
  public boolean onRequestPermissionsResult(int requestCode, String[] permissions,
                                            int[] grantResults) {
    if (requestCode != CAMERA_PERMISSION_REQUEST) return false;
    Result result = pendingInitResult;
    MethodCall call = pendingInitCall;
    pendingInitResult = null;
    pendingInitCall = null;
    if (result == null) return true;

    // Create the session regardless of the decision; if denied, the FFI
    // camera_start will simply fail to open the device and Dart surfaces it.
    createSession(call, result);
    return true;
  }
}
