class PosCategory {
  const PosCategory({
    required this.id,
    required this.name,
    required this.position,
    this.parentId,
    this.iconUrl,
    this.children = const <PosCategory>[],
  });

  final String id;
  final String name;
  final String? parentId;
  final String? iconUrl;
  final int position;
  final List<PosCategory> children;

  factory PosCategory.fromJson(Map<String, dynamic> json) => PosCategory(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        parentId: _nullable(json['parent_id']),
        iconUrl: _nullable(json['icon_url']),
        position: _integer(json['position']),
        children: (json['children'] as List? ?? const [])
            .whereType<Map>()
            .map(
                (item) => PosCategory.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
      );

  static List<PosCategory> buildTree(Iterable<PosCategory> flat) {
    final items = flat.toList(growable: false);
    final childrenByParent = <String?, List<PosCategory>>{};
    for (final item in items) {
      childrenByParent.putIfAbsent(item.parentId, () => []).add(item);
    }
    int compare(PosCategory a, PosCategory b) {
      final byPosition = a.position.compareTo(b.position);
      if (byPosition != 0) return byPosition;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    }

    PosCategory attach(PosCategory item, Set<String> ancestors) {
      if (ancestors.contains(item.id)) return item;
      final children = [...?childrenByParent[item.id]]..sort(compare);
      return PosCategory(
        id: item.id,
        name: item.name,
        parentId: item.parentId,
        iconUrl: item.iconUrl,
        position: item.position,
        children: children
            .map((child) => attach(child, {...ancestors, item.id}))
            .toList(growable: false),
      );
    }

    final roots = [...?childrenByParent[null]]..sort(compare);
    return roots.map((item) => attach(item, const {})).toList(growable: false);
  }

  static String? _nullable(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
