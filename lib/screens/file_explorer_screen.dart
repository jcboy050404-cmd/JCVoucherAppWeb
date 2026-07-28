import 'dart:io';
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

  String get _currentDirString {
    if (_currentPath.length == 1) return '';
    // e.g. ['/', 'hotspot'] -> 'hotspot/'
    // ['/', 'hotspot', 'img'] -> 'hotspot/img/'
    return _currentPath.sublist(1).join('/') + '/';
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
      try {
        await widget.service.deleteFile(file.id);
        TopToast.show(context, 'File deleted successfully', backgroundColor: const Color(0xFF00E676));
        await _loadFiles();
      } catch (e) {
        TopToast.show(context, 'Error deleting file: $e', backgroundColor: const Color(0xFFFF5252));
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
        allowedExtensions: ['html', 'txt', 'css', 'js', 'xml'],
      );

      if (result != null && result.files.single.path != null) {
        final File file = File(result.files.single.path!);
        final String contents = await file.readAsString();
        final String fileName = result.files.single.name;
        
        final String targetDir = _currentDirString;
        final String targetPath = targetDir.isEmpty ? fileName : '$targetDir$fileName';
        
        RouterFile? existingFile;
        try {
          existingFile = _allFiles.firstWhere((f) => f.name == targetPath);
        } catch (e) {
          existingFile = null;
        }
        
        if (existingFile == null) {
          if (!mounted) return;
          TopToast.show(context, 'Only overwriting existing files is supported. Please pick a file named exactly like an existing one.', backgroundColor: const Color(0xFFFF5252));
          return;
        }

        setState(() => _isLoading = true);
        
        await widget.service.setFileContents(existingFile.id, contents);
        if (!mounted) return;
        TopToast.show(context, 'File uploaded and overwritten successfully!', backgroundColor: const Color(0xFF00E676));
        await _loadFiles();
      }
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'Error uploading file: $e', backgroundColor: const Color(0xFFFF5252));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('File Explorer', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
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
                        child: Text(_error!, style: GoogleFonts.poppins(color: const Color(0xFFFF5252))),
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
