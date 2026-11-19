final Map<String, String> _memoryFallback = {};

String? readLocalStorage(String key) => _memoryFallback[key];

void writeLocalStorage(String key, String value) {
  _memoryFallback[key] = value;
}

void removeLocalStorage(String key) {
  _memoryFallback.remove(key);
}
