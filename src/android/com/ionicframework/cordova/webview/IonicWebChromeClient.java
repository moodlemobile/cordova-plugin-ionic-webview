package com.ionicframework.cordova.webview;

import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;
import android.webkit.PermissionRequest;

import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.engine.SystemWebChromeClient;
import org.apache.cordova.engine.SystemWebViewEngine;
import org.json.JSONException;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * WebChromeClient used by IonicWebViewEngine.
 *
 * Requests Android runtime permissions when a page inside the WebView asks for
 * capture permissions (audio/video) through getUserMedia.
 */
public class IonicWebChromeClient extends SystemWebChromeClient {

  private static final String LOG_TAG = "IonicWebChromeClient";
  // "Unique" number. It's important that two functions handling permissions at the same time don't use the same request code.
  private static final int PERMISSIONS_REQUEST_CODE_BASE = 1714;

  private final AtomicInteger nextPermissionsRequestCode = new AtomicInteger(PERMISSIONS_REQUEST_CODE_BASE);
  private final Map<Integer, PermissionRequest> pendingPermissionRequests = new ConcurrentHashMap<>();
  private final CordovaInterface cordova;

  public IonicWebChromeClient(SystemWebViewEngine parentEngine, CordovaInterface cordova) {
    super(parentEngine);

    this.cordova = cordova;
  }

  @Override
  public void onPermissionRequest(final PermissionRequest request) {
    Log.d(LOG_TAG, "onPermissionRequest: " + Arrays.toString(request.getResources()));

    // Keep previous behaviour on old Android versions where runtime permissions do not apply.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      request.grant(request.getResources());

      return;
    }

    if (cordova == null || cordova.getActivity() == null) {
      request.deny();

      return;
    }

    final List<String> missingPermissions = getMissingAndroidPermissions(request);

    if (missingPermissions.isEmpty()) {
      request.grant(request.getResources());

      return;
    }

    final int requestCode = nextPermissionsRequestCode.getAndIncrement();
    final String[] permissions = missingPermissions.toArray(new String[0]);

    pendingPermissionRequests.put(requestCode, request);

    try {
      cordova.requestPermissions(new CordovaPlugin() {
        @Override
        public void onRequestPermissionResult(int callbackRequestCode, String[] grantedPermissions, int[] grantResults)
            throws JSONException {
          onPermissionRequestResult(requestCode, grantResults);
        }

        @Override
        public void onRequestPermissionsResult(int callbackRequestCode, String[] grantedPermissions, int[] grantResults)
            throws JSONException {
          onPermissionRequestResult(requestCode, grantResults);
        }
      }, requestCode, permissions);
    } catch (Throwable e) {
      Log.e(LOG_TAG, "Error requesting runtime permissions for WebView media capture", e);
      pendingPermissionRequests.remove(requestCode);
      request.deny();
    }
  }

  @Override
  public void onPermissionRequestCanceled(PermissionRequest request) {
    // Remove any pending callback associated with the canceled WebView request.
    Iterator<Map.Entry<Integer, PermissionRequest>> iterator = pendingPermissionRequests.entrySet().iterator();
    while (iterator.hasNext()) {
      Map.Entry<Integer, PermissionRequest> entry = iterator.next();
      if (entry.getValue() == request) {
        iterator.remove();
      }
    }

    super.onPermissionRequestCanceled(request);
  }

  private List<String> getMissingAndroidPermissions(PermissionRequest request) {
    List<String> requiredPermissions = new ArrayList<>();

    for (String resource : request.getResources()) {
      switch (resource) {
        case PermissionRequest.RESOURCE_AUDIO_CAPTURE:
          addPermissionIfMissing(requiredPermissions, Manifest.permission.RECORD_AUDIO);
          break;
        case PermissionRequest.RESOURCE_VIDEO_CAPTURE:
          addPermissionIfMissing(requiredPermissions, Manifest.permission.CAMERA);
          break;
        default:
          // Ignore other permissions.
          break;
      }
    }

    List<String> missingPermissions = new ArrayList<>();

    for (String permission : requiredPermissions) {
      if (!cordova.hasPermission(permission)) {
        missingPermissions.add(permission);
      }
    }

    return missingPermissions;
  }

  private void addPermissionIfMissing(List<String> permissions, String permission) {
    if (!permissions.contains(permission)) {
      permissions.add(permission);
    }
  }

  private void onPermissionRequestResult(int requestCode, int[] grantResults) {
    final PermissionRequest permissionRequest = pendingPermissionRequests.remove(requestCode);

    if (permissionRequest == null) {
      return;
    }

    boolean allGranted = grantResults.length > 0;
    for (int grantResult : grantResults) {
      if (grantResult != PackageManager.PERMISSION_GRANTED) {
        allGranted = false;
        break;
      }
    }

    if (cordova == null || cordova.getActivity() == null) {
      permissionRequest.deny();

      return;
    }

    // Assign it to a final variable because anonymous Runnable classes can only access final variables.
    final boolean isGranted = allGranted;
    cordova.getActivity().runOnUiThread(new Runnable() {
      @Override
      public void run() {
        if (isGranted) {
          permissionRequest.grant(permissionRequest.getResources());
        } else {
          permissionRequest.deny();
        }
      }
    });
  }
}
