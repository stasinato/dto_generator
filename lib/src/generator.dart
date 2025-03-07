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

        final dtoCode = generateDtoClass(
          className,
          schema,
          definitions,
          schemaToClassName,
          <String>{},
          isJsonInput,
          inlineNestedDtos: inlineNestedDtos,
        );

        final fileName = _createDtoFileName(className);
        final outputFile = File(path.join(outputDir.path, fileName));
        outputFile.writeAsStringSync(dtoCode);
        print('Generated: ${outputFile.path}');

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
      return parsedData;
    } else if (parsedData is List) {
      if (parsedData.isNotEmpty) {
        print("Input JSON is a list. Inferring schema from first element.");
        return {"InferredDto": inferSchema(parsedData.first)};
      } else {
        throw Exception("Input JSON is an empty list. Nothing to infer.");
      }
    } else {
      throw Exception("Unexpected data format.");
    }
  }

  /// Gets schema definitions from the input or infers them
  Map<String, dynamic>? _getOrInferDefinitions(Map<String, dynamic> swagger) {
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
}

/// Generates a Dart class annotated with @JsonSerializable for the given schema
String generateDtoClass(
  String className,
  Map<String, dynamic> schema,
  Map<String, dynamic> definitions,
  Map<String, String> schemaToClassName,
  Set<String> imports,
  bool isJsonInput, {
  Map<String, Map<String, dynamic>>? inlineNestedDtos,
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
  final partFileName = '${camelCaseToSnakeCase(className)}_response_dto.g.dart';
  buffer.writeln("part '$partFileName';");
  buffer.writeln();
  buffer.writeln('@JsonSerializable(explicitToJson: true)');
  buffer.writeln(
      'class ${className}ResponseDto {'); // Append ResponseDto to the class name

  // Generate fields
  properties.forEach((propName, propSchema) {
    final dartType = mapSwaggerTypeToDartType(
      propSchema,
      definitions,
      schemaToClassName,
      imports,
      propertyName: propName,
      isJsonInput: isJsonInput,
      inlineNestedDtos: inlineNestedDtos,
    );

    final isRequired = requiredProps.contains(propName);
    final nullabilitySuffix = isRequired ? '' : '?';
    final dartFieldName = toDartFieldName(propName);

    if (propName != dartFieldName) {
      buffer.writeln('  @JsonKey(name: "$propName")');
    }
    buffer.writeln('  final $dartType$nullabilitySuffix $dartFieldName;');
  });

  // Constructor
  buffer.write('\n  ${className}ResponseDto({'); // Update constructor name
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
      '  factory ${className}ResponseDto.fromJson(Map<String, dynamic> json) => _\$${className}ResponseDtoFromJson(json);');
  buffer.writeln(
      '  Map<String, dynamic> toJson() => _\$${className}ResponseDtoToJson(this);');
  buffer.writeln('}');

  // Prepend imports
  for (final import in imports) {
    // Update import paths to include _response_dto suffix
    final importPath = import.replaceAll('.dart', '_response_dto.dart');
    importsBuffer.writeln("import '$importPath';");
  }
  final classCode = buffer.toString().replaceFirst('\n', '\n$importsBuffer\n');

  // If JSON input and inline nested DTOs were collected, append them
  if (isJsonInput && inlineNestedDtos?.isNotEmpty == true) {
    final nestedBuffer = StringBuffer();
    inlineNestedDtos!.forEach((nestedClassName, nestedSchema) {
      nestedBuffer.writeln();
      nestedBuffer.writeln(generateInlineNestedClass(
          '${nestedClassName}ResponseDto', nestedSchema, isJsonInput));
    });
    return classCode + nestedBuffer.toString();
  }

  return classCode;
}

/// Generates a Dart class for an inline nested DTO
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
    final dartType = mapSwaggerTypeToDartType(
      propSchema,
      {},
      {},
      <String>{},
      propertyName: propName,
      isJsonInput: isJsonInput,
    );

    final isRequired = requiredProps.contains(propName);
    final nullabilitySuffix = isRequired ? '' : '?';
    final dartFieldName = toDartFieldName(propName);

    if (propName != dartFieldName) {
      buffer.writeln('  @JsonKey(name: "$propName")');
    }
    buffer.writeln('  final $dartType$nullabilitySuffix $dartFieldName;');
  });

  buffer.write('  $className({');
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

  buffer.writeln(
      '  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);');
  buffer.writeln(
      '  Map<String, dynamic> toJson() => _\$${className}ToJson(this);');
  buffer.writeln('}');

  return buffer.toString();
}
