import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;

import 'package:dto_generator/src/utils/string_utils.dart';
import 'package:dto_generator/src/utils/type_mapper.dart';
import 'package:dto_generator/src/utils/yaml_utils.dart';

/// Main class responsible for generating DTOs from OpenAPI/Swagger specifications
class DtoGenerator {
  final String swaggerFilePath;
  final String? outputDirPath;
  final bool isJsonInput;

  DtoGenerator({
    required this.swaggerFilePath,
    this.outputDirPath,
    bool? isJsonInput,
  }) : isJsonInput =
            isJsonInput ?? swaggerFilePath.toLowerCase().endsWith('.json');

  /// Creates a file name for the DTO class
  String _createDtoFileName(String className) {
    final snakeCase = camelCaseToSnakeCase(className);
    return '${snakeCase}_response_dto.dart';
  }

  /// Creates a file name for the list wrapper DTO
  String _createListDtoFileName(String className) {
    final snakeCase = camelCaseToSnakeCase(className);
    return '${snakeCase}_list_response_dto.dart';
  }

  /// Generates the list wrapper DTO class
  String _generateListWrapperClass(String itemClassName) {
    final buffer = StringBuffer();
    buffer.writeln("import '${_createDtoFileName(itemClassName)}';");
    buffer.writeln();

    final className = '${itemClassName}ListResponseDto';
    buffer.writeln('class $className {');
    buffer.writeln('  final List<${itemClassName}ResponseDto> items;');
    buffer.writeln();
    buffer.writeln('  $className({');
    buffer.writeln('    required this.items,');
    buffer.writeln('  });');
    buffer.writeln();
    buffer.writeln(
        '  factory $className.fromJson(List<Map<String, dynamic>> json) {');
    buffer.writeln('    return $className(');
    buffer.writeln(
        '      items: json.map((e) => ${itemClassName}ResponseDto.fromJson(e)).toList(),');
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln('}');

    return buffer.toString();
  }

  /// Generates DTO classes from the Swagger/OpenAPI specification
  Future<void> generate() async {
    // 1. Determine the output directory (gen folder next to the input file)
    final inputFile = File(swaggerFilePath);
    if (!inputFile.existsSync()) {
      throw Exception('File not found at $swaggerFilePath');
    }

    final inputDir = path.dirname(inputFile.absolute.path);
    final outputDir = Directory(outputDirPath ?? path.join(inputDir, 'gen'));

    // Create output directory if it doesn't exist
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    // 2. Read and parse the Swagger/OpenAPI file
    final fileContent = inputFile.readAsStringSync();
    final parsedData = _parseInputFile(fileContent);
    final swagger = _normalizeInput(parsedData);

    // 3. Get or infer schema definitions
    final definitions = _getOrInferDefinitions(swagger);
    if (definitions == null) {
      throw Exception('No schemas could be inferred from the file.');
    }

    // 4. Create mappings for class names
    final Map<String, String> schemaToClassName = {};
    for (final key in definitions.keys) {
      final className = sanitizeClassName(key);
      schemaToClassName[key] = className;
    }

    // 5. Generate DTOs
    final Set<String> processedKeys = {};
    while (processedKeys.length < schemaToClassName.length) {
      final newKeys = schemaToClassName.keys
          .where((k) => !processedKeys.contains(k))
          .toList();

      for (final key in newKeys) {
        final className = schemaToClassName[key]!;
        final schema = definitions[key] as Map<String, dynamic>;
        final inlineNestedDtos =
            isJsonInput ? <String, Map<String, dynamic>>{} : null;

        // Track nested DTOs that need their own files
        final nestedDtos = <String, String>{};

        // Generate the main DTO
        final dtoCode = _generateDtoClass(
          className,
          schema,
          definitions,
          schemaToClassName,
          <String>{},
          isJsonInput,
          inlineNestedDtos: inlineNestedDtos,
          nestedDtos: nestedDtos,
          parentClassName: null,
        );

        final fileName = _createDtoFileName(className);
        final outputFile = File(path.join(outputDir.path, fileName));
        outputFile.writeAsStringSync(dtoCode);
        print('Generated: ${outputFile.path}');

        // Generate files for nested DTOs
        for (final entry in nestedDtos.entries) {
          final nestedFileName = _createDtoFileName(entry.key);
          final nestedFile = File(path.join(outputDir.path, nestedFileName));
          nestedFile.writeAsStringSync(entry.value);
          print('Generated nested: ${nestedFile.path}');
        }

        // If this is from a list input, also generate the list wrapper
        if (parsedData is List && className == 'InferredDto') {
          final listDtoCode = _generateListWrapperClass(className);
          final listFileName = _createListDtoFileName(className);
          final listFile = File(path.join(outputDir.path, listFileName));
          listFile.writeAsStringSync(listDtoCode);
          print('Generated: ${listFile.path}');
        }

        processedKeys.add(key);
      }
    }

    print('\nDTO generation complete! Files generated in: ${outputDir.path}');
  }

