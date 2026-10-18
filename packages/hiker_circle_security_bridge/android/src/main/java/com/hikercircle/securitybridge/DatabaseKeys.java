// DatabaseKeys wraps random SQLCipher passwords with a non-exportable Android Keystore key.
package com.hikercircle.securitybridge;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.AtomicFile;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Locale;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** One process-wide key factory shared by foreground, native and headless workers. */
public final class DatabaseKeys {
  private DatabaseKeys() {}
  public static synchronized String key(Context context, String name) throws Exception {
    if (!"flutter-main".equals(name) && !"native-location".equals(name)) {
      throw new IllegalArgumentException("Invalid database key name");
    }
    KeyStore store = KeyStore.getInstance("AndroidKeyStore");
    store.load(null);
    String alias = "hiker_circle_database_key_wrap_v1";
    File file = new File(context.getNoBackupFilesDir(), "database-key-" + name + ".bin");
    AtomicFile wrapped = new AtomicFile(file);
    boolean existing = file.exists() || new File(file.getPath() + ".bak").exists();
    if (existing && !store.containsAlias(alias)) {
      throw new IllegalStateException("The local database wrapping key is unavailable");
    }
    SecretKey master;
    if (store.containsAlias(alias)) master = (SecretKey) store.getKey(alias, null);
    else {
      KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
      generator.init(new KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
          .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
          .setKeySize(256).setUserAuthenticationRequired(false).build());
      master = generator.generateKey();
    }
    if (existing) {
      byte[] data = wrapped.readFully();
      if (data.length < 29) throw new IllegalStateException("The protected key record is invalid");
      Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
      cipher.init(Cipher.DECRYPT_MODE, master, new GCMParameterSpec(128, Arrays.copyOfRange(data, 0, 12)));
      return new String(cipher.doFinal(Arrays.copyOfRange(data, 12, data.length)), StandardCharsets.UTF_8);
    }
    byte[] bytes = new byte[32]; new SecureRandom().nextBytes(bytes);
    StringBuilder hex = new StringBuilder(64);
    for (byte value : bytes) hex.append(String.format(Locale.ROOT, "%02x", value & 0xff));
    String key = hex.toString();
    Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, master);
    FileOutputStream output = wrapped.startWrite();
    try {
      output.write(cipher.getIV()); output.write(cipher.doFinal(key.getBytes(StandardCharsets.UTF_8)));
      wrapped.finishWrite(output);
    } catch (Exception error) { wrapped.failWrite(output); throw error; }
    return key;
  }
}
