package com.example.native_opencv;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.graphics.SurfaceTexture;
import android.os.Handler;
import android.os.Looper;
import android.view.Surface;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.view.TextureRegistry;

/**
 * Native camera + OCR plugin. Replaces the Flutter `camera` package: it owns the
 * preview SurfaceTexture and the start/stop/dispose method channel, forwards
 * everything to the pure-NDK CameraOcrSession over JNI, and republishes per-frame
 * OCR results on an EventChannel that ocr_processor.dart consumes.
 */
public class NativeOpencvPlugin
    implements FlutterPlugin, MethodCallHandler, ActivityAware,
               EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener {

  static {
    System.loadLibrary("native_opencv");
  }

  private static final int CAMERA_PERMISSION_REQUEST = 0xCA3;

  private MethodChannel methodChannel;
  private EventChannel eventChannel;
  private TextureRegistry textures;
  private TextureRegistry.SurfaceTextureEntry textureEntry;
  private Surface previewSurface;

  private EventChannel.EventSink eventSink;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());

  private Activity activity;
  private ActivityPluginBinding activityBinding;

  private long nativePtr = 0;

  // Stashed start() request awaiting a camera-permission decision.
  private Result pendingStartResult;
  private boolean pendingStartDebug;

  // ---- JNI -----------------------------------------------------------------
  private native long[] nativeInit(Surface surface, String dataPath,
                                   int[] cfgInts, double[] cfgDoubles);
  private native boolean nativeStart(long handle, boolean debug);
  private native void nativeStop(long handle);
  private native void nativeSetDebug(long handle, boolean debug);
  private native void nativeDispose(long handle);

  // ---- FlutterPlugin -------------------------------------------------------
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    textures = binding.getTextureRegistry();
    methodChannel = new MethodChannel(binding.getBinaryMessenger(), "native_opencv/camera_ocr");
    methodChannel.setMethodCallHandler(this);
    eventChannel = new EventChannel(binding.getBinaryMessenger(), "native_opencv/camera_ocr/events");
    eventChannel.setStreamHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    methodChannel.setMethodCallHandler(null);
    eventChannel.setStreamHandler(null);
    disposeSession();
  }

  // ---- MethodCallHandler ---------------------------------------------------
  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "initialize":
        initialize(call, result);
        break;
      case "start":
        Boolean debug = call.argument("debug");
        start(debug != null && debug, result);
        break;
      case "stop":
        if (nativePtr != 0) nativeStop(nativePtr);
        result.success(null);
        break;
      case "setDebug":
        Boolean enabled = call.argument("enabled");
        if (nativePtr != 0) nativeSetDebug(nativePtr, enabled != null && enabled);
        result.success(null);
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
      // Already initialised — return the existing texture + preview dims.
      result.success(previewInfo());
      return;
    }
    String dataPath = call.argument("dataPath");
    int[] cfgInts = call.argument("cfgInts");
    double[] cfgDoubles = call.argument("cfgDoubles");

    textureEntry = textures.createSurfaceTexture();
    SurfaceTexture st = textureEntry.surfaceTexture();
    previewSurface = new Surface(st);

    long[] res = nativeInit(previewSurface, dataPath == null ? "" : dataPath,
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
    return info;
  }

  private void start(boolean debug, Result result) {
    if (nativePtr == 0) {
      result.error("not_initialized", "initialize must be called first", null);
      return;
    }
    if (activity != null &&
        activity.checkSelfPermission(Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED) {
      pendingStartResult = result;
      pendingStartDebug = debug;
      activity.requestPermissions(new String[]{Manifest.permission.CAMERA},
                                  CAMERA_PERMISSION_REQUEST);
      return;
    }
    boolean ok = nativeStart(nativePtr, debug);
    if (ok) {
      result.success(null);
    } else {
      result.error("camera_start_failed", "Could not start camera session", null);
    }
  }

  private void disposeSession() {
    if (nativePtr != 0) {
      nativeDispose(nativePtr);
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

  // ---- Result callback from native (worker thread) -------------------------
  // Called over JNI from the OCR worker; marshals into the event map on the
  // main thread for the EventChannel.
  @SuppressWarnings("unused")
  private void onNativeResult(boolean isDetected, int detailsRoiIndex, int width,
                              int height, int[] rois, String[] ocr, byte[] mask,
                              byte[] crop, byte[] capture) {
    final Map<String, Object> map = new HashMap<>();
    map.put("isDetected", isDetected);
    map.put("detailsRoiIndex", detailsRoiIndex);
    map.put("width", width);
    map.put("height", height);
    map.put("rois", rois);

    final Map<String, String> ocrMap = new HashMap<>();
    final String[] keys = {"score", "marvelous", "perfect", "great", "good", "miss"};
    for (int i = 0; i < keys.length && i < ocr.length; i++) {
      ocrMap.put(keys[i], ocr[i] == null ? "" : ocr[i]);
    }
    map.put("ocr", ocrMap);

    if (mask != null) map.put("mask", mask);
    if (crop != null) map.put("crop", crop);
    if (capture != null) map.put("capture", capture);

    mainHandler.post(() -> {
      if (eventSink != null) eventSink.success(map);
    });
  }

  // ---- EventChannel.StreamHandler ------------------------------------------
  @Override
  public void onListen(Object arguments, EventChannel.EventSink events) {
    eventSink = events;
  }

  @Override
  public void onCancel(Object arguments) {
    eventSink = null;
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
    Result result = pendingStartResult;
    pendingStartResult = null;
    if (result == null) return true;

    boolean granted = grantResults.length > 0 &&
                      grantResults[0] == PackageManager.PERMISSION_GRANTED;
    if (!granted) {
      result.error("permission_denied", "Camera permission denied", null);
      return true;
    }
    boolean ok = nativePtr != 0 && nativeStart(nativePtr, pendingStartDebug);
    if (ok) {
      result.success(null);
    } else {
      result.error("camera_start_failed", "Could not start camera session", null);
    }
    return true;
  }
}
