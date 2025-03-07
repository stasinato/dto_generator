<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

# DTO Generator

A Dart package that generates Data Transfer Object (DTO) classes from OpenAPI/Swagger specifications. The generated classes are annotated with `@JsonSerializable` for easy JSON serialization/deserialization.

## Features

- Generates Dart classes from OpenAPI/Swagger specifications (YAML or JSON)
- Supports nested objects and arrays
- Handles references to other schemas
- Generates proper nullable types based on required fields
- Supports date-time formats
- Generates proper camelCase field names from snake_case
- Deduplicates similar schemas to avoid redundant classes
- Inlines small nested objects for better code organization

## Installation

Add this package to your project's `dev_dependencies`:

```yaml
dev_dependencies:
  dto_generator: ^1.0.0
```

## Usage

You can use the package in those ways:

### Command Line

```bash
# Basic usage
dart run dto_generator swagger.yaml

# Specify output directory
dart run dto_generator name_file.yaml lib/models

# Use JSON input
dart run dto_generator name_file.json lib/models
```

## Generated Code Example

For a schema like:

```yaml
components:
  schemas:
    User:
      type: object
      properties:
        id:
          type: integer
        name:
          type: string
        email:
          type: string
      required:
        - id
        - email
```

The generator will create:

```dart
import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable(explicitToJson: true)
class User {
  final int id;
  final String? name;
  final String email;

  User({
    required this.id,
    this.name,
    required this.email,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}
```

After checking generated code, you can run generator as usually:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

```bash
dart pub global activate dto_generator
```
