import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../services/voucher_pdf_service.dart';
import '../services/trial_service.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../models/voucher.dart';

/// Shows the full print preview bottom sheet (paper size picker, template
/// selector, live PDF preview, Download PDF and Print PDF buttons).
///
/// This is the same modal used in VoucherListScreen – call it from
/// any screen to get identical behaviour.
void showVoucherPrintPreview(
  BuildContext context,
  List<Voucher> vouchers,
) {
  VoucherPaperSize selectedPaper = VoucherPaperSize.a4;
  VoucherTemplate selectedTemplate = VoucherTemplate.standard;
  final hotspotCtrl =
      TextEditingController(text: 'JOEMIA WiFi Hotspot');
  final loginUrlCtrl =
      TextEditingController(text: 'http://10.10.10.1');
  final footerNoteCtrl =
      TextEditingController(text: 'ENJOY @ JOEMIA CAFE');
  
  bool isProUser = false;
  TrialService.isPro().then((pro) {
    isProUser = pro;
  });

  final customWidthCtrl = TextEditingController(text: '21.0');
  final customHeightCtrl = TextEditingController(text: '29.7');
  
  Uint8List? _logoBytes;
  
  final Map<Color, PdfColor> templateColors = {
    const Color(0xFF4CAF50): PdfColors.green,
    const Color(0xFF2196F3): PdfColors.blue,
    const Color(0xFFF44336): PdfColors.red,
    const Color(0xFFFF9800): PdfColors.orange,
    const Color(0xFF9C27B0): PdfColors.purple,
    const Color(0xFF000000): PdfColors.black,
  };
  Color selectedColor = const Color(0xFF4CAF50);
  
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setPreviewState) {
          void _openCustomizerModal() {
            showDialog(
              context: context,
              builder: (ctx) {
                return Dialog(
                  backgroundColor: const Color(0xFF121224),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: StatefulBuilder(
                    builder: (context, setDialogState) {
                      void updateStates(VoidCallback fn) {
                        setDialogState(fn);
                        setPreviewState(fn);
                      }
                      return SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Customize Receipt Text',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white54),
                                    onPressed: () => Navigator.pop(ctx),
                                  )
                                ],
                              ),
                              const SizedBox(height: 12),
                              _PreviewEditorField(
                                controller: hotspotCtrl,
                                label: 'Hotspot Name',
                                hint: 'JOEMIA WiFi Hotspot',
                                onChanged: (_) => updateStates(() {}),
                              ),
                              const SizedBox(height: 10),
                              _PreviewEditorField(
                                controller: loginUrlCtrl,
                                label: 'Login Portal URL',
                                hint: 'http://10.10.10.1',
                                onChanged: (_) => updateStates(() {}),
                              ),
                              const SizedBox(height: 10),
                              _PreviewEditorField(
                                controller: footerNoteCtrl,
                                label: 'Footer Slogan',
                                hint: 'ENJOY @ JOEMIA CAFE',
                                onChanged: (_) => updateStates(() {}),
                              ),
                              if (selectedTemplate == VoucherTemplate.premium) ...[
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.image, size: 16),
                                        label: Text(
                                          _logoBytes == null ? 'Upload Logo' : 'Change Logo',
                                          style: GoogleFonts.poppins(fontSize: 11),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                        ),
                                        onPressed: () async {
                                          final picker = ImagePicker();
                                          final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                                          if (pickedFile != null) {
                                            final bytes = await pickedFile.readAsBytes();
                                            updateStates(() {
                                              _logoBytes = bytes;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    if (_logoBytes != null) ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                        onPressed: () {
                                          updateStates(() {
                                            _logoBytes = null;
                                          });
                                        },
                                      )
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Accent Color',
                                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: templateColors.keys.map((color) {
                                    final isSelected = selectedColor == color;
                                    return GestureDetector(
                                      onTap: () {
                                        updateStates(() {
                                          selectedColor = color;
                                        });
                                      },
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                          border: isSelected
                                              ? Border.all(color: Colors.white, width: 2)
                                              : null,
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: color.withValues(alpha: 0.5),
                                                    blurRadius: 8,
                                                    spreadRadius: 2,
                                                  )
                                                ]
                                              : null,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ]
                          )
                        )
                      );
                    }
                  )
                );
              }
            );
          }
          return Container(
            height: MediaQuery.of(context).size.height * 0.94,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF121224),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: const Color(0xFF00BFFF).withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Print Preview (${vouchers.length})',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${selectedPaper.nameLabel} | Auto-adjusting tickets',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: const Color(0xFF00BFFF),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Paper Size Dropdown
                Text(
                  'Paper Size:',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<VoucherPaperSize>(
                      value: selectedPaper,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1A1A2E),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white54,
                      ),
                      items: VoucherPaperSize.values
                          .map(
                            (paper) => DropdownMenuItem(
                              value: paper,
                              child: Text(
                                paper.nameLabel,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (paper) {
                        if (paper != null) {
                          setPreviewState(() {
                            selectedPaper = paper;
                            if (selectedTemplate == VoucherTemplate.withInstructions && paper != VoucherPaperSize.thermal58) {
                              selectedTemplate = VoucherTemplate.standard;
                            }
                          });
                        }
                      },
                    ),
                  ),
                ),
                if (selectedPaper == VoucherPaperSize.custom) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _PreviewEditorField(
                          controller: customWidthCtrl,
                          label: 'Width (cm)',
                          hint: '21.0',
                          onChanged: (_) => setPreviewState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PreviewEditorField(
                          controller: customHeightCtrl,
                          label: 'Height (cm)',
                          hint: '29.7',
                          onChanged: (_) => setPreviewState(() {}),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),

                // Template Selection (only for thermal 58mm)
                // Template Selection
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Template Layout:',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                          if (selectedTemplate != VoucherTemplate.standard)
                            GestureDetector(
                              onTap: _openCustomizerModal,
                              child: Text(
                                '✏️ Customize Fields',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF00BFFF),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<VoucherTemplate>(
                            value: selectedTemplate,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1A1A2E),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
                            items: VoucherTemplate.values
                                .where((t) => t != VoucherTemplate.withInstructions || selectedPaper == VoucherPaperSize.thermal58)
                                .map(
                                  (template) => DropdownMenuItem(
                                    value: template,
                                    child: Text(
                                      template.displayName,
                                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (template) {
                              if (template != null) {
                                if (template == VoucherTemplate.premium && !isProUser) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Premium Split template is only available for Pro subscribers.',
                                        style: GoogleFonts.poppins(),
                                      ),
                                      backgroundColor: Colors.orange,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }
                                setPreviewState(() {
                                  selectedTemplate = template;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      
                      // Customizer has been moved to a separate popup modal
                      const SizedBox(height: 14),
                    ],
                  ),

                // Live PDF Preview
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: PdfPreview(
                      key: ValueKey((
                        selectedPaper,
                        selectedTemplate,
                        hotspotCtrl.text,
                        loginUrlCtrl.text,
                        footerNoteCtrl.text,
                        customWidthCtrl.text,
                        customHeightCtrl.text,
                        _logoBytes,
                        selectedColor.toARGB32(),
                      )),
                      build: (format) {
                        PdfPageFormat? customFormat;
                        if (selectedPaper == VoucherPaperSize.custom) {
                          final w = double.tryParse(customWidthCtrl.text) ?? 21.0;
                          final h = double.tryParse(customHeightCtrl.text) ?? 29.7;
                          customFormat = PdfPageFormat(w * PdfPageFormat.cm, h * PdfPageFormat.cm);
                        }
                        
                        return VoucherPdfService.buildPdf(
                          vouchers,
                          paperSize: selectedPaper,
                          template: selectedTemplate,
                          hotspotName: hotspotCtrl.text.isNotEmpty
                              ? hotspotCtrl.text
                              : 'JOEMIA WiFi Hotspot',
                          loginUrl: loginUrlCtrl.text.isNotEmpty
                              ? loginUrlCtrl.text
                              : 'http://10.10.10.1',
                          footerNote: footerNoteCtrl.text.isNotEmpty
                              ? footerNoteCtrl.text
                              : 'ENJOY @ JOEMIA CAFE',
                          customFormat: customFormat,
                          logoBytes: _logoBytes,
                          primaryColor: templateColors[selectedColor],
                        );
                      },
                      allowPrinting: false,
                      allowSharing: false,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                      pdfFileName:
                          'vouchers_${selectedPaper.shortLabel}_${vouchers.length}.pdf',
                      actions: const [],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Action buttons
                Row(
                  children: [
                    // Download PDF
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final messenger =
                              ScaffoldMessenger.of(context);
                          try {
                            PdfPageFormat? customFormat;
                            if (selectedPaper == VoucherPaperSize.custom) {
                              final w = double.tryParse(customWidthCtrl.text) ?? 21.0;
                              final h = double.tryParse(customHeightCtrl.text) ?? 29.7;
                              customFormat = PdfPageFormat(w * PdfPageFormat.cm, h * PdfPageFormat.cm);
                            }

                            final pdfBytes =
                                await VoucherPdfService.buildPdf(
                              vouchers,
                              paperSize: selectedPaper,
                              template: selectedTemplate,
                              hotspotName: hotspotCtrl.text,
                              loginUrl: loginUrlCtrl.text,
                              footerNote: footerNoteCtrl.text,
                              customFormat: customFormat,
                              logoBytes: _logoBytes,
                              primaryColor: templateColors[selectedColor],
                            );
                            await Printing.sharePdf(
                              bytes: pdfBytes,
                              filename:
                                  'vouchers_${selectedPaper.shortLabel}_${vouchers.length}.pdf',
                            );
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('PDF download failed: $e',
                                    style: GoogleFonts.poppins()),
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.file_download_rounded,
                            size: 18),
                        label: Text(
                          'Download PDF',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF6B35),
                          side: const BorderSide(
                              color: Color(0xFFFF6B35), width: 1.5),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Print PDF
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final messenger =
                              ScaffoldMessenger.of(context);
                          try {
                            PdfPageFormat? customFormat;
                            if (selectedPaper == VoucherPaperSize.custom) {
                              final w = double.tryParse(customWidthCtrl.text) ?? 21.0;
                              final h = double.tryParse(customHeightCtrl.text) ?? 29.7;
                              customFormat = PdfPageFormat(w * PdfPageFormat.cm, h * PdfPageFormat.cm);
                            }

                            await Printing.layoutPdf(
                              onLayout: (_) =>
                                  VoucherPdfService.buildPdf(
                                vouchers,
                                paperSize: selectedPaper,
                                template: selectedTemplate,
                                hotspotName: hotspotCtrl.text,
                                loginUrl: loginUrlCtrl.text,
                                footerNote: footerNoteCtrl.text,
                                customFormat: customFormat,
                                logoBytes: _logoBytes,
                                primaryColor: templateColors[selectedColor],
                              ),
                              name:
                                  'vouchers_${selectedPaper.shortLabel}_${vouchers.length}',
                            );
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Print failed: $e',
                                    style: GoogleFonts.poppins()),
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon:
                            const Icon(Icons.print_rounded, size: 18),
                        label: Text(
                          'Print PDF',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00BFFF),
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

// Private helpers

class _PreviewEditorField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;

  const _PreviewEditorField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: Colors.white60,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 34,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  GoogleFonts.poppins(fontSize: 12, color: Colors.white30),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: Color(0xFF00BFFF), width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
