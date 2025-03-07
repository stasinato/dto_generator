# DTO Generator

A command-line tool to generate DTO classes from Swagger/OpenAPI definitions.

## Overview

DTO Generator is a Dart command-line application designed to help you quickly generate Data Transfer Object (DTO) classes from your Swagger/OpenAPI definitions. It reads your Swagger file (in YAML or JSON format), infers the data schemas, and produces corresponding Dart classes annotated with `@JsonSerializable` for seamless JSON serialization.

## Features

- **Automatic DTO Generation:** Generates Dart classes based on Swagger/OpenAPI definitions.
- **Multi-format Support:** Works with both JSON and YAML input files.
- **Intelligent Inlining:** Inlines small nested objects to simplify the generated code.
- **Naming Conventions:** Automatically converts names to CamelCase for classes and camelCase for fields.
- **Seamless JSON Integration:** Leverages `json_serializable` for effortless serialization and deserialization.

## Installation

Activate DTO Generator globally by running:
 
```bash
dart pub global activate dto_generator
