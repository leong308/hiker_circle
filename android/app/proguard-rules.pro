# Only development-signed builds include this provider. Native startup selects
# it through reflection; retain its factory in minified local release APKs.
-keep class com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory {
    public static com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory getInstance();
}
