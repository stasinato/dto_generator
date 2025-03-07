import 'package:yaml/yaml.dart';

/// Recursively converts a YAML document into standard Dart objects.
dynamic yamlToMap(dynamic yamlDoc) {
  if (yamlDoc is YamlMap) {
    final map = <String, dynamic>{};
    for (final entry in yamlDoc.entries) {
      map[entry.key.toString()] = yamlToMap(entry.value);
    }
    return map;
  } else if (yamlDoc is YamlList) {
    return yamlDoc.map((item) => yamlToMap(item)).toList();
  } else {
    return yamlDoc;
  }
}

/// Infers a JSON schema from an example object.
Map<String, dynamic> inferSchema(dynamic example) {
  if (example is Map) {
    final Map<String, dynamic> schema = {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    };
    example.forEach((key, value) {
      schema['properties'][key.toString()] = inferSchema(value);
      if (value != null) {
        (schema['required'] as List).add(key.toString());
      }
    });
    if ((schema['required'] as List).isEmpty) {
      schema.remove('required');
    }
    return schema;
  } else if (example is List) {
    if (example.isNotEmpty) {
      return {
        'type': 'array',
        'items': inferSchema(example.first),
      };
    } else {
      return {
        'type': 'array',
        'items': {},
      };
    }
  } else if (example is int) {
    return {'type': 'integer'};
  } else if (example is double) {
    return {'type': 'number'};
  } else if (example is bool) {
    return {'type': 'boolean'};
  } else if (example is String) {
    return {'type': 'string'};
  } else {
    return {'type': 'string'};
  }
}
