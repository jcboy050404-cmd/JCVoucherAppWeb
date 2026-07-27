import 'dart:io';
import 'dart:convert';

void main() {
  final f = File(r'C:\Users\jccel\.gemini\antigravity-ide\brain\c69fac16-2686-4642-8da9-7c306e87b9ed\.system_generated\logs\transcript_full.jsonl');
  final lines = f.readAsLinesSync();
  int count = 0;
  for (var l in lines) {
    if (l.contains('dashboard_screen.dart') && l.contains('multi_replace_file_content')) {
      final obj = jsonDecode(l);
      final content = obj['content'];
      if (content != null && content.contains('ReplacementChunks')) {
        print('=== MATCH ${count} ===');
        print(content);
      }
      count++;
    }
  }
}
