import 'dart:io';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../services/mikrotik_service.dart';
import '../models/router_file.dart';
import '../widgets/top_toast.dart';

class MikrotikFileExplorerScreen extends StatefulWidget {
  final MikrotikService service;

  const MikrotikFileExplorerScreen({super.key, required this.service});

  @override
  State<MikrotikFileExplorerScreen> createState() => _MikrotikFileExplorerScreenState();
}

class _MikrotikFileExplorerScreenState extends State<MikrotikFileExplorerScreen> {
  bool _isLoading = true;
  String? _error;
  List<RouterFile> _allFiles = [];
  
  // Breadcrumb navigation
  List<String> _currentPath = ['/'];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final files = await widget.service.getFiles();
      if (!mounted) return;
      setState(() {
        _allFiles = files;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // Extensions treated as TEXT — uploaded via UTF-8 string API.
  static const _textExtensions = {
    '.html', '.htm', '.css', '.js', '.xml',
    '.rsc', '.txt', '.json', '.svg',
  };

  static bool _isTextFile(String filename) {
    final lower = filename.toLowerCase();
    return _textExtensions.any((ext) => lower.endsWith(ext));
  }

  // Binary extensions we support uploading via raw-byte API.
  static const _binaryExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.ico',
    '.woff', '.woff2', '.ttf', '.otf', '.eot',
    '.swf', '.mp3', '.ogg', '.wav',
  };

  static bool _isBinaryFile(String filename) {
    final lower = filename.toLowerCase();
    return _binaryExtensions.any((ext) => lower.endsWith(ext));
  }


  String get _currentDirString {
    if (_currentPath.length == 1) return '';
    // e.g. ['/', 'hotspot'] -> 'hotspot/'
    // ['/', 'hotspot', 'img'] -> 'hotspot/img/'
    return '${_currentPath.sublist(1).join('/')}/';
  }

  List<RouterFile> get _currentFiles {
    final dir = _currentDirString;
    final List<RouterFile> filtered = [];

    for (final f in _allFiles) {
      // Find files that start with the current directory
      if (f.name.startsWith(dir) && f.name != dir) {
        // Only include files/folders at this exact depth
        final remaining = f.name.substring(dir.length);
        if (!remaining.contains('/') || (remaining.endsWith('/') && remaining.indexOf('/') == remaining.length - 1)) {
          filtered.add(f);
        }
      }
    }

    // Sort: Folders first, then alphabetically
    filtered.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.compareTo(b.name);
    });

