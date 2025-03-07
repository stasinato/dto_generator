import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';

int _inlineDtoCounter = 0; // used for generating unique inline DTO names

// A global map of schema signatures to class names, so we don't generate duplicates
final Map<String, String> _inlineSchemaSignatures = {};

/// Returns true if the given schema (which must have "properties") is considered "small".
/// Here, small means having 3 or fewer properties.
bool _isSmallNestedObject(Map<String, dynamic> schema) {
  if (!schema.containsKey('properties')) return false;
  final properties = schema['properties'] as Map;
  return properties.length <= 3;
}

/// A Dart script that parses a Swagger/OpenAPI file (in JSON or YAML format)
/// and generates DTO classes annotated with @JsonSerializable.
///
/// If no global schema definitions are found, it attempts to infer a schema from
/// example responses (or, if not available, from the entire JSON file).
///
/// Usage:
///   dart generate_dtos.dart [path_to_swagger_file.yaml or .json] [output_directory]
void main(List<String> args) async {
  // 1. Get the path to the Swagger/OpenAPI file.
  final swaggerFilePath = args.isNotEmpty ? args.first : 'swagger.yaml';
  // Determine if the input is JSON.
  final bool isJsonInput = swaggerFilePath.toLowerCase().endsWith('.json');

  // 2. Directory where generated *.dart files will be created.
  final outputDirPath = args.length > 1 ? args[1] : 'generated_dtos';
  final outputDir = Directory(outputDirPath);
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  // 3. Read and parse the file.
  final File swaggerFile = File(swaggerFilePath);
  if (!swaggerFile.existsSync()) {
    print('Error: File not found at $swaggerFilePath');
    exit(1);
  }
  final fileContent = swaggerFile.readAsStringSync();

  dynamic parsedData;
  try {
    if (swaggerFilePath.toLowerCase().endsWith('.yaml') ||
        swaggerFilePath.toLowerCase().endsWith('.yml')) {
      final yamlDoc = loadYaml(fileContent);
      parsedData = yamlToMap(yamlDoc);
    } else {
      parsedData = jsonDecode(fileContent);
    }
  } catch (e) {
    print('Error parsing file: $e');
    exit(1);
  }

  // 4. Ensure we have a Map<String, dynamic> to work with.
  Map<String, dynamic> swagger;
  if (parsedData is Map<String, dynamic>) {
    swagger = parsedData;
  } else if (parsedData is List) {
    if (parsedData.isNotEmpty) {
      print("Input JSON is a list. Inferring schema from first element.");
      // Wrap the inferred schema in a map to continue processing.
      swagger = {"InferredDto": inferSchema(parsedData.first)};
    } else {
      print("Input JSON is an empty list. Nothing to infer.");
      exit(1);
    }
  } else {
    print("Unexpected data format.");
    exit(1);
  }

  // 5. Look for schema definitions.
  var definitions = swagger['components']?['schemas'] ?? swagger['definitions'];

  // 6. If definitions are missing, try to infer them from example responses.
  if (definitions == null) {
    if (swagger.containsKey("paths")) {
      dynamic example;
      final paths = swagger["paths"] as Map<String, dynamic>;
      // Iterate through the paths and HTTP methods to find an example.
      for (final pathEntry in paths.entries) {
        final pathValue = pathEntry.value;
        if (pathValue is Map<String, dynamic>) {
          for (final methodEntry in pathValue.entries) {
            final methodValue = methodEntry.value;
            if (methodValue is Map<String, dynamic> &&
                methodValue.containsKey("responses")) {
              final responses =
                  methodValue["responses"] as Map<String, dynamic>;
              for (final responseEntry in responses.entries) {
                final responseValue = responseEntry.value;
                if (responseValue is Map<String, dynamic> &&
                    responseValue.containsKey("content")) {
                  final content =
                      responseValue["content"] as Map<String, dynamic>;
                  if (content.containsKey("application/json")) {
                    final appJson =
                        content["application/json"] as Map<String, dynamic>;
                    // Look for an example.
                    if (appJson.containsKey("example")) {
                      example = appJson["example"];
                      break;
                    } else if (appJson.containsKey("schema") &&
                        appJson["schema"] is Map<String, dynamic>) {
                      final schemaPart =
                          appJson["schema"] as Map<String, dynamic>;
                      if (schemaPart.containsKey("example")) {
                        example = schemaPart["example"];
                        break;
                      }
                    }
                  }
                }
              }
            }
            if (example != null) break;
          }
        }
        if (example != null) break;
      }
      if (example != null) {
        print(
            "No global schemas found. Inferred schema from example response.");
        definitions = {"InferredDto": inferSchema(example)};
      }
    } else {
      // If there are no paths, assume the entire file is the example.
      print(
          "No global schemas or paths found. Inferring schema from entire JSON file.");
      definitions = {"InferredDto": inferSchema(swagger)};
    }
  }

  if (definitions == null) {
    print('No schemas could be inferred from the file.');
    exit(1);
  }

  // 7. Create mappings for class names.
  // We'll use schemaToClassName to track both global and inline DTOs.
  final Map<String, String> schemaToClassName = {};
  for (final key in definitions.keys) {
    final className = _sanitizeClassName(key);
    schemaToClassName[key] = className;
  }

  // 8. Generate a Dart file for each schema (global and inline).
  final Set<String> processedKeys = {};
  while (processedKeys.length < schemaToClassName.length) {
    final newKeys = schemaToClassName.keys
        .where((k) => !processedKeys.contains(k))
        .toList();
    for (final key in newKeys) {
      final className = schemaToClassName[key]!;
      final schema = definitions[key] as Map<String, dynamic>;
      // For JSON input, collect inline nested classes in this map.
      final inlineNestedDtos =
          isJsonInput ? <String, Map<String, dynamic>>{} : null;
      final dtoCode = generateDtoClass(className, schema, definitions,
          schemaToClassName, <String>{}, isJsonInput,
          inlineNestedDtos: inlineNestedDtos);
      // Generate file name using snake_case.
      final fileName = '${_camelCaseToSnakeCase(className)}.dart';
      final outputFile = File('${outputDir.path}/$fileName');
      outputFile.writeAsStringSync(dtoCode);
      print('Generated: ${outputFile.path}');
      processedKeys.add(key);
    }
  }

  print('\nDTO generation complete!');
}

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

