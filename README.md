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

You can use the package in two ways:

### Command Line

```bash
# Basic usage
dart run dto_generator swagger.yaml

# Specify output directory
dart run dto_generator swagger.yaml lib/models

# Use JSON input
dart run dto_generator swagger.json lib/models
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

## Configuration

The generator supports several features that can be controlled:

- Automatic conversion of property names to proper Dart field names
- Handling of required vs optional fields
- Special handling of date-time fields
- Inlining of small nested objects (3 properties or fewer)
- Deduplication of similar schemas

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

```bash
dart pub global activate dto_generator
```
