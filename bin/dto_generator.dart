import 'dart:io';

import 'package:dto_generator/src/generator.dart';

/// A Dart script that parses a Swagger/OpenAPI file (in JSON or YAML format)
/// and generates DTO classes annotated with @JsonSerializable.
///
/// If no global schema definitions are found, it attempts to infer a schema from
/// example responses (or, if not available, from the entire JSON file).
///
/// Usage:
///   dart generate_dtos.dart [path_to_swagger_file.yaml or .json] [output_directory]
void main(List<String> args) async {
  if (args.isEmpty) {
    print(
        'Usage: dart generate_dtos.dart [path_to_swagger_file.yaml or .json] [output_directory]');
    return;
  }

  try {
    final generator = DtoGenerator(
      swaggerFilePath: args[0],
      outputDirPath: args.length > 1 ? args[1] : null,
    );

    await generator.generate();
    print('\nDTO generation complete!');
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}