/// Generates a Dart class annotated with @JsonSerializable for the given schema.
/// For JSON input, if inline nested objects are small, they are generated inline (within the same file).
String generateDtoClass(
  String className,
  Map<String, dynamic> schema,
  Map<String, dynamic> definitions,
  Map<String, String> schemaToClassName,
  Set<String> processedSchemas,
  bool isJsonInput, {
  Map<String, Map<String, dynamic>>? inlineNestedDtos,
}) {
  inlineNestedDtos ??= {};
  final properties = schema['properties'] is Map
      ? Map<String, dynamic>.from(schema['properties'])
      : <String, dynamic>{};
  final requiredProps = schema['required'] as List<dynamic>? ?? [];

  final Set<String> imports = {};
  final buffer = StringBuffer();
  buffer.writeln("import 'package:json_annotation/json_annotation.dart';");
  final importsBuffer = StringBuffer();
  // Use snake_case for the part file name.
  buffer.writeln("part '${_camelCaseToSnakeCase(className)}.g.dart';");
  buffer.writeln();
  buffer.writeln('@JsonSerializable(explicitToJson: true)');
  buffer.writeln('class $className {');

  // Generate fields.
  properties.forEach((propName, propSchema) {
    final dartType = _mapSwaggerTypeToDartType(
        propSchema, definitions, schemaToClassName, imports,
        propertyName: propName,
        isJsonInput: isJsonInput,
        inlineNestedDtos: inlineNestedDtos);
    final isRequired = requiredProps.contains(propName);
    final nullabilitySuffix = isRequired ? '' : '?';
    final dartFieldName = _toDartFieldName(propName);
    if (propName != dartFieldName) {
      buffer.writeln('  @JsonKey(name: "$propName")');
    }
    buffer.writeln('  final $dartType$nullabilitySuffix $dartFieldName;');
  });

  // Constructor.
  buffer.write('\n  $className({');
  bool firstField = true;
  for (final propName in properties.keys) {
    final dartFieldName = _toDartFieldName(propName);
    final isRequired = requiredProps.contains(propName);
    if (!firstField) buffer.write(', ');
    if (isRequired) {
      buffer.write('required this.$dartFieldName');
    } else {
      buffer.write('this.$dartFieldName');
    }
    firstField = false;
  }
  buffer.writeln('});');

  // fromJson / toJson methods.
  buffer.writeln();
  buffer.writeln(
      '  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);');
  buffer.writeln(
      '  Map<String, dynamic> toJson() => _\$${className}ToJson(this);');
  buffer.writeln('}');

  // Prepend additional imports.
  for (final import in imports) {
    importsBuffer.writeln("import '$import';");
  }
  final classCode = buffer.toString().replaceFirst('\n', '\n$importsBuffer\n');

  // If JSON input and inline nested DTOs were collected, append them.
  if (isJsonInput && inlineNestedDtos.isNotEmpty) {
    final nestedBuffer = StringBuffer();
    inlineNestedDtos.forEach((nestedClassName, nestedSchema) {
      nestedBuffer.writeln();
      nestedBuffer.writeln(generateInlineNestedClass(
          nestedClassName, nestedSchema, isJsonInput));
    });
    return classCode + nestedBuffer.toString();
  } else {
    return classCode;
  }
}

