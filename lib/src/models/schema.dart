/// Represents a property in a DTO schema
class DtoProperty {
  final String name;
  final String type;
  final bool isRequired;
  final String? format;
  final Map<String, dynamic>? items;
  final Map<String, dynamic>? properties;

  DtoProperty({
    required this.name,
    required this.type,
    required this.isRequired,
    this.format,
    this.items,
    this.properties,
  });

  factory DtoProperty.fromJson(
      String name, Map<String, dynamic> json, List<String> required) {
    return DtoProperty(
      name: name,
      type: json['type'] as String? ?? 'object',
      isRequired: required.contains(name),
      format: json['format'] as String?,
      items: json['items'] as Map<String, dynamic>?,
      properties: json['properties'] as Map<String, dynamic>?,
    );
  }
}

/// Represents a DTO schema
class DtoSchema {
  final String name;
  final List<DtoProperty> properties;
  final List<String> required;

  DtoSchema({
    required this.name,
    required this.properties,
    required this.required,
  });

  factory DtoSchema.fromJson(String name, Map<String, dynamic> json) {
    final required = (json['required'] as List?)?.cast<String>() ?? [];
    final properties = <DtoProperty>[];

    if (json['properties'] != null) {
      final Map<String, dynamic> props = json['properties'];
      props.forEach((key, value) {
        properties.add(
            DtoProperty.fromJson(key, value as Map<String, dynamic>, required));
      });
    }

    return DtoSchema(
      name: name,
      properties: properties,
      required: required,
    );
  }
}
