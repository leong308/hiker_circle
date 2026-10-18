// HikerCircleSecurityBridgePlugin registers database keys and migration leases in headless engines.
package com.hikercircle.securitybridge;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.io.File;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodChannel;

/** Activity-independent registration also runs in Firebase/safety background engines. */
public final class HikerCircleSecurityBridgePlugin implements FlutterPlugin {
  private static final Object guard = new Object();
  private static final Map<String, String> leases = new HashMap<>();
  private final String owner = UUID.randomUUID().toString() + ":";
  private volatile boolean attached;
  private MethodChannel channel;
  private ExecutorService worker;
  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
    attached = true;
    Context context = binding.getApplicationContext();
    worker = Executors.newSingleThreadExecutor();
    Handler main = new Handler(Looper.getMainLooper());
    channel = new MethodChannel(binding.getBinaryMessenger(), "hiker_circle/database_security");
    channel.setMethodCallHandler((call, result) -> {
      if ("releaseDatabase".equals(call.method)) {
        try {
          String path = new File((String) call.argument("path")).getCanonicalPath();
          String token = call.argument("lease");
          synchronized (guard) {
            if ((owner + token).equals(leases.get(path))) { leases.remove(path); guard.notifyAll(); }
          }
          result.success(null);
        } catch (Exception error) { result.error("database-lock-unavailable", "Database lock unavailable.", null); }
        return;
      }
      if ("acquireDatabase".equals(call.method)) {
        String requestedPath = call.argument("path");
        worker.execute(() -> {
          try {
            String path = new File(requestedPath).getCanonicalPath();
            String token = UUID.randomUUID().toString();
            synchronized (guard) {
              while (attached && leases.containsKey(path)) guard.wait();
              if (!attached) return;
              leases.put(path, owner + token);
            }
            main.post(() -> result.success(token));
          } catch (Exception error) { main.post(() -> result.error("database-lock-unavailable", "Database lock unavailable.", null)); }
        });
        return;
      }
      if (!"databaseKey".equals(call.method)) { result.notImplemented(); return; }
      String name = call.argument("name");
      worker.execute(() -> {
        try {
          String key = DatabaseKeys.key(context, name);
          main.post(() -> result.success(key));
        } catch (Exception error) {
          main.post(() -> result.error("database-key-unavailable", "The protected local database key is unavailable.", null));
        }
      });
    });
  }
  @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
    attached = false;
    synchronized (guard) {
      leases.entrySet().removeIf(entry -> entry.getValue().startsWith(owner)); guard.notifyAll();
    }
    channel.setMethodCallHandler(null); worker.shutdownNow();
  }
}
