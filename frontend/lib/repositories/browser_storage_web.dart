import 'dart:js_interop';

@JS('window.localStorage.getItem')
external JSString? _jsGetItem(JSString key);

@JS('window.localStorage.setItem')
external void _jsSetItem(JSString key, JSString value);

@JS('window.localStorage.removeItem')
external void _jsRemoveItem(JSString key);

String? readLocalStorage(String key) {
  try {
    return _jsGetItem(key.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}

void writeLocalStorage(String key, String value) {
  try {
    _jsSetItem(key.toJS, value.toJS);
  } catch (_) {}
}

void removeLocalStorage(String key) {
  try {
    _jsRemoveItem(key.toJS);
  } catch (_) {}
}
