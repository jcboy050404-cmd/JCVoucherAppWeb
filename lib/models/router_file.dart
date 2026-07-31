class RouterFile {
  final String id;
  final String name;
  final String type;
  final int size;
  final String creationTime;
  final String contents;

  RouterFile({
    required this.id,
    required this.name,
    required this.type,
    required this.size,
    required this.creationTime,
    this.contents = '',
  });

  factory RouterFile.fromMap(Map<String, String> map) {
    return RouterFile(
      id: map['.id'] ?? '',
      name: map['name'] ?? 'unknown',
      type: map['type'] ?? 'unknown',
      size: int.tryParse(map['size'] ?? '0') ?? 0,
      creationTime: map['creation-time'] ?? '',
      contents: map['contents'] ?? '',
    );
  }

  /// A folder is anything RouterOS reports as 'directory' OR 'disk' (the
  /// `flash/` partition and other disk mounts come back as type 'disk'), or any
  /// entry whose name ends with '/' (RouterOS marks folders that way). Matching
  /// all three ensures drives like `flash` aren't mis-shown as plain files.
  bool get isDirectory =>
      type.toLowerCase() == 'directory' ||
      type.toLowerCase() == 'disk' ||
      name.endsWith('/');
  bool get isTextFile =>
      name.endsWith('.html') ||
      name.endsWith('.txt') ||
      name.endsWith('.css') ||
      name.endsWith('.js') ||
      name.endsWith('.xml') ||
      name.endsWith('.rsc');
}