  /// Parses the input file content based on its format
  dynamic _parseInputFile(String fileContent) {
    try {
      if (!isJsonInput) {
        final yamlDoc = loadYaml(fileContent);
        return yamlToMap(yamlDoc);
      } else {
        return jsonDecode(fileContent);
      }
    } catch (e) {
      throw Exception('Error parsing file: $e');
    }
  }

  /// Normalizes the input data into a Map<String, dynamic>
  Map<String, dynamic> _normalizeInput(dynamic parsedData) {
    if (parsedData is Map<String, dynamic>) {
      return inferSchema(parsedData);
    } else if (parsedData is List) {
      if (parsedData.isNotEmpty) {
        print("Input JSON is a list. Creating DTO from first item.");
        return inferSchema(parsedData.first);
      } else {
        throw Exception("Input JSON is an empty list. Nothing to infer.");
      }
    } else {
      throw Exception("Unexpected data format.");
    }
  }

  /// Gets schema definitions from the input or infers them
  Map<String, dynamic>? _getOrInferDefinitions(Map<String, dynamic> swagger) {
    // For direct JSON input (not OpenAPI/Swagger), use the schema directly
    if (isJsonInput) {
      return {"InferredDto": swagger};
    }

    // For OpenAPI/Swagger, try to get from components or definitions
    var definitions =
        swagger['components']?['schemas'] ?? swagger['definitions'];

    if (definitions == null) {
      if (swagger.containsKey("paths")) {
        final example = _findExampleFromPaths(swagger["paths"]);
        if (example != null) {
          print(
              "No global schemas found. Inferred schema from example response.");
          return {"InferredDto": inferSchema(example)};
        }
      } else {
        print(
            "No global schemas or paths found. Inferring schema from entire JSON file.");
        return {"InferredDto": inferSchema(swagger)};
      }
    }

    return definitions;
  }

  /// Finds an example response from the paths object
  dynamic _findExampleFromPaths(Map<String, dynamic> paths) {
    for (final pathValue in paths.values) {
      if (pathValue is! Map<String, dynamic>) continue;

      for (final methodValue in pathValue.values) {
        if (methodValue is! Map<String, dynamic>) continue;
        if (!methodValue.containsKey("responses")) continue;

        final responses = methodValue["responses"] as Map<String, dynamic>;
        for (final responseValue in responses.values) {
          if (responseValue is! Map<String, dynamic>) continue;
          if (!responseValue.containsKey("content")) continue;

          final content = responseValue["content"] as Map<String, dynamic>;
          if (!content.containsKey("application/json")) continue;

          final appJson = content["application/json"] as Map<String, dynamic>;
          if (appJson.containsKey("example")) {
            return appJson["example"];
          }

          if (appJson.containsKey("schema") &&
              appJson["schema"] is Map<String, dynamic>) {
            final schemaPart = appJson["schema"] as Map<String, dynamic>;
            if (schemaPart.containsKey("example")) {
              return schemaPart["example"];
            }
          }
        }
      }
    }
    return null;
  }

