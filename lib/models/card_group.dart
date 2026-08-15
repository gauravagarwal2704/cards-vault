class CardGroup {
  final String id;
  final String name;
  final int? colorValue;
  final DateTime createdAt;

  const CardGroup({
    required this.id,
    required this.name,
    this.colorValue,
    required this.createdAt,
  });

  CardGroup copyWith({
    String? name,
    int? colorValue,
    bool clearColor = false,
  }) {
    return CardGroup(
      id: id,
      name: name ?? this.name,
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'colorValue': colorValue,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CardGroup.fromJson(Map<String, dynamic> json) {
    return CardGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      colorValue: json['colorValue'] as int?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  @override
  String toString() => 'CardGroup(id: $id, name: $name)';
}
