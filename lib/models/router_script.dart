class RouterScript {
  final String id;
  final String name;
  final String source;
  final String owner;
  final String lastStarted;
  final String runCount;

  RouterScript({
    required this.id,
    required this.name,
    required this.source,
    this.owner = 'admin',
    this.lastStarted = '',
    this.runCount = '0',
  });

  factory RouterScript.fromMap(Map<String, String> map) {
    return RouterScript(
      id: map['.id'] ?? '',
      name: map['name'] ?? '',
      source: map['source'] ?? '',
      owner: map['owner'] ?? 'admin',
      lastStarted: map['last-started'] ?? '',
      runCount: map['run-count'] ?? '0',
    );
  }
}
