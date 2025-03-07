/// Sanitizes a raw name to create a valid Dart class name (CamelCase).
String sanitizeClassName(String rawName) {
  final words = rawName.split(RegExp(r'[^A-Za-z0-9]+'));
  final className = words.map((word) {
    if (word.isEmpty) return '';
    return word[0].toUpperCase() + word.substring(1);
  }).join('');
  return className.isEmpty ? 'UnnamedDto' : className;
}

/// Converts a JSON property name to a Dart field name (camelCase).
String toDartFieldName(String propName) {
  if (propName.isEmpty) return 'empty';
  if (propName.contains('_')) {
    final parts = propName.split('_');
    return parts.first +
        parts.skip(1).map((part) {
          if (part.isEmpty) return '';
          return part[0].toUpperCase() + part.substring(1);
        }).join('');
  }
  return propName[0].toLowerCase() + propName.substring(1);
}

/// Converts a CamelCase string to snake_case.
String camelCaseToSnakeCase(String input) {
  final regex = RegExp(r'(?<=[a-z])(?=[A-Z])');
  return input.split(regex).map((word) => word.toLowerCase()).join('_');
}
