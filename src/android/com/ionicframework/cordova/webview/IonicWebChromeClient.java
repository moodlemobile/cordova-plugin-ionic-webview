package com.ionicframework.cordova.webview;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;
import android.util.TypedValue;
import android.webkit.PermissionRequest;
import android.webkit.WebView;

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
  private final SystemWebViewEngine parentEngine;
  private final CordovaInterface cordova;

  /**
   * Creates a WebChromeClient instance bound to the current WebView engine.
   *
   * @param parentEngine parent SystemWebViewEngine associated with the WebView
   * @param cordova Cordova interface used to access permissions and activity context
   */
  public IonicWebChromeClient(SystemWebViewEngine parentEngine, CordovaInterface cordova) {
    super(parentEngine);

    this.parentEngine = parentEngine;
    this.cordova = cordova;
  }

  @Override
  public void onPermissionRequest(final PermissionRequest request) {
    Log.d(LOG_TAG, "onPermissionRequest: " + Arrays.toString(request.getResources()));

    final String mediaName = getRequestedMediaName(request);
    if (mediaName == null) {
      // Only handle microphone/camera permissions.
      request.deny();

      return;
    }

    if (cordova == null || cordova.getActivity() == null) {
      request.deny();

      return;
    }

    // Keep previous behaviour on old Android versions where runtime permissions do not apply.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      showMediaCapturePrompt(request, mediaName);

      return;
    }

    final List<String> missingPermissions = getMissingAndroidPermissions(request);

    if (missingPermissions.isEmpty()) {
      showMediaCapturePrompt(request, mediaName);

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
          onPermissionRequestResult(requestCode, grantResults, mediaName);
        }

        @Override
        public void onRequestPermissionsResult(int callbackRequestCode, String[] grantedPermissions, int[] grantResults)
            throws JSONException {
          onPermissionRequestResult(requestCode, grantResults, mediaName);
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

  /**
   * Resolves which Android runtime permissions are still missing for a WebView permission request.
   *
   * @param request WebView permission request containing requested media resources
   * @return list of Android permissions that must be requested from the user
   */
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

  /**
   * Adds a permission string to the list only when it is not already present.
   *
   * @param permissions mutable collection of permission names
   * @param permission Android permission to include
   */
  private void addPermissionIfMissing(List<String> permissions, String permission) {
    if (!permissions.contains(permission)) {
      permissions.add(permission);
    }
  }

  /**
   * Handles the runtime permission result and either proceeds with a media prompt or denies access.
   *
   * @param requestCode generated request code associated with the original WebView request
   * @param grantResults Android grant results received from the permission callback
   * @param mediaName user-facing media name used in the capture dialog
   */
  private void onPermissionRequestResult(int requestCode, int[] grantResults, String mediaName) {
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
    final String requestedMediaName = mediaName;
    cordova.getActivity().runOnUiThread(new Runnable() {
      @Override
      public void run() {
        if (isGranted) {
          showMediaCapturePrompt(permissionRequest, requestedMediaName);
        } else {
          permissionRequest.deny();
        }
      }
    });
  }

  /**
   * Converts requested WebView media resources into a user-friendly media label.
   *
   * @param request WebView permission request
   * @return "camera", "microphone", "camera and microphone", or null for unsupported resources
   */
  private String getRequestedMediaName(PermissionRequest request) {
    boolean hasAudio = false;
    boolean hasVideo = false;

    for (String resource : request.getResources()) {
      if (PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource)) {
        hasAudio = true;
      } else if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(resource)) {
        hasVideo = true;
      }
    }

    if (hasAudio && hasVideo) {
      return "camera and microphone";
    }

    if (hasVideo) {
      return "camera";
    }

    if (hasAudio) {
      return "microphone";
    }

    return null;
  }

  /**
   * Shows the native confirmation dialog before granting WebView media capture access.
   *
   * @param request WebView permission request to grant or deny
   * @param mediaName user-facing name of the requested media capability
   */
  private void showMediaCapturePrompt(final PermissionRequest request, String mediaName) {
    if (cordova == null || cordova.getActivity() == null) {
      request.deny();

      return;
    }

    final Activity activity = cordova.getActivity();
    final String host = getDisplayHostForRequest(request);
    final String message = "\"" + host + "\" would like to access the " + mediaName + ".";

    activity.runOnUiThread(new Runnable() {
      @Override
      public void run() {
        if (activity.isFinishing() || (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1 && activity.isDestroyed())) {
          request.deny();

          return;
        }

        AlertDialog dialog = new AlertDialog.Builder(activity)
            .setMessage(message)
            .setPositiveButton("Allow", new DialogInterface.OnClickListener() {
              @Override
              public void onClick(DialogInterface dialogInterface, int which) {
                request.grant(request.getResources());
              }
            })
            .setNegativeButton("Don't Allow", new DialogInterface.OnClickListener() {
              @Override
              public void onClick(DialogInterface dialogInterface, int which) {
                request.deny();
              }
            })
            .setOnCancelListener(new DialogInterface.OnCancelListener() {
              @Override
              public void onCancel(DialogInterface dialogInterface) {
                request.deny();
              }
            })
            .create();

        dialog.show();
        applyRoundedCorners(dialog, activity);
      }
    });
  }

  /**
   * Applies rounded-corner styling to an AlertDialog background.
   *
   * @param dialog dialog to style
   * @param activity host activity used to resolve theme colors and dimensions
   */
  private void applyRoundedCorners(AlertDialog dialog, Activity activity) {
    if (dialog.getWindow() == null) {
      return;
    }

    GradientDrawable background = new GradientDrawable();
    background.setShape(GradientDrawable.RECTANGLE);
    background.setColor(resolveDialogBackgroundColor(activity));
    background.setCornerRadius(dpToPx(activity, 20f));

    dialog.getWindow().setBackgroundDrawable(background);
  }

  /**
   * Resolves the best background color for dialogs from the current activity theme.
   *
   * @param activity activity whose theme is used for color resolution
   * @return resolved dialog background color or white as a fallback
   */
  private int resolveDialogBackgroundColor(Activity activity) {
    TypedValue typedValue = new TypedValue();
    if (activity.getTheme().resolveAttribute(android.R.attr.colorBackgroundFloating, typedValue, true)) {
      return typedValue.data;
    }

    if (activity.getTheme().resolveAttribute(android.R.attr.colorBackground, typedValue, true)) {
      return typedValue.data;
    }

    return Color.WHITE;
  }

  /**
   * Converts density-independent pixels (dp) to physical pixels.
   *
   * @param activity activity used to read display metrics
   * @param valueInDp value in density-independent pixels
   * @return corresponding pixel value
   */
  private float dpToPx(Activity activity, float valueInDp) {
    return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, valueInDp, activity.getResources().getDisplayMetrics());
  }

  /**
   * Determines the display host to show in the media permission prompt.
   *
   * @param request WebView permission request containing the origin URL
   * @return app name for trusted app host requests, otherwise the origin host when available
   */
  private String getDisplayHostForRequest(PermissionRequest request) {
    String requestHost = null;
    if (request.getOrigin() != null) {
      requestHost = request.getOrigin().getHost();
    }

    String webViewHost = getCurrentWebViewHost();
    if (requestHost != null && requestHost.length() > 0 && webViewHost != null && requestHost.equalsIgnoreCase(webViewHost)) {
      return getAppName();
    }

    if (requestHost != null && requestHost.length() > 0) {
      return requestHost;
    }

    return getAppName();
  }

  /**
   * Reads the host of the currently loaded WebView URL.
   *
   * @return current WebView host or null when unavailable
   */
  private String getCurrentWebViewHost() {
    try {
      if (parentEngine == null || parentEngine.getView() == null || !(parentEngine.getView() instanceof WebView)) {
        return null;
      }

      String currentUrl = ((WebView) parentEngine.getView()).getUrl();
      if (currentUrl == null || currentUrl.length() == 0) {
        return null;
      }

      Uri currentUri = Uri.parse(currentUrl);
      return currentUri.getHost();
    } catch (Throwable e) {
      Log.w(LOG_TAG, "Unable to resolve current WebView host", e);

      return null;
    }
  }

  /**
   * Resolves the application label for user-facing permission messages.
   *
   * @return application label or "this app" as a fallback
   */
  private String getAppName() {
    if (cordova == null || cordova.getActivity() == null) {
      return "this app";
    }

    CharSequence label = cordova.getActivity().getApplicationInfo().loadLabel(cordova.getActivity().getPackageManager());
    if (label != null) {
      String appName = label.toString().trim();
      if (appName.length() > 0) {
        return appName;
      }
    }

    return "this app";
  }
}
