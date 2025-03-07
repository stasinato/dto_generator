import 'dart:convert';
import 'package:dto_generator/src/utils/string_utils.dart';
import 'package:dto_generator/src/generator.dart';

/// A global map of schema signatures to class names, so we don't generate duplicates
final Map<String, String> _inlineSchemaSignatures = {};

/// Returns true if the given schema (which must have "properties") is considered "small".
/// Here, small means having 3 or fewer properties.
bool isSmallNestedObject(Map<String, dynamic> schema) {
  if (!schema.containsKey('properties')) return false;
  final properties = schema['properties'] as Map;
  return properties.length <= 3;
}

/// Maps a JSON schema snippet to a Dart type.
String mapSwaggerTypeToDartType(
  Map<String, dynamic> schema,
  Map<String, dynamic> definitions,
  Map<String, String> schemaToClassName,
  Set<String> imports, {
  required String propertyName,
  required bool isJsonInput,
  Map<String, Map<String, dynamic>>? inlineNestedDtos,
}) {
  if (schema['\$ref'] != null) {
    final refPath = schema['\$ref'] as String;
    final refParts = refPath.split('/');
    final refName = refParts.last;
    final refClassName = schemaToClassName[refName];
    if (refClassName != null) {
      imports.add('${camelCaseToSnakeCase(refClassName)}.dart');
      return refClassName;
    }
    return 'dynamic';
  }
  final type = schema['type'] as String?;
  final format = schema['format'] as String?;
  if (type == null) return 'dynamic';

  switch (type) {
    case 'object':
      if (schema.containsKey('properties')) {
        if (isJsonInput) {
          // For JSON input, if the object is small, inline it as a nested class.
          if (isSmallNestedObject(schema)) {
            String nestedClassName = sanitizeClassName(propertyName);

            if (inlineNestedDtos != null &&
                !inlineNestedDtos.containsKey(nestedClassName)) {
              inlineNestedDtos[nestedClassName] = schema;
            }
            return nestedClassName;
          } else {
            // For larger objects in JSON, use a generic map.
            return 'Map<String, dynamic>';
          }
        } else {
          // For YAML or non-JSON input: deduplicate and promote to separate DTO.
          final signature = computeSchemaSignature(schema);
          if (_inlineSchemaSignatures.containsKey(signature)) {
            final existingClassName = _inlineSchemaSignatures[signature]!;
            imports.add('${camelCaseToSnakeCase(existingClassName)}.dart');
            return existingClassName;
          } else {
            String newClassName = sanitizeClassName(propertyName);

            if (!schemaToClassName.containsValue(newClassName)) {
              definitions[newClassName] = schema;
              schemaToClassName[newClassName] = newClassName;
            }
            _inlineSchemaSignatures[signature] = newClassName;
            imports.add('${camelCaseToSnakeCase(newClassName)}.dart');
            return newClassName;
          }
        }
      }
      return 'Map<String, dynamic>';

    case 'array':
      final itemSchema = schema['items'];
      if (itemSchema is Map<String, dynamic>) {
        if (itemSchema['type'] == 'object' && itemSchema['properties'] is Map) {
          // For object arrays, use the property name as the type
          final itemClassName = capitalize(propertyName);
          return 'List<${itemClassName}ResponseDto>';
        }
        return 'List<${mapSwaggerTypeToDartType(itemSchema, definitions, schemaToClassName, imports, propertyName: propertyName, isJsonInput: isJsonInput)}>';
      }
      return 'List<dynamic>';

    case 'string':
      if (format == 'date-time' || format == 'date') {
        return 'DateTime';
      }
      return 'String';

    case 'integer':
      return 'int';

    case 'boolean':
      return 'bool';

    case 'number':
      return 'double';

    default:
      return 'dynamic';
  }
}

/// Produces a canonical "signature" string for a given schema object,
/// so we can detect if two schemas have the same shape.
String computeSchemaSignature(dynamic value) {
  if (value is Map<String, dynamic>) {
    final sortedKeys = value.keys.toList()..sort();
    final map = <String, dynamic>{};
    for (final k in sortedKeys) {
      map[k] = computeSchemaSignature(value[k]);
    }
    return jsonEncode(map);
  } else if (value is List) {
    return jsonEncode(value.map(computeSchemaSignature).toList());
  } else {
    return jsonEncode(value);
  }
}
