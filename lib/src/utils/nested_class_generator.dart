import 'package:dto_generator/src/utils/string_utils.dart';
import 'package:dto_generator/src/utils/type_mapper.dart';

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