  /// Generates a Dart class annotated with @JsonSerializable for the given schema
  String _generateDtoClass(
    String className,
    Map<String, dynamic> schema,
    Map<String, dynamic> definitions,
    Map<String, String> schemaToClassName,
    Set<String> imports,
    bool isJsonInput, {
    Map<String, Map<String, dynamic>>? inlineNestedDtos,
    Map<String, String>? nestedDtos,
    String? parentClassName,
  }) {
    final properties = schema['properties'] is Map
        ? Map<String, dynamic>.from(schema['properties'])
        : <String, dynamic>{};
    final requiredProps = schema['required'] as List<dynamic>? ?? [];

    final buffer = StringBuffer();
    buffer.writeln("import 'package:json_annotation/json_annotation.dart';");

    // Add imports for referenced DTOs
    final importsBuffer = StringBuffer();

    // Use snake_case for the part file name with _response_dto suffix
    final partFileName =
        '${camelCaseToSnakeCase(className)}_response_dto.g.dart';
    buffer.writeln("part '$partFileName';");
    buffer.writeln();

    // First generate any nested classes that should be inline
    final nestedClasses = StringBuffer();
    properties.forEach((propName, propSchema) {
      if (propSchema is Map<String, dynamic>) {
        // Handle array types
        if (propSchema['type'] == 'array' &&
            propSchema['items'] is Map<String, dynamic>) {
          final itemSchema = propSchema['items'] as Map<String, dynamic>;
          if (itemSchema['type'] == 'object' &&
              itemSchema['properties'] is Map) {
            // Create a class for the array item type - remove 'Item' suffix
            final itemClassName = capitalize(toDartFieldName(propName));

            final nestedCode = _generateDtoClass(
              itemClassName,
              itemSchema,
              definitions,
              schemaToClassName,
              <String>{},
              isJsonInput,
              nestedDtos: nestedDtos,
              parentClassName: className,
            );

            if (nestedDtos != null) {
              nestedDtos[itemClassName] = nestedCode;
              importsBuffer
                  .writeln("import '${_createDtoFileName(itemClassName)}';");
            }
          }
        }
        // Handle object types
        else if (propSchema['type'] == 'object' &&
            propSchema['properties'] is Map) {
          final nestedProps = propSchema['properties'] as Map<String, dynamic>;

          bool checkDeepNesting(Map<String, dynamic> props) {
            return props.values.any((prop) {
              if (prop is Map<String, dynamic>) {
                if (prop['type'] == 'array') {
                  final items = prop['items'];
                  if (items is Map<String, dynamic> &&
                      items['type'] == 'object' &&
                      items['properties'] is Map) {
                    return true;
                  }
                }
                if (prop['type'] == 'object' && prop['properties'] is Map) {
                  return checkDeepNesting(
                      prop['properties'] as Map<String, dynamic>);
                }
              }
              return false;
            });
          }

          final hasDeepNesting = checkDeepNesting(nestedProps);
          final nestedClassName = capitalize(toDartFieldName(propName));

          if (!hasDeepNesting) {
            // Simple nested object - include in the same file
            nestedClasses.writeln();
            nestedClasses.writeln('@JsonSerializable()');
            nestedClasses.writeln('class ${nestedClassName}ResponseDto {');

            final nestedRequired =
                propSchema['required'] as List<dynamic>? ?? [];

            nestedProps.forEach((nestedPropName, nestedPropSchema) {
              final dartType = mapSwaggerTypeToDartType(
                nestedPropSchema,
                definitions,
                schemaToClassName,
                imports,
                propertyName: nestedPropName,
                isJsonInput: isJsonInput,
              );

              final isRequired = nestedRequired.contains(nestedPropName);
              final nullabilitySuffix = isRequired ? '' : '?';
              final dartFieldName = toDartFieldName(nestedPropName);

              if (nestedPropName != dartFieldName) {
                nestedClasses.writeln('  @JsonKey(name: "$nestedPropName")');
              }
              nestedClasses.writeln(
                  '  final $dartType$nullabilitySuffix $dartFieldName;');
            });

            // Constructor
            nestedClasses.write('\n  const ${nestedClassName}ResponseDto({');
            bool firstField = true;
            for (final nestedPropName in nestedProps.keys) {
              final dartFieldName = toDartFieldName(nestedPropName);
              final isRequired = nestedRequired.contains(nestedPropName);
              if (!firstField) nestedClasses.write(', ');
              if (isRequired) {
                nestedClasses.write('required this.$dartFieldName');
              } else {
                nestedClasses.write('this.$dartFieldName');
              }
              firstField = false;
            }
            nestedClasses.writeln('});');

            // fromJson / toJson methods
            nestedClasses.writeln();
            nestedClasses.writeln(
                '  factory ${nestedClassName}ResponseDto.fromJson(Map<String, dynamic> json) =>');
            nestedClasses.writeln(
                '      _\$${nestedClassName}ResponseDtoFromJson(json);');
            nestedClasses.writeln();
            nestedClasses.writeln(
                '  Map<String, dynamic> toJson() => _\$${nestedClassName}ResponseDtoToJson(this);');
            nestedClasses.writeln('}');
          } else {
            // Complex nested object with its own nesting - create a separate file
            final fullClassName = parentClassName != null
                ? '$parentClassName$nestedClassName'
                : nestedClassName;

            final nestedCode = _generateDtoClass(
              fullClassName,
              propSchema,
              definitions,
              schemaToClassName,
              <String>{},
              isJsonInput,
              nestedDtos: nestedDtos,
              parentClassName: fullClassName,
            );

            if (nestedDtos != null) {
              nestedDtos[fullClassName] = nestedCode;
              importsBuffer.writeln(
                  "import '${camelCaseToSnakeCase(fullClassName)}_response_dto.dart';");
            }
          }
        }
      }
    });

    buffer.writeln('@JsonSerializable(explicitToJson: true)');
    buffer.writeln('class ${className}ResponseDto {');

    // Generate fields
    properties.forEach((propName, propSchema) {
      String dartType;
      if (propSchema is Map<String, dynamic> &&
          propSchema['type'] == 'object' &&
          propSchema['properties'] is Map) {
        final nestedClassName = capitalize(toDartFieldName(propName));

        // Always append ResponseDto to nested object types
        dartType = '${nestedClassName}ResponseDto';
      } else {
        dartType = mapSwaggerTypeToDartType(
          propSchema,
          definitions,
          schemaToClassName,
          imports,
          propertyName: propName,
          isJsonInput: isJsonInput,
          inlineNestedDtos: inlineNestedDtos,
        );
      }

      final isRequired = requiredProps.contains(propName);
      final nullabilitySuffix = isRequired ? '' : '?';
      final dartFieldName = toDartFieldName(propName);

      if (propName != dartFieldName) {
        buffer.writeln('  @JsonKey(name: "$propName")');
      }
      buffer.writeln('  final $dartType$nullabilitySuffix $dartFieldName;');
    });

    // Constructor
    buffer.write('\n  const ${className}ResponseDto({');
    bool firstField = true;
    for (final propName in properties.keys) {
      final dartFieldName = toDartFieldName(propName);
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

    // fromJson / toJson methods
    buffer.writeln();
    buffer.writeln(
        '  factory ${className}ResponseDto.fromJson(Map<String, dynamic> json) =>');
    buffer.writeln('      _\$${className}ResponseDtoFromJson(json);');
    buffer.writeln();
    buffer.writeln(
        '  Map<String, dynamic> toJson() => _\$${className}ResponseDtoToJson(this);');
    buffer.writeln('}');

    // Add any nested classes after the main class
    if (nestedClasses.isNotEmpty) {
      buffer.writeln();
      buffer.write(nestedClasses.toString());
    }

    // Prepend imports
    for (final import in imports) {
      // Remove any existing _response_dto suffix before adding it once
      final importPath = import.endsWith('_response_dto.dart')
          ? import
          : import.replaceAll('.dart', '_response_dto.dart');
      importsBuffer.writeln("import '$importPath';");
    }
    return buffer.toString().replaceFirst('\n', '\n$importsBuffer\n');
  }
}

/// Capitalizes the first letter of a string
String capitalize(String s) => s[0].toUpperCase() + s.substring(1);
