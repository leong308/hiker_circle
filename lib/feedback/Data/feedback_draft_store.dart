// Browser drafts use IndexedDB; mobile drafts use the encrypted session store.
export 'feedback_draft_store_sqlite.dart'
    if (dart.library.js_interop) 'feedback_draft_store_web.dart';
