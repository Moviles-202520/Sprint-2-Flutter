// Web implementation to detect full tab/window close and run a callback
import 'dart:html' as html;

html.EventListener? _listener;

void registerBeforeUnload(void Function() onUnload) {
  // Use 'beforeunload' to catch tab close and refresh; not fired on simple tab switch
  _listener ??= (event) {
    try {
      onUnload();
    } catch (_) {}
    // Optionally show confirmation dialog; disabled to avoid blocking.
    // event.preventDefault();
  };
  html.window.addEventListener('beforeunload', _listener!);
}

void unregisterBeforeUnload() {
  if (_listener != null) {
    html.window.removeEventListener('beforeunload', _listener!);
    _listener = null;
  }
}