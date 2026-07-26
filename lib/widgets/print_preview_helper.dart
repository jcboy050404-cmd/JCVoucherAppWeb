import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import '../services/voucher_pdf_service.dart';
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
  bool showCustomizer = false;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setPreviewState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.88,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                const SizedBox(height: 16),

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
                const SizedBox(height: 12),

                // Paper Size Dropdown
                Text(
                  'Paper Size:',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
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
                          setPreviewState(() => selectedPaper = paper);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Template Selection (only for thermal 58mm)
                if (selectedPaper == VoucherPaperSize.thermal58) ...[
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
                          if (selectedTemplate ==
                              VoucherTemplate.withInstructions)
                            GestureDetector(
                              onTap: () {
                                setPreviewState(() =>
                                    showCustomizer = !showCustomizer);
                              },
                              child: Text(
                                showCustomizer
                                    ? 'Hide Editor'
                                    : '✏️ Customize Fields',
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
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setPreviewState(() => selectedTemplate =
                                    VoucherTemplate.standard);
                              },
                              child: _TemplateChip(
                                label: 'Standard',
                                selected: selectedTemplate ==
                                    VoucherTemplate.standard,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setPreviewState(() {
                                  selectedTemplate =
                                      VoucherTemplate.withInstructions;
                                  showCustomizer = true;
                                });
                              },
                              child: _TemplateChip(
                                label: 'HTML Guide Receipt',
                                selected: selectedTemplate ==
                                    VoucherTemplate.withInstructions,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Inline Customizer
                      if (selectedTemplate ==
                              VoucherTemplate.withInstructions &&
                          showCustomizer) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0A14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Customize Receipt Text',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF00BFFF),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _PreviewEditorField(
                                controller: hotspotCtrl,
                                label: 'Hotspot Name',
                                hint: 'JOEMIA WiFi Hotspot',
                                onChanged: (_) =>
                                    setPreviewState(() {}),
                              ),
                              const SizedBox(height: 6),
                              _PreviewEditorField(
                                controller: loginUrlCtrl,
                                label: 'Login Portal URL',
                                hint: 'http://10.10.10.1',
                                onChanged: (_) =>
                                    setPreviewState(() {}),
                              ),
                              const SizedBox(height: 6),
                              _PreviewEditorField(
                                controller: footerNoteCtrl,
                                label: 'Footer Slogan',
                                hint: 'ENJOY @ JOEMIA CAFE',
                                onChanged: (_) =>
                                    setPreviewState(() {}),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                    ],
                  ),
                ],

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
                      )),
                      build: (_) => VoucherPdfService.buildPdf(
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
                      ),
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
                            final pdfBytes =
                                await VoucherPdfService.buildPdf(
                              vouchers,
                              paperSize: selectedPaper,
                              template: selectedTemplate,
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
                            await Printing.layoutPdf(
                              onLayout: (_) =>
                                  VoucherPdfService.buildPdf(
                                vouchers,
                                paperSize: selectedPaper,
                                template: selectedTemplate,
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

class _TemplateChip extends StatelessWidget {
  final String label;
  final bool selected;
  const _TemplateChip({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF00BFFF)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? const Color(0xFF00BFFF)
              : Colors.white.withValues(alpha: 0.1),
          width: 1.5,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.black : Colors.white70,
        ),
      ),
    );
  }
}

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