/// Generates a Dart class (without file-level import/part directives) for an inline nested DTO.
String generateInlineNestedClass(
    String className, Map<String, dynamic> schema, bool isJsonInput) {
  final properties = schema['properties'] is Map
      ? Map<String, dynamic>.from(schema['properties'])
      : <String, dynamic>{};
  final requiredProps = schema['required'] as List<dynamic>? ?? [];
  final buffer = StringBuffer();
  buffer.writeln('@JsonSerializable()');
  buffer.writeln('class $className {');

  properties.forEach((propName, propSchema) {
    // For nested inline classes, we use a simple mapping (we don’t further inline nested objects here)
    final dartType = _mapSwaggerTypeToDartType(propSchema, {}, {}, <String>{},
        propertyName: propName, isJsonInput: isJsonInput);
    final isRequired = requiredProps.contains(propName);
    final nullabilitySuffix = isRequired ? '' : '?';
    final dartFieldName = _toDartFieldName(propName);
    if (propName != dartFieldName) {
      buffer.writeln('  @JsonKey(name: "$propName")');
    }
    buffer.writeln('  final $dartType$nullabilitySuffix $dartFieldName;');
  });

  buffer.write('  $className({');
  bool firstField = true;
  for (final propName in properties.keys) {
    final dartFieldName = _toDartFieldName(propName);
    final isRequired = requiredProps.contains(propName);
    if (!firstField) buffer.write(', ');
    if (isRequired) {
      buffer.write('required this.$dartFieldName');
    } else {
      buffer.write('this.$dartFieldName');
    }
    firstField = false;
  }
  buffer.writeln('});');

  buffer.writeln(
      '  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);');
  buffer.writeln(
      '  Map<String, dynamic> toJson() => _\$${className}ToJson(this);');
  buffer.writeln('}');
  return buffer.toString();
}

/// Maps a JSON schema snippet to a Dart type.
/// For non-JSON input, inline objects are promoted to separate DTO files (with deduplication).
/// For JSON input, if the nested object is small (as defined by _isSmallNestedObject),
/// it is inlined as a nested class in the same file; otherwise it is treated as Map<String, dynamic>.
String _mapSwaggerTypeToDartType(
  Map<String, dynamic> schema,
  Map<String, dynamic> definitions,
  Map<String, String> schemaToClassName,
  Set<String> imports, {
  String? propertyName,
  bool isJsonInput = false,
  Map<String, Map<String, dynamic>>? inlineNestedDtos,
}) {
  if (schema['\$ref'] != null) {
    final refPath = schema['\$ref'] as String;
    final refParts = refPath.split('/');
    final refName = refParts.last;
    final refClassName = schemaToClassName[refName];
    if (refClassName != null) {
      imports.add('${_camelCaseToSnakeCase(refClassName)}.dart');
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
          if (_isSmallNestedObject(schema)) {
            String nestedClassName;
            if (propertyName != null) {
              nestedClassName = _sanitizeClassName(propertyName);
            } else {
              nestedClassName = 'InlineDto${_inlineDtoCounter++}';
            }
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
          final signature = _computeSchemaSignature(schema);
          if (_inlineSchemaSignatures.containsKey(signature)) {
            final existingClassName = _inlineSchemaSignatures[signature]!;
            imports.add('${_camelCaseToSnakeCase(existingClassName)}.dart');
            return existingClassName;
          } else {
            String newClassName;
            if (propertyName != null) {
              newClassName = _sanitizeClassName(propertyName);
            } else {
              newClassName = 'InlineDto${_inlineDtoCounter++}';
            }
            if (!schemaToClassName.containsValue(newClassName)) {
              definitions[newClassName] = schema;
              schemaToClassName[newClassName] = newClassName;
            }
            _inlineSchemaSignatures[signature] = newClassName;
            imports.add('${_camelCaseToSnakeCase(newClassName)}.dart');
            return newClassName;
          }
        }
      }
      return 'Map<String, dynamic>';

    case 'array':
      final items = schema['items'] as Map<String, dynamic>?;
      if (items != null) {
        final itemType = _mapSwaggerTypeToDartType(
            items, definitions, schemaToClassName, imports,
            propertyName: propertyName,
            isJsonInput: isJsonInput,
            inlineNestedDtos: inlineNestedDtos);
        return 'List<$itemType>';
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
String _computeSchemaSignature(dynamic value) {
  if (value is Map<String, dynamic>) {
    final sortedKeys = value.keys.toList()..sort();
    final map = <String, dynamic>{};
    for (final k in sortedKeys) {
      map[k] = _computeSchemaSignature(value[k]);
    }
    return jsonEncode(map);
  } else if (value is List) {
    return jsonEncode(value.map(_computeSchemaSignature).toList());
  } else {
    return jsonEncode(value);
  }
}

/// Sanitizes a raw name to create a valid Dart class name (CamelCase).
String _sanitizeClassName(String rawName) {
  final words = rawName.split(RegExp(r'[^A-Za-z0-9]+'));
  final className = words.map((word) {
    if (word.isEmpty) return '';
    return word[0].toUpperCase() + word.substring(1);
  }).join('');
  return className.isEmpty ? 'UnnamedDto' : className;
}

/// Converts a JSON property name to a Dart field name (camelCase).
String _toDartFieldName(String propName) {
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
String _camelCaseToSnakeCase(String input) {
  final regex = RegExp(r'(?<=[a-z])(?=[A-Z])');
  return input.split(regex).map((word) => word.toLowerCase()).join('_');
}