    return filtered;
  }

  void _navigateTo(String folderName) {
    setState(() {
      _currentPath.add(folderName.replaceAll('/', ''));
    });
  }

  void _navigateUp(int index) {
    setState(() {
      _currentPath = _currentPath.sublist(0, index + 1);
    });
  }

  Future<void> _deleteFile(RouterFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: Text('Delete File', style: GoogleFonts.poppins(color: Colors.white)),
        content: Text('Are you sure you want to delete ${file.name}?', style: GoogleFonts.poppins(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.poppins(color: const Color(0xFFFF5252), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      if (!mounted) return;
      final ctx = context;
      try {
        await widget.service.deleteFile(file.id);
        if (!ctx.mounted) return;
        TopToast.show(ctx, 'File deleted successfully', backgroundColor: const Color(0xFF00E676));
        await _loadFiles();
      } catch (e) {
        if (!ctx.mounted) return;
        TopToast.show(ctx, 'Error deleting file: $e', backgroundColor: const Color(0xFFFF5252));
        setState(() => _isLoading = false);
      }
    }
  }

  void _openFile(RouterFile file) {
    if (file.isDirectory) {
      // Just extract the folder name
      final parts = file.name.split('/');
      final folderName = parts.last.isEmpty ? parts[parts.length - 2] : parts.last;
      _navigateTo(folderName);
    } else if (file.isTextFile) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileEditorScreen(service: widget.service, file: file),
        ),
      ).then((_) => _loadFiles());
    } else {
      TopToast.show(context, 'This file type cannot be opened', backgroundColor: const Color(0xFFFBC02D));
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size > 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }
  Future<void> _uploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'html', 'htm', 'txt', 'css', 'js', 'xml', 'rsc', 'json', 'svg',
          'png', 'jpg', 'jpeg', 'gif', 'ico',
          'woff', 'woff2', 'ttf', 'otf', 'eot',
        ],
      );

      if (result != null && result.files.single.path != null) {
        final String filePath = result.files.single.path!;
        final String fileName = result.files.single.name;
        final String targetDir = _currentDirString;
        final String targetPath = targetDir.isEmpty ? fileName : '$targetDir$fileName';

        // Check if file already exists on router
        RouterFile? existingFile;
        for (final f in _allFiles) {
          if (f.name == targetPath) { existingFile = f; break; }
        }

        setState(() => _isLoading = true);
        final isBinary = _isBinaryFile(fileName);

        if (existingFile != null) {
          if (isBinary) {
            final bytes = await File(filePath).readAsBytes();
            await widget.service.setFileBinaryContents(existingFile.id, bytes);
          } else {
            final contents = await File(filePath).readAsString();
            await widget.service.setFileContents(existingFile.id, contents);
          }
          if (!mounted) return;
          TopToast.show(context, 'File overwritten successfully!',
              backgroundColor: const Color(0xFF00E676));
        } else {
          if (isBinary) {
            final bytes = await File(filePath).readAsBytes();
            await widget.service.createBinaryFile(targetPath, bytes);
          } else {
            final contents = await File(filePath).readAsString();
            await widget.service.createFile(targetPath, contents);
          }
          if (!mounted) return;
          TopToast.show(context, 'File uploaded successfully!',
              backgroundColor: const Color(0xFF00E676));
        }
        await _loadFiles();
      }
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'Error uploading file: $e',
          backgroundColor: const Color(0xFFFF5252));
      setState(() => _isLoading = false);
    }
  }

  /// Replaces ALL files in the current folder with the contents of a ZIP archive.
  Future<void> _replaceFolder() async {
    if (_currentPath.length < 2) return; // Only inside a subfolder

    // 1. Pick a ZIP file
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'Could not open file picker: $e',
          backgroundColor: const Color(0xFFFF5252));
      return;
    }
    if (result == null || result.files.single.bytes == null) return;

    // 2. Decode the ZIP in memory
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(result.files.single.bytes!);
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'Invalid ZIP file: $e',
          backgroundColor: const Color(0xFFFF5252));
      return;
    }

    // 3. Determine prefix to strip from ZIP paths.
    //    If the ZIP has a single top-level folder matching the current folder
    //    name, strip it so files land directly in _currentDirString.
    final currentFolderName = _currentPath.last; // e.g. 'hotspot'
    final topLevelFolders = archive.files
        .where((f) => !f.isFile)
        .map((f) => f.name.split('/').first)
        .toSet();
    final String stripPrefix =
        (topLevelFolders.length == 1 &&
                topLevelFolders.first == currentFolderName)
            ? '$currentFolderName/'
            : '';

    // 4. Collect ALL uploadable files from ZIP (text + binary)
    final toUpload = <({String routerPath, List<int> bytes, bool isBinary})>[];
    int skipped = 0;
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      String relPath = entry.name;
      if (stripPrefix.isNotEmpty && relPath.startsWith(stripPrefix)) {
        relPath = relPath.substring(stripPrefix.length);
      }
      if (relPath.isEmpty) continue;
      final routerPath = '$_currentDirString$relPath';
      final bytes = entry.content as List<int>;
      if (_isTextFile(relPath)) {
        toUpload.add((routerPath: routerPath, bytes: bytes, isBinary: false));
      } else if (_isBinaryFile(relPath)) {
        toUpload.add((routerPath: routerPath, bytes: bytes, isBinary: true));
      } else {
        skipped++; // Unknown extension — skip
      }
    }

    if (toUpload.isEmpty) {
      if (!context.mounted) return;
      TopToast.show(context, 'No uploadable files found in ZIP.',
          backgroundColor: const Color(0xFFFF9800));
      return;
    }

    // 5. Confirm dialog
    final existingCount =
        _allFiles.where((f) => f.name.startsWith(_currentDirString)).length;
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.folder_zip_rounded,
                color: Color(0xFFFF9800), size: 24),
            const SizedBox(width: 10),
            Text('Replace Folder',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _confirmRow(Icons.delete_outline_rounded, const Color(0xFFFF5252),
                'Delete $existingCount existing file(s) in $_currentDirString'),
            const SizedBox(height: 8),
            _confirmRow(Icons.upload_rounded, const Color(0xFF00E676),
                'Upload ${toUpload.length} file(s) from ZIP'),
            if (skipped > 0) ...[
              const SizedBox(height: 8),
              _confirmRow(Icons.warning_amber_rounded, const Color(0xFFFF9800),
                  'Skip $skipped file(s) with unknown extension'),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5252),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: Text('Replace',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // 6. Show progress dialog and execute
    final progress = ValueNotifier<(int, int, String)>((0, toUpload.length, ''));
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Replacing Folder…',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          content: ValueListenableBuilder<(int, int, String)>(
            valueListenable: progress,
            builder: (_, val, _) {
              final done = val.$1;
              final total = val.$2;
              final label = val.$3;
              final pct = total > 0 ? done / total : 0.0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: done == 0 && label.isEmpty ? null : pct,
                    backgroundColor: Colors.white12,
                    color: const Color(0xFF00BFFF),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label.isEmpty
                        ? 'Clearing old files…'
                        : '$done / $total — $label',
                    style: GoogleFonts.poppins(
                        color: Colors.white70, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    String? errorMsg;
    try {
      // Step A: Delete existing files in the folder
      if (_currentDirString.isNotEmpty) {
        await widget.service.deleteFilesInDirectory(_currentDirString);
      }

      // Step B: Upload each file (text or binary)
      for (int i = 0; i < toUpload.length; i++) {
        final item = toUpload[i];
        final shortName = item.routerPath.split('/').last;
        progress.value = (i + 1, toUpload.length, shortName);
        if (item.isBinary) {
          await widget.service.createBinaryFile(item.routerPath, item.bytes);
        } else {
          final content = utf8.decode(item.bytes);
          await widget.service.createFile(item.routerPath, content);
        }
      }
    } catch (e) {
      errorMsg = e.toString();
    }

    progress.dispose();
    if (!mounted) return;
    Navigator.of(context).pop(); // Close progress dialog

    if (errorMsg != null) {
      TopToast.show(context, 'Error: $errorMsg',
          backgroundColor: const Color(0xFFFF5252));
    } else {
      final skippedMsg = skipped > 0 ? ' ($skipped unknown files skipped)' : '';
      TopToast.show(
          context,
          '✅ Replaced ${toUpload.length} files successfully!$skippedMsg',
          backgroundColor: const Color(0xFF00E676));
    }
    await _loadFiles();
  }

  Widget _confirmRow(IconData icon, Color color, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style:
                  GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final insideFolder = _currentPath.length > 1;
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('File Explorer',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          if (insideFolder)
            Tooltip(
              message: 'Replace all files in this folder with a ZIP',
              child: IconButton(
                icon: const Icon(Icons.folder_zip_rounded,
                    color: Color(0xFFFF9800)),
                onPressed: _replaceFolder,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00BFFF)),
            onPressed: _loadFiles,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadFile,
        backgroundColor: const Color(0xFF00BFFF),
        icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
        label: Text('Upload', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _buildBreadcrumbs(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00BFFF)))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_rounded, size: 56, color: Color(0xFFFF5252)),
                              const SizedBox(height: 16),
                              Text('Could not load files',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              Container(
                                constraints: const BoxConstraints(maxHeight: 140),
                                child: SingleChildScrollView(
                                  child: Text(_error ?? '',
                                      style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
                                      textAlign: TextAlign.center),
                                ),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: _loadFiles,
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: Text('Retry', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00BFFF),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _currentFiles.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.folder_open_rounded, size: 80, color: Colors.white24),
                                const SizedBox(height: 16),
                                Text('Folder is empty', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 16)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _currentFiles.length,
                            itemBuilder: (ctx, i) {
                              final f = _currentFiles[i];
                              return _buildFileTile(f);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF18182A),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _currentPath.asMap().entries.map((entry) {
            final idx = entry.key;
            final pathPart = entry.value;
            final isLast = idx == _currentPath.length - 1;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: isLast ? null : () => _navigateUp(idx),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      pathPart,
                      style: GoogleFonts.poppins(
                        color: isLast ? Colors.white : const Color(0xFF00BFFF),
                        fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                if (!isLast) const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 18),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFileTile(RouterFile file) {
    final iconData = file.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_rounded;
    final iconColor = file.isDirectory ? const Color(0xFFFBC02D) : const Color(0xFF00BFFF);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF18182A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(iconData, color: iconColor),
        ),
        title: Text(
          file.name.split('/').lastWhere((s) => s.isNotEmpty),
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: file.isDirectory
            ? null
            : Text(
                '${_formatBytes(file.size)}  •  ${file.creationTime}',
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
              ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5252)),
          onPressed: () => _deleteFile(file),
        ),
        onTap: () => _openFile(file),
      ),
    );
  }
}

class FileEditorScreen extends StatefulWidget {
  final MikrotikService service;
  final RouterFile file;

  const FileEditorScreen({super.key, required this.service, required this.file});

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _loadFileContents();
  }

  Future<void> _loadFileContents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final contents = await widget.service.getFileContents(widget.file.id);
      if (!mounted) return;
      setState(() {
        _ctrl.text = contents;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveFile() async {
    setState(() => _isSaving = true);
    try {
      await widget.service.setFileContents(widget.file.id, _ctrl.text);
      if (!mounted) return;
      TopToast.show(context, 'File saved successfully', backgroundColor: const Color(0xFF00E676));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'Error saving file: $e', backgroundColor: const Color(0xFFFF5252));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.file.name.split('/').lastWhere((s) => s.isNotEmpty);
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(fileName, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          if (!_isLoading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: _isSaving
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00BFFF)))
                  : IconButton(
                      icon: const Icon(Icons.save_rounded, color: Color(0xFF00E676)),
                      onPressed: _saveFile,
                    ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00BFFF)))
          : _error != null
              ? Center(
                  child: Text(_error!, style: GoogleFonts.poppins(color: const Color(0xFFFF5252))),
                )
              : Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18182A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'File is empty.',
                      hintStyle: TextStyle(color: Colors.white24),
                    ),
                  ),
                ),
    );
  }
}
