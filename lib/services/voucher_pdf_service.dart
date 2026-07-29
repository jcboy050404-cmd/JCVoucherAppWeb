import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/voucher.dart';

/// Paper size options supported for voucher printing.
enum VoucherPaperSize {
  a4,
  letter,
  longBond,
  legal,
  thermal58,
  thermal80,
  custom, // Custom dimensions
}

extension VoucherPaperSizeExt on VoucherPaperSize {
  String get nameLabel {
    switch (this) {
      case VoucherPaperSize.a4:
        return 'A4 (21.0 × 29.7 cm)';
      case VoucherPaperSize.letter:
        return 'Letter (21.59 × 27.94 cm)';
      case VoucherPaperSize.longBond:
        return 'Long Bond (21.59 × 33.0 cm)';
      case VoucherPaperSize.legal:
        return 'Legal (21.59 × 35.56 cm)';
      case VoucherPaperSize.thermal58:
        return 'Thermal 58mm Roll (Receipt Printer)';
      case VoucherPaperSize.thermal80:
        return 'Thermal 80mm Roll (Receipt Printer)';
      case VoucherPaperSize.custom:
        return 'Custom Paper Size';
    }
  }

  String get shortLabel {
    switch (this) {
      case VoucherPaperSize.a4:
        return 'A4';
      case VoucherPaperSize.letter:
        return 'Letter';
      case VoucherPaperSize.longBond:
        return 'Long (33cm)';
      case VoucherPaperSize.legal:
        return 'Legal (35.6cm)';
      case VoucherPaperSize.thermal58:
        return '58mm Roll';
      case VoucherPaperSize.thermal80:
        return '80mm Roll';
      case VoucherPaperSize.custom:
        return 'Custom';
    }
  }

  PdfPageFormat get pdfFormat {
    switch (this) {
      case VoucherPaperSize.a4:
        return PdfPageFormat.a4;
      case VoucherPaperSize.letter:
        return PdfPageFormat.letter;
      case VoucherPaperSize.longBond:
        return const PdfPageFormat(612.0, 936.0);
      case VoucherPaperSize.legal:
        return PdfPageFormat.legal;
      case VoucherPaperSize.thermal58:
        return const PdfPageFormat(164.4, 300.0);
      case VoucherPaperSize.thermal80:
        return const PdfPageFormat(226.7, 350.0);
      case VoucherPaperSize.custom:
        return PdfPageFormat.a4; // Fallback
    }
  }

  bool get isThermal =>
      this == VoucherPaperSize.thermal58 || this == VoucherPaperSize.thermal80;
}

/// Template style options for voucher printing.
enum VoucherTemplate {
  standard, // Original design
  withInstructions, // With WiFi connection instructions (thermal 58mm)
  custom, // Custom template design
  modern, // Modern distinct layout
  minimal, // Minimal clean layout
  classic, // Classic bordered layout
  premium, // Premium Split layout
}

extension VoucherTemplateExt on VoucherTemplate {
  String get displayName {
    switch (this) {
      case VoucherTemplate.standard: return 'Standard';
      case VoucherTemplate.withInstructions: return 'HTML Guide Receipt';
      case VoucherTemplate.custom: return 'Custom Design';
      case VoucherTemplate.modern: return 'Modern Design';
      case VoucherTemplate.minimal: return 'Minimalist';
      case VoucherTemplate.classic: return 'Classic Bordered';
      case VoucherTemplate.premium: return 'Premium Split';
    }
  }
}

/// Generates printable PDF voucher tickets automatically scaled to paper size.
/// Uses built-in Helvetica fonts (no internet required).
class VoucherPdfService {
  /// Returns PDF bytes scaled to the specified paper size.
  static Future<Uint8List> buildPdf(
    List<Voucher> vouchers, {
    VoucherPaperSize paperSize = VoucherPaperSize.a4,
    VoucherTemplate template = VoucherTemplate.standard,
    String hotspotName = 'JOEMIA WiFi Hotspot',
    String loginUrl = 'http://10.10.10.1',
    String footerNote = 'ENJOY @ JOEMIA CAFE',
    PdfPageFormat? customFormat,
    Uint8List? logoBytes,
    PdfColor? primaryColor,
  }) async {
    final pdf = pw.Document();
    final isThermal = paperSize.isThermal;
    final baseFont = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();

    // Use new custom template
    if (template == VoucherTemplate.custom) {
      return _buildCustomTemplatePdf(
        vouchers,
        baseFont,
        boldFont,
        paperSize,
        hotspotName: hotspotName,
        loginUrl: loginUrl,
        footerNote: footerNote,
        customFormat: customFormat,
      );
    }

    // Use new modern template
    if (template == VoucherTemplate.modern) {
      return _buildModernTemplatePdf(
        vouchers,
        baseFont,
        boldFont,
        paperSize,
        hotspotName: hotspotName,
        customFormat: customFormat,
      );
    }

    // Use new minimal template
    if (template == VoucherTemplate.minimal) {
      return _buildMinimalTemplatePdf(
        vouchers,
        baseFont,
        boldFont,
        paperSize,
        hotspotName: hotspotName,
        customFormat: customFormat,
      );
    }

    // Use new classic template
    if (template == VoucherTemplate.classic) {
      return _buildClassicTemplatePdf(
        vouchers,
        baseFont,
        boldFont,
        paperSize,
        hotspotName: hotspotName,
        customFormat: customFormat,
      );
    }

    // Use premium split template
    if (template == VoucherTemplate.premium) {
      return _buildPremiumTemplatePdf(
        vouchers,
        baseFont,
        boldFont,
        paperSize,
        hotspotName: hotspotName,
        loginUrl: loginUrl,
        footerNote: footerNote,
        customFormat: customFormat,
        logoBytes: logoBytes,
        primaryColor: primaryColor ?? PdfColors.green,
      );
    }

    // Use custom template for thermal 58mm with instructions
    if (paperSize == VoucherPaperSize.thermal58 &&
        template == VoucherTemplate.withInstructions) {
      return _buildThermalWithInstructionsPdf(
        vouchers,
        baseFont,
        boldFont,
        hotspotName: hotspotName,
        loginUrl: loginUrl,
        footerNote: footerNote,
      );
    }

    if (isThermal) {
      // ── THERMAL RECEIPT ROLL LAYOUT (58mm / 80mm) ──────────────────────────
      final double rollWidth =
          paperSize == VoucherPaperSize.thermal58 ? 164.4 : 226.7;
      final double horizontalMargin =
          paperSize == VoucherPaperSize.thermal58 ? 4.0 : 6.0;
      final double usableWidth = rollWidth - (horizontalMargin * 2);
      const double ticketH = 118.0;
      const double spacing = 6.0;

      final double totalRollHeight =
          (ticketH + spacing) * vouchers.length + 16.0;
      final pageFormat = PdfPageFormat(rollWidth, totalRollHeight);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.symmetric(
            horizontal: horizontalMargin,
            vertical: 6.0,
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < vouchers.length; i++) ...[
                  _buildThermalTicket(
                    voucher: vouchers[i],
                    index: i + 1,
                    usableWidth: usableWidth,
                    baseFont: baseFont,
                    boldFont: boldFont,
                    paperSize: paperSize,
                  ),
                  if (i < vouchers.length - 1) pw.SizedBox(height: spacing),
                ],
              ],
            );
          },
        ),
      );
    } else {
      // ── STANDARD SHEET PAPER LAYOUT (A4, Letter, Long, Legal) ─────────────
      var format = (paperSize == VoucherPaperSize.custom && customFormat != null) ? customFormat : paperSize.pdfFormat;
      const int cols = 4;
      const double cellH = 68.0;
      const double headerHeight = 16.0;
      const double headerSpacing = 4.0;
      const double colSpacing = 3.0;
      const double rowSpacing = 3.0;

      final double usableWidth = format.width - 24; // 12pt margins
      final double usableHeight = format.height - 24;

      final double cellW = (usableWidth - (cols - 1) * colSpacing) / cols;

      final double gridUsableH = usableHeight - headerHeight - headerSpacing;
      final int rows =
          ((gridUsableH + rowSpacing) / (cellH + rowSpacing)).floor().clamp(1, 30);
      final int perPage = cols * rows;
      final int totalPages = (vouchers.length / perPage).ceil().clamp(1, 9999);

      for (int p = 0; p < totalPages; p++) {
        final slice = vouchers.skip(p * perPage).take(perPage).toList();

        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(12),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Page header
                  pw.Container(
                    height: headerHeight,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Wi-Fi Voucher Tickets',
                          style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 8.5,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.Text(
                          '${paperSize.shortLabel} | Page ${p + 1} / $totalPages ($perPage/page)',
                          style: pw.TextStyle(
                            font: baseFont,
                            fontSize: 7.5,
                            color: PdfColors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: headerSpacing),

                  // Ticket grid
                  for (int r = 0; r < slice.length; r += cols) ...[
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        for (int c = 0; c < cols; c++) ...[
                          if (r + c < slice.length)
                            _buildSheetTicketCell(
                              idx: r + c,
                              slice: slice,
                              overallIndex: (p * perPage) + r + c + 1,
                              cellW: cellW,
                              cellH: cellH,
                              baseFont: baseFont,
                              boldFont: boldFont,
                            )
                          else
                            pw.SizedBox(width: cellW, height: cellH),
                          if (c < cols - 1) pw.SizedBox(width: colSpacing),
                        ],
                      ],
                    ),
                    if (r + cols < slice.length)
                      pw.SizedBox(height: rowSpacing),
                  ],
                ],
              );
            },
          ),
        );
      }
    }

    return pdf.save();
  }

  // ── Single Thermal Ticket (Standard Layout) ────────────────────────────────

  static pw.Widget _buildThermalTicket({
    required Voucher voucher,
    required int index,
    required double usableWidth,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required VoucherPaperSize paperSize,
  }) {
    final bool is58 = paperSize == VoucherPaperSize.thermal58;

    final String priceStr =
        voucher.price > 0 ? 'P${voucher.price.toStringAsFixed(0)}' : 'Free';
    final String uptimeStr =
        voucher.limitUptime.isNotEmpty ? voucher.limitUptime : '--';

    String validUntil = '--';
    final valMatch = RegExp(r'val:(\d+)([dh])').firstMatch(voucher.comment);
    final expMatch = RegExp(r'exp:(\S+)').firstMatch(voucher.comment);
    final vuMatch = RegExp(r'ValidUntil:(\S+)').firstMatch(voucher.comment);

    if (expMatch != null) {
      validUntil = expMatch.group(1)!;
    } else if (valMatch != null) {
      final numStr = valMatch.group(1)!;
      final unit = valMatch.group(2) == 'd' ? 'Days' : 'Hours';
      validUntil = '$numStr $unit';
    } else if (vuMatch != null) {
      validUntil = vuMatch.group(1)!;
    } else if (voucher.createdDate != null) {
      final d = voucher.createdDate!;
      validUntil =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    final double titleFontSize = is58 ? 10.5 : 12.0;
    final double fieldLabelSize = is58 ? 9.0 : 10.0;
    final double fieldValueSize = is58 ? 10.5 : 12.0;
    final double codeFontSize = is58 ? 11.5 : 13.5;
    
    final String genDate = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';

    return pw.Container(
      width: usableWidth,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.0),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          // Header band
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Wi-Fi VOUCHER',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: titleFontSize,
                    color: PdfColors.black,
                  ),
                ),
                pw.Text(
                  '#$index',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: titleFontSize - 1,
                    color: PdfColors.black,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 5),

          // User Login / Code
          _thermalRow(
              (voucher.password.isNotEmpty) ? 'User Login:' : 'Voucher Code:', 
              voucher.name.toUpperCase(),
              labelSize: fieldLabelSize,
              valueSize: codeFontSize,
              baseFont: baseFont,
              boldFont: boldFont,
              isCode: true),

          // Password (only if it exists and differs from username)
          if (voucher.password.isNotEmpty && voucher.password != voucher.name)
            _thermalRow(
                'Password :', voucher.password,
                labelSize: fieldLabelSize,
                valueSize: codeFontSize,
                baseFont: baseFont,
                boldFont: boldFont,
                isCode: true),

          pw.SizedBox(height: 3),
          pw.Container(height: 0.5, color: PdfColors.black),
          pw.SizedBox(height: 3),

          // Time Limit
          _thermalRow('Time Limit :', uptimeStr,
              labelSize: fieldLabelSize,
              valueSize: fieldValueSize,
              baseFont: baseFont,
              boldFont: boldFont),

          if (voucher.customerName.isNotEmpty)
            _thermalRow('Customer   :', voucher.customerName,
                labelSize: fieldLabelSize,
                valueSize: fieldValueSize,
                baseFont: baseFont,
                boldFont: boldFont),

          // Price
          _thermalRow('Price      :', priceStr,
              labelSize: fieldLabelSize,
              valueSize: fieldValueSize,
              baseFont: baseFont,
              boldFont: boldFont),

          _thermalRow('Valid Until:', validUntil,
              labelSize: fieldLabelSize - 0.5,
              valueSize: fieldValueSize - 0.5,
              baseFont: baseFont,
              boldFont: boldFont),
              
          _thermalRow('Generated  :', genDate,
              labelSize: fieldLabelSize - 0.5,
              valueSize: fieldValueSize - 0.5,
              baseFont: baseFont,
              boldFont: boldFont),
        ],
      ),
    );
  }

  static pw.Widget _thermalRow(
    String label,
    String value, {
    required double labelSize,
    required double valueSize,
    required pw.Font baseFont,
    required pw.Font boldFont,
    bool isCode = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: baseFont,
              fontSize: labelSize,
              color: PdfColors.black,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: boldFont,
              fontSize: valueSize,
              color: PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  // ── Sheet Ticket Cell (A4 / Letter / Long / Legal) ─────────────────────────

  static pw.Widget _buildSheetTicketCell({
    required int idx,
    required List<Voucher> slice,
    required double cellW,
    required double cellH,
    required pw.Font baseFont,
    required pw.Font boldFont,
    int? overallIndex,
  }) {
    if (idx >= slice.length) {
      return pw.SizedBox(width: cellW, height: cellH);
    }

    final Voucher v = slice[idx];

    final String priceStr =
        v.price > 0 ? 'P${v.price.toStringAsFixed(0)}' : 'Free';
    final String uptimeStr =
        v.limitUptime.isNotEmpty ? v.limitUptime : '--';

    String validUntil = '--';
    final valMatch = RegExp(r'val:(\d+)([dh])').firstMatch(v.comment);
    final expMatch = RegExp(r'exp:(\S+)').firstMatch(v.comment);
    final vuMatch = RegExp(r'ValidUntil:(\S+)').firstMatch(v.comment);

    if (expMatch != null) {
      validUntil = expMatch.group(1)!;
    } else if (valMatch != null) {
      final numStr = valMatch.group(1)!;
      final unit = valMatch.group(2) == 'd' ? 'Days' : 'Hours';
      validUntil = '$numStr $unit';
    } else if (vuMatch != null) {
      validUntil = vuMatch.group(1)!;
    } else if (v.createdDate != null) {
      final d = v.createdDate!;
      validUntil =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    final String genDate = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';

    return pw.SizedBox(
      width: cellW,
      height: cellH,
      child: pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColors.black,
                  width: 0.6,
                ),
              ),
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                height: 14,
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Wi-Fi VOUCHER',
                          style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 6,
                            color: PdfColors.black,
                          ),
                        ),
                        if (overallIndex != null)
                          pw.Text(
                            '#$overallIndex',
                            style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 6,
                              color: PdfColors.black,
                            ),
                          ),
                      ],
                    ),
                    pw.SizedBox(height: 1.5),
                    pw.Container(height: 1.0, color: PdfColors.black),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(4, 3, 4, 2),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: [
                      _sheetRow(
                          (v.password.isNotEmpty) ? 'User Login:' : 'Voucher Code:', 
                          v.name.toUpperCase(),
                          baseFont: baseFont, boldFont: boldFont, bold: true),
                      if (v.password.isNotEmpty && v.password != v.name)
                        _sheetRow('Password :', v.password,
                            baseFont: baseFont, boldFont: boldFont, bold: true),
                      pw.Container(height: 0.5, color: PdfColors.black),
                      _sheetRow('Time Limit :', uptimeStr,
                          baseFont: baseFont, boldFont: boldFont),
                      if (v.customerName.isNotEmpty)
                        _sheetRow('Customer   :', v.customerName,
                            baseFont: baseFont, boldFont: boldFont),
                      _sheetRow('Price      :', priceStr,
                          baseFont: baseFont, boldFont: boldFont),
                      _sheetRow('Valid Until:', validUntil,
                          baseFont: baseFont, boldFont: boldFont),
                      _sheetRow('Generated:', genDate,
                          baseFont: baseFont, boldFont: boldFont),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _sheetRow(
    String label,
    String value, {
    required pw.Font baseFont,
    required pw.Font boldFont,
    bool bold = false,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            font: baseFont,
            fontSize: 5.5,
            color: PdfColors.black,
          ),
        ),
        pw.SizedBox(width: 2),
        pw.Expanded(
          child: pw.Text(
            value,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(
              font: bold ? boldFont : baseFont,
              fontSize: bold ? 6.5 : 6.0,
              color: PdfColors.black,
            ),
          ),
        ),
      ],
    );
  }

  // ── Thermal 58mm PDF With WiFi Instructions (HTML/PHP Template Match) ──────

  static Future<Uint8List> _buildThermalWithInstructionsPdf(
    List<Voucher> vouchers,
    pw.Font baseFont,
    pw.Font boldFont, {
    String hotspotName = 'JOEMIA WiFi Hotspot',
    String loginUrl = 'http://10.10.10.1',
    String footerNote = 'ENJOY @ JOEMIA CAFE',
  }) async {
    final pdf = pw.Document();
    const double rollWidth = 164.4; // 58mm
    const double horizontalMargin = 4.0;
    const double verticalMargin = 6.0;
    const double usableWidth = rollWidth - (horizontalMargin * 2);
    const double ticketHeight = 185.0; // Height for complete instruction voucher
    const double spacing = 8.0;

    final double totalRollHeight =
        (ticketHeight + spacing) * vouchers.length + 16.0;
    final pageFormat = PdfPageFormat(rollWidth, totalRollHeight);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(
          horizontal: horizontalMargin,
          vertical: verticalMargin,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < vouchers.length; i++) ...[
                _buildThermalInstructionTicket(
                  voucher: vouchers[i],
                  index: i + 1,
                  usableWidth: usableWidth,
                  baseFont: baseFont,
                  boldFont: boldFont,
                  hotspotName: hotspotName,
                  loginUrl: loginUrl,
                  footerNote: footerNote,
                ),
                if (i < vouchers.length - 1) pw.SizedBox(height: spacing),
              ],
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Single thermal 58mm ticket formatted like the HTML receipt template
  static pw.Widget _buildThermalInstructionTicket({
    required Voucher voucher,
    required int index,
    required double usableWidth,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
    required String loginUrl,
    required String footerNote,
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    final String uptimeStr =
        voucher.limitUptime.isNotEmpty ? voucher.limitUptime.toUpperCase() : '--';

    return pw.Container(
      width: usableWidth,
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.0),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          // ── 1. Hotspot Name Title ──────────────────────────
          pw.Center(
            child: pw.Text(
              hotspotName.toUpperCase(),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 11.0,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.SizedBox(height: 5),

          // ── 2. Voucher / Username & Password Box ────────────
          if (!hasPassword) ...[
            pw.Center(
              child: pw.Text(
                voucher.password.isNotEmpty ? 'USER LOGIN' : 'VOUCHER',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 9.0,
                  color: PdfColors.black,
                ),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              width: double.infinity,
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 1.2),
              ),
              child: pw.Center(
                child: pw.Text(
                  voucher.name.toUpperCase(),
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 15.0,
                    letterSpacing: 1.5,
                    color: PdfColors.black,
                  ),
                ),
              ),
            ),
          ] else ...[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      'Username',
                      style: pw.TextStyle(font: boldFont, fontSize: 8.5),
                    ),
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      'Password',
                      style: pw.TextStyle(font: boldFont, fontSize: 8.5),
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 3, horizontal: 2),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 1.0),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        voucher.name.toUpperCase(),
                        style: pw.TextStyle(font: boldFont, fontSize: 11.0),
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 3, horizontal: 2),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 1.0),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        voucher.password,
                        style: pw.TextStyle(font: boldFont, fontSize: 11.0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          pw.SizedBox(height: 5),

          // ── 3. HOW TO CONNECT Instructions ─────────────────
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.black, width: 0.8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'HOW TO CONNECT',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 7.5,
                    color: PdfColors.black,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  '1. Connect to $hotspotName',
                  style: pw.TextStyle(font: baseFont, fontSize: 6.5),
                ),
                pw.SizedBox(height: 1.5),
                pw.Text(
                  '2. If login page doesn\'t open, visit $loginUrl',
                  style: pw.TextStyle(font: baseFont, fontSize: 6.5),
                ),
                pw.SizedBox(height: 1.5),
                pw.Text(
                  '3. Enter the voucher code above',
                  style: pw.TextStyle(font: baseFont, fontSize: 6.5),
                ),
                pw.SizedBox(height: 1.5),
                pw.Text(
                  '4. Tap CONNECT',
                  style: pw.TextStyle(font: baseFont, fontSize: 6.5),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 5),

          // ── 4. DURATION & FOOTER ───────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.black, width: 0.8)),
            ),
            child: pw.Column(
              children: [
                pw.Center(
                  child: pw.Text(
                    'DURATION: $uptimeStr',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 10.0,
                      color: PdfColors.black,
                    ),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    footerNote.toUpperCase(),
                    style: pw.TextStyle(
                      font: baseFont,
                      fontSize: 7.5,
                      color: PdfColors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Custom Template Implementations ────────────────────────────────────────

  static Future<Uint8List> _buildCustomTemplatePdf(
    List<Voucher> vouchers,
    pw.Font baseFont,
    pw.Font boldFont,
    VoucherPaperSize paperSize, {
    required String hotspotName,
    required String loginUrl,
    required String footerNote,
    PdfPageFormat? customFormat,
  }) async {
    final pdf = pw.Document();
    final isThermal = paperSize.isThermal;

    if (isThermal) {
      final double rollWidth =
          paperSize == VoucherPaperSize.thermal58 ? 164.4 : 226.7;
      final double horizontalMargin =
          paperSize == VoucherPaperSize.thermal58 ? 4.0 : 6.0;
      final double usableWidth = rollWidth - (horizontalMargin * 2);
      const double ticketH = 140.0;
      const double spacing = 8.0;

      final double totalRollHeight =
          (ticketH + spacing) * vouchers.length + 16.0;
      final pageFormat = PdfPageFormat(rollWidth, totalRollHeight);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.symmetric(
            horizontal: horizontalMargin,
            vertical: 6.0,
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < vouchers.length; i++) ...[
                  _buildCustomThermalTicket(
                    voucher: vouchers[i],
                    usableWidth: usableWidth,
                    baseFont: baseFont,
                    boldFont: boldFont,
                    hotspotName: hotspotName,
                  ),
                  if (i < vouchers.length - 1) pw.SizedBox(height: spacing),
                ],
              ],
            );
          },
        ),
      );
    } else {
      var format = (paperSize == VoucherPaperSize.custom && customFormat != null)
          ? customFormat
          : paperSize.pdfFormat;
      const int cols = 3; // Wider tickets for custom template
      const double cellH = 100.0;
      const double headerHeight = 16.0;
      const double headerSpacing = 4.0;
      const double colSpacing = 6.0;
      const double rowSpacing = 6.0;

      final double usableWidth = format.width - 24;
      final double usableHeight = format.height - 24;
      final double cellW = (usableWidth - (cols - 1) * colSpacing) / cols;

      final double gridUsableH = usableHeight - headerHeight - headerSpacing;
      final int rows = ((gridUsableH + rowSpacing) / (cellH + rowSpacing)).floor().clamp(1, 30);
      final int perPage = cols * rows;
      final int totalPages = (vouchers.length / perPage).ceil().clamp(1, 9999);

      for (int p = 0; p < totalPages; p++) {
        final slice = vouchers.skip(p * perPage).take(perPage).toList();

        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(12),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    height: headerHeight,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Custom Template Vouchers', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                        pw.Text('Page ${p + 1} of $totalPages', style: pw.TextStyle(font: baseFont, fontSize: 8)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: headerSpacing),
                  for (int r = 0; r < slice.length; r += cols) ...[
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        for (int c = 0; c < cols; c++) ...[
                          if (r + c < slice.length)
                            _buildCustomSheetTicket(
                              voucher: slice[r + c],
                              cellW: cellW,
                              cellH: cellH,
                              baseFont: baseFont,
                              boldFont: boldFont,
                              hotspotName: hotspotName,
                            )
                          else
                            pw.SizedBox(width: cellW, height: cellH),
                          if (c < cols - 1) pw.SizedBox(width: colSpacing),
                        ],
                      ],
                    ),
                    if (r + cols < slice.length) pw.SizedBox(height: rowSpacing),
                  ],
                ],
              );
            },
          ),
        );
      }
    }
    return pdf.save();
  }

  static pw.Widget _buildCustomThermalTicket({
    required Voucher voucher,
    required double usableWidth,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    return pw.Container(
      width: usableWidth,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 2.0),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(hotspotName, style: pw.TextStyle(font: boldFont, fontSize: 14)),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.black,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text('WIFI ACCESS', style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.white)),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Code:', style: pw.TextStyle(font: baseFont, fontSize: 10)),
          pw.Text(voucher.name.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 18, letterSpacing: 2)),
          if (hasPassword) ...[
            pw.SizedBox(height: 4),
            pw.Text('Password:', style: pw.TextStyle(font: baseFont, fontSize: 10)),
            pw.Text(voucher.password, style: pw.TextStyle(font: boldFont, fontSize: 14)),
          ],
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Time:', style: pw.TextStyle(font: baseFont, fontSize: 10)),
              pw.Text(voucher.limitUptime.isEmpty ? 'Unlimited' : voucher.limitUptime, style: pw.TextStyle(font: boldFont, fontSize: 10)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Price:', style: pw.TextStyle(font: baseFont, fontSize: 10)),
              pw.Text(voucher.price > 0 ? 'P${voucher.price.toStringAsFixed(0)}' : 'Free', style: pw.TextStyle(font: boldFont, fontSize: 10)),
              if (voucher.customerName.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text('Customer:', style: pw.TextStyle(font: baseFont, fontSize: 10)),
                pw.Text(voucher.customerName, style: pw.TextStyle(font: boldFont, fontSize: 10)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCustomSheetTicket({
    required Voucher voucher,
    required double cellW,
    required double cellH,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    return pw.Container(
      width: cellW,
      height: cellH,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(4),
            color: PdfColors.black,
            child: pw.Center(
              child: pw.Text(hotspotName.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.white)),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('VOUCHER CODE', style: pw.TextStyle(font: baseFont, fontSize: 7)),
                    pw.Text(voucher.name.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 14)),
                    if (hasPassword) ...[
                      pw.SizedBox(height: 2),
                      pw.Text('PASSWORD', style: pw.TextStyle(font: baseFont, fontSize: 7)),
                      pw.Text(voucher.password, style: pw.TextStyle(font: boldFont, fontSize: 10)),
                    ],
                  ],
                ),
              ),
              pw.Container(width: 1, height: 40, color: PdfColors.black),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('DURATION', style: pw.TextStyle(font: baseFont, fontSize: 6)),
                    pw.Text(voucher.limitUptime.isEmpty ? 'Unlimited' : voucher.limitUptime, style: pw.TextStyle(font: boldFont, fontSize: 8)),
                    pw.SizedBox(height: 4),
                    pw.Text('PRICE', style: pw.TextStyle(font: baseFont, fontSize: 6)),
                    pw.Text(voucher.price > 0 ? 'P${voucher.price.toStringAsFixed(0)}' : 'Free', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Modern Template Implementations ────────────────────────────────────────

  static Future<Uint8List> _buildModernTemplatePdf(
    List<Voucher> vouchers,
    pw.Font baseFont,
    pw.Font boldFont,
    VoucherPaperSize paperSize, {
    required String hotspotName,
    PdfPageFormat? customFormat,
  }) async {
    final pdf = pw.Document();
    final isThermal = paperSize.isThermal;

    if (isThermal) {
      final double rollWidth = paperSize == VoucherPaperSize.thermal58 ? 164.4 : 226.7;
      final double horizontalMargin = paperSize == VoucherPaperSize.thermal58 ? 4.0 : 6.0;
      final double usableWidth = rollWidth - (horizontalMargin * 2);
      const double ticketH = 130.0;
      const double spacing = 8.0;

      final double totalRollHeight = (ticketH + spacing) * vouchers.length + 16.0;
      final pageFormat = PdfPageFormat(rollWidth, totalRollHeight);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: 6.0),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < vouchers.length; i++) ...[
                  _buildModernThermalTicket(
                    voucher: vouchers[i],
                    usableWidth: usableWidth,
                    baseFont: baseFont,
                    boldFont: boldFont,
                    hotspotName: hotspotName,
                  ),
                  if (i < vouchers.length - 1) pw.SizedBox(height: spacing),
                ],
              ],
            );
          },
        ),
      );
    } else {
      var format = (paperSize == VoucherPaperSize.custom && customFormat != null) ? customFormat : paperSize.pdfFormat;
      const int cols = 3;
      const double cellH = 90.0;
      const double headerHeight = 16.0;
      const double headerSpacing = 4.0;
      const double colSpacing = 8.0;
      const double rowSpacing = 8.0;

      final double usableWidth = format.width - 24;
      final double usableHeight = format.height - 24;
      final double cellW = (usableWidth - (cols - 1) * colSpacing) / cols;

      final double gridUsableH = usableHeight - headerHeight - headerSpacing;
      final int rows = ((gridUsableH + rowSpacing) / (cellH + rowSpacing)).floor().clamp(1, 30);
      final int perPage = cols * rows;
      final int totalPages = (vouchers.length / perPage).ceil().clamp(1, 9999);

      for (int p = 0; p < totalPages; p++) {
        final slice = vouchers.skip(p * perPage).take(perPage).toList();

        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(12),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    height: headerHeight,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Modern Template Vouchers', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                        pw.Text('Page ${p + 1} of $totalPages', style: pw.TextStyle(font: baseFont, fontSize: 8)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: headerSpacing),
                  for (int r = 0; r < slice.length; r += cols) ...[
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        for (int c = 0; c < cols; c++) ...[
                          if (r + c < slice.length)
                            _buildModernSheetTicket(
                              voucher: slice[r + c],
                              cellW: cellW,
                              cellH: cellH,
                              baseFont: baseFont,
                              boldFont: boldFont,
                              hotspotName: hotspotName,
                            )
                          else
                            pw.SizedBox(width: cellW, height: cellH),
                          if (c < cols - 1) pw.SizedBox(width: colSpacing),
                        ],
                      ],
                    ),
                    if (r + cols < slice.length) pw.SizedBox(height: rowSpacing),
                  ],
                ],
              );
            },
          ),
        );
      }
    }
    return pdf.save();
  }

  static pw.Widget _buildModernThermalTicket({
    required Voucher voucher,
    required double usableWidth,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    return pw.Container(
      width: usableWidth,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text(hotspotName, style: pw.TextStyle(font: boldFont, fontSize: 12, color: PdfColors.grey800)),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text('INTERNET VOUCHER', style: pw.TextStyle(font: baseFont, fontSize: 8, color: PdfColors.grey600)),
          ),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(voucher.name.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 20, letterSpacing: 1.5, color: PdfColors.blueGrey900)),
          ),
          if (hasPassword) ...[
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text('PIN: ${voucher.password}', style: pw.TextStyle(font: baseFont, fontSize: 12, color: PdfColors.grey800)),
            ),
          ],
          pw.SizedBox(height: 10),
          pw.Divider(color: PdfColors.grey400, thickness: 0.5),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('DURATION', style: pw.TextStyle(font: baseFont, fontSize: 7, color: PdfColors.grey600)),
                  pw.Text(voucher.limitUptime.isEmpty ? 'Unlimited' : voucher.limitUptime, style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.grey900)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('PRICE', style: pw.TextStyle(font: baseFont, fontSize: 7, color: PdfColors.grey600)),
                  pw.Text(voucher.price > 0 ? 'P${voucher.price.toStringAsFixed(0)}' : 'Free', style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.grey900)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildModernSheetTicket({
    required Voucher voucher,
    required double cellW,
    required double cellH,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    return pw.Container(
      width: cellW,
      height: cellH,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(hotspotName, style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.grey800)),
              pw.Text('WIFI', style: pw.TextStyle(font: baseFont, fontSize: 7, color: PdfColors.grey600)),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(voucher.name.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 16, letterSpacing: 1.2, color: PdfColors.blueGrey900)),
          if (hasPassword) ...[
            pw.SizedBox(height: 2),
            pw.Text('PIN: ${voucher.password}', style: pw.TextStyle(font: baseFont, fontSize: 9, color: PdfColors.grey800)),
          ],
          pw.Expanded(child: pw.SizedBox()),
          pw.Divider(color: PdfColors.grey400, thickness: 0.5),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('TIME', style: pw.TextStyle(font: baseFont, fontSize: 6, color: PdfColors.grey600)),
                  pw.Text(voucher.limitUptime.isEmpty ? 'Unlimited' : voucher.limitUptime, style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.grey900)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('PRICE', style: pw.TextStyle(font: baseFont, fontSize: 6, color: PdfColors.grey600)),
                  pw.Text(voucher.price > 0 ? 'P${voucher.price.toStringAsFixed(0)}' : 'Free', style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.grey900)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Minimal Template Implementations ────────────────────────────────────────

  static Future<Uint8List> _buildMinimalTemplatePdf(
    List<Voucher> vouchers,
    pw.Font baseFont,
    pw.Font boldFont,
    VoucherPaperSize paperSize, {
    required String hotspotName,
    PdfPageFormat? customFormat,
  }) async {
    final pdf = pw.Document();
    final isThermal = paperSize.isThermal;

    if (isThermal) {
      final double rollWidth = paperSize == VoucherPaperSize.thermal58 ? 164.4 : 226.7;
      final double horizontalMargin = paperSize == VoucherPaperSize.thermal58 ? 4.0 : 6.0;
      final double usableWidth = rollWidth - (horizontalMargin * 2);
      const double ticketH = 100.0;
      const double spacing = 6.0;

      final double totalRollHeight = (ticketH + spacing) * vouchers.length + 16.0;
      final pageFormat = PdfPageFormat(rollWidth, totalRollHeight);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: 6.0),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < vouchers.length; i++) ...[
                  _buildMinimalThermalTicket(
                    voucher: vouchers[i],
                    usableWidth: usableWidth,
                    baseFont: baseFont,
                    boldFont: boldFont,
                    hotspotName: hotspotName,
                  ),
                  if (i < vouchers.length - 1) pw.SizedBox(height: spacing),
                ],
              ],
            );
          },
        ),
      );
    } else {
      var format = (paperSize == VoucherPaperSize.custom && customFormat != null) ? customFormat : paperSize.pdfFormat;
      const int cols = 3;
      const double cellH = 80.0;
      const double headerHeight = 16.0;
      const double headerSpacing = 4.0;
      const double colSpacing = 8.0;
      const double rowSpacing = 8.0;

      final double usableWidth = format.width - 24;
      final double usableHeight = format.height - 24;
      final double cellW = (usableWidth - (cols - 1) * colSpacing) / cols;

      final double gridUsableH = usableHeight - headerHeight - headerSpacing;
      final int rows = ((gridUsableH + rowSpacing) / (cellH + rowSpacing)).floor().clamp(1, 30);
      final int perPage = cols * rows;
      final int totalPages = (vouchers.length / perPage).ceil().clamp(1, 9999);

      for (int p = 0; p < totalPages; p++) {
        final slice = vouchers.skip(p * perPage).take(perPage).toList();

        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(12),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    height: headerHeight,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Minimal Template Vouchers', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                        pw.Text('Page ${p + 1} of $totalPages', style: pw.TextStyle(font: baseFont, fontSize: 8)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: headerSpacing),
                  for (int r = 0; r < slice.length; r += cols) ...[
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        for (int c = 0; c < cols; c++) ...[
                          if (r + c < slice.length)
                            _buildMinimalSheetTicket(
                              voucher: slice[r + c],
                              cellW: cellW,
                              cellH: cellH,
                              baseFont: baseFont,
                              boldFont: boldFont,
                              hotspotName: hotspotName,
                            )
                          else
                            pw.SizedBox(width: cellW, height: cellH),
                          if (c < cols - 1) pw.SizedBox(width: colSpacing),
                        ],
                      ],
                    ),
                    if (r + cols < slice.length) pw.SizedBox(height: rowSpacing),
                  ],
                ],
              );
            },
          ),
        );
      }
    }
    return pdf.save();
  }

  static pw.Widget _buildMinimalThermalTicket({
    required Voucher voucher,
    required double usableWidth,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    return pw.Container(
      width: usableWidth,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(voucher.name.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 24, letterSpacing: 1.5)),
          if (hasPassword) ...[
            pw.SizedBox(height: 2),
            pw.Text(voucher.password, style: pw.TextStyle(font: baseFont, fontSize: 14)),
          ],
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(voucher.limitUptime.isEmpty ? 'Unlimited' : voucher.limitUptime, style: pw.TextStyle(font: baseFont, fontSize: 10)),
              pw.Text(' | ', style: pw.TextStyle(font: baseFont, fontSize: 10)),
              pw.Text(voucher.price > 0 ? 'P${voucher.price.toStringAsFixed(0)}' : 'Free', style: pw.TextStyle(font: baseFont, fontSize: 10)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(hotspotName, style: pw.TextStyle(font: baseFont, fontSize: 8, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  static pw.Widget _buildMinimalSheetTicket({
    required Voucher voucher,
    required double cellW,
    required double cellH,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    return pw.Container(
      width: cellW,
      height: cellH,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(voucher.name.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 18, letterSpacing: 1.2)),
          if (hasPassword) ...[
            pw.SizedBox(height: 2),
            pw.Text(voucher.password, style: pw.TextStyle(font: baseFont, fontSize: 10)),
          ],
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(voucher.limitUptime.isEmpty ? 'Unlimited' : voucher.limitUptime, style: pw.TextStyle(font: baseFont, fontSize: 8)),
              pw.Text(' | ', style: pw.TextStyle(font: baseFont, fontSize: 8)),
              pw.Text(voucher.price > 0 ? 'P${voucher.price.toStringAsFixed(0)}' : 'Free', style: pw.TextStyle(font: baseFont, fontSize: 8)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(hotspotName, style: pw.TextStyle(font: baseFont, fontSize: 6, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  // ── Classic Template Implementations ───────────────────────────────────────

  static Future<Uint8List> _buildClassicTemplatePdf(
    List<Voucher> vouchers,
    pw.Font baseFont,
    pw.Font boldFont,
    VoucherPaperSize paperSize, {
    required String hotspotName,
    PdfPageFormat? customFormat,
  }) async {
    final pdf = pw.Document();
    final isThermal = paperSize.isThermal;

    if (isThermal) {
      final double rollWidth = paperSize == VoucherPaperSize.thermal58 ? 164.4 : 226.7;
      final double horizontalMargin = paperSize == VoucherPaperSize.thermal58 ? 4.0 : 6.0;
      final double usableWidth = rollWidth - (horizontalMargin * 2);
      const double ticketH = 150.0;
      const double spacing = 8.0;

      final double totalRollHeight = (ticketH + spacing) * vouchers.length + 16.0;
      final pageFormat = PdfPageFormat(rollWidth, totalRollHeight);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: 6.0),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < vouchers.length; i++) ...[
                  _buildClassicThermalTicket(
                    voucher: vouchers[i],
                    usableWidth: usableWidth,
                    baseFont: baseFont,
                    boldFont: boldFont,
                    hotspotName: hotspotName,
                  ),
                  if (i < vouchers.length - 1) pw.SizedBox(height: spacing),
                ],
              ],
            );
          },
        ),
      );
    } else {
      var format = (paperSize == VoucherPaperSize.custom && customFormat != null) ? customFormat : paperSize.pdfFormat;
      const int cols = 3;
      const double cellH = 110.0;
      const double headerHeight = 16.0;
      const double headerSpacing = 4.0;
      const double colSpacing = 6.0;
      const double rowSpacing = 6.0;

      final double usableWidth = format.width - 24;
      final double usableHeight = format.height - 24;
      final double cellW = (usableWidth - (cols - 1) * colSpacing) / cols;

      final double gridUsableH = usableHeight - headerHeight - headerSpacing;
      final int rows = ((gridUsableH + rowSpacing) / (cellH + rowSpacing)).floor().clamp(1, 30);
      final int perPage = cols * rows;
      final int totalPages = (vouchers.length / perPage).ceil().clamp(1, 9999);

      for (int p = 0; p < totalPages; p++) {
        final slice = vouchers.skip(p * perPage).take(perPage).toList();

        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(12),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    height: headerHeight,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Classic Template Vouchers', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                        pw.Text('Page ${p + 1} of $totalPages', style: pw.TextStyle(font: baseFont, fontSize: 8)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: headerSpacing),
                  for (int r = 0; r < slice.length; r += cols) ...[
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        for (int c = 0; c < cols; c++) ...[
                          if (r + c < slice.length)
                            _buildClassicSheetTicket(
                              voucher: slice[r + c],
                              cellW: cellW,
                              cellH: cellH,
                              baseFont: baseFont,
                              boldFont: boldFont,
                              hotspotName: hotspotName,
                            )
                          else
                            pw.SizedBox(width: cellW, height: cellH),
                          if (c < cols - 1) pw.SizedBox(width: colSpacing),
                        ],
                      ],
                    ),
                    if (r + cols < slice.length) pw.SizedBox(height: rowSpacing),
                  ],
                ],
              );
            },
          ),
        );
      }
    }
    return pdf.save();
  }

  static pw.Widget _buildClassicThermalTicket({
    required Voucher voucher,
    required double usableWidth,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
    int? overallIndex,
  }) {
    final String genDate = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    return pw.Container(
      width: usableWidth,
      padding: const pw.EdgeInsets.all(2),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 2.0),
      ),
      child: pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(hotspotName, style: pw.TextStyle(font: boldFont, fontSize: 14)),
                if (overallIndex != null) ...[
                  pw.SizedBox(width: 4),
                  pw.Text('#$overallIndex', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                ],
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 8),
            pw.Text('VOUCHER CODE', style: pw.TextStyle(font: baseFont, fontSize: 8)),
            pw.SizedBox(height: 2),
            pw.Text(voucher.name.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 18, letterSpacing: 1.2)),
            if (hasPassword) ...[
              pw.SizedBox(height: 4),
              pw.Text('PASSWORD', style: pw.TextStyle(font: baseFont, fontSize: 8)),
              pw.SizedBox(height: 2),
              pw.Text(voucher.password, style: pw.TextStyle(font: boldFont, fontSize: 14)),
            ],
            pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10),
            child: pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
          ),  pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Duration:', style: pw.TextStyle(font: baseFont, fontSize: 9)),
                pw.Text(voucher.limitUptime.isEmpty ? 'Unlimited' : voucher.limitUptime, style: pw.TextStyle(font: boldFont, fontSize: 9)),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Price:', style: pw.TextStyle(font: baseFont, fontSize: 9)),
                pw.Text(voucher.price > 0 ? 'P${voucher.price.toStringAsFixed(0)}' : 'Free', style: pw.TextStyle(font: boldFont, fontSize: 9)),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Generated:', style: pw.TextStyle(font: baseFont, fontSize: 9)),
                pw.Text(genDate, style: pw.TextStyle(font: boldFont, fontSize: 9)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildClassicSheetTicket({
    required Voucher voucher,
    required double cellW,
    required double cellH,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    return pw.Container(
      width: cellW,
      height: cellH,
      padding: const pw.EdgeInsets.all(2),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 2.0),
      ),
      child: pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(hotspotName, style: pw.TextStyle(font: boldFont, fontSize: 10)),
            pw.SizedBox(height: 2),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 6),
            pw.Text('VOUCHER CODE', style: pw.TextStyle(font: baseFont, fontSize: 6)),
            pw.SizedBox(height: 2),
            pw.Text(voucher.name.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 14, letterSpacing: 1.2)),
            if (hasPassword) ...[
              pw.SizedBox(height: 2),
              pw.Text('PASSWORD', style: pw.TextStyle(font: baseFont, fontSize: 6)),
              pw.SizedBox(height: 1),
              pw.Text(voucher.password, style: pw.TextStyle(font: boldFont, fontSize: 10)),
            ],
            pw.Expanded(child: pw.SizedBox()),
            pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Duration:', style: pw.TextStyle(font: baseFont, fontSize: 7)),
                pw.Text(voucher.limitUptime.isEmpty ? 'Unlimited' : voucher.limitUptime, style: pw.TextStyle(font: boldFont, fontSize: 7)),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Price:', style: pw.TextStyle(font: baseFont, fontSize: 7)),
                pw.Text(voucher.price > 0 ? 'P${voucher.price.toStringAsFixed(0)}' : 'Free', style: pw.TextStyle(font: boldFont, fontSize: 7)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Future<Uint8List> _buildPremiumTemplatePdf(
    List<Voucher> vouchers,
    pw.Font baseFont,
    pw.Font boldFont,
    VoucherPaperSize paperSize, {
    required String hotspotName,
    required String loginUrl,
    required String footerNote,
    PdfPageFormat? customFormat,
    Uint8List? logoBytes,
    PdfColor primaryColor = PdfColors.green,
  }) async {
    final pdf = pw.Document();
    final isThermal = paperSize.isThermal;

    if (isThermal) {
      final double rollWidth = paperSize == VoucherPaperSize.thermal58 ? 164.4 : 226.7;
      final double horizontalMargin = paperSize == VoucherPaperSize.thermal58 ? 4.0 : 6.0;
      final double usableWidth = rollWidth - (horizontalMargin * 2);
      const double ticketH = 150.0;
      const double spacing = 8.0;

      final double totalRollHeight = (ticketH + spacing) * vouchers.length + 16.0;
      final pageFormat = PdfPageFormat(rollWidth, totalRollHeight);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: 6.0),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < vouchers.length; i++) ...[
                  _buildPremiumThermalTicket(
                    voucher: vouchers[i],
                    usableWidth: usableWidth,
                    baseFont: baseFont,
                    boldFont: boldFont,
                    hotspotName: hotspotName,
                    overallIndex: i + 1,
                  ),
                  if (i < vouchers.length - 1) pw.SizedBox(height: spacing),
                ],
              ],
            );
          },
        ),
      );
    } else {
      var format = (paperSize == VoucherPaperSize.custom && customFormat != null) ? customFormat : paperSize.pdfFormat;
      const int cols = 3; // 3 columns for premium template
      const double cellH = 125.0;
      const double headerHeight = 16.0;
      const double headerSpacing = 4.0;
      const double colSpacing = 8.0;
      const double rowSpacing = 8.0;

      final double usableWidth = format.width - 24;
      final double usableHeight = format.height - 24;
      final double cellW = (usableWidth - (cols - 1) * colSpacing) / cols;

      final double gridUsableH = usableHeight - headerHeight - headerSpacing;
      final int rows = ((gridUsableH + rowSpacing) / (cellH + rowSpacing)).floor().clamp(1, 30);
      final int perPage = cols * rows;
      final int totalPages = (vouchers.length / perPage).ceil().clamp(1, 9999);

      for (int p = 0; p < totalPages; p++) {
        final slice = vouchers.skip(p * perPage).take(perPage).toList();

        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(12),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    height: headerHeight,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Vouchers ($hotspotName)', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                        pw.Text('Page ${p + 1} of $totalPages', style: pw.TextStyle(font: baseFont, fontSize: 9)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: headerSpacing),
                  pw.Expanded(
                    child: pw.Wrap(
                      spacing: colSpacing,
                      runSpacing: rowSpacing,
                      children: slice.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final voucher = entry.value;
                        final overallIndex = (p * perPage) + idx + 1;
                        return _buildPremiumSheetTicket(
                          voucher: voucher,
                          width: cellW,
                          height: cellH,
                          baseFont: baseFont,
                          boldFont: boldFont,
                          hotspotName: hotspotName,
                          loginUrl: loginUrl,
                          footerNote: footerNote,
                          logoBytes: logoBytes,
                          primaryColor: primaryColor,
                          overallIndex: overallIndex,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }
    }
    return pdf.save();
  }

  static String _formatDataLimit(String bytesStr) {
    if (bytesStr.isEmpty || bytesStr == '0') return 'Unlimited Data';
    final bytes = int.tryParse(bytesStr) ?? 0;
    if (bytes == 0) return 'Unlimited Data';
    if (bytes >= 1073741824) return 'Data: ${(bytes / 1073741824).toStringAsFixed(1).replaceAll('.0', '')}GB';
    if (bytes >= 1048576) return 'Data: ${(bytes / 1048576).toStringAsFixed(1).replaceAll('.0', '')}MB';
    return 'Data: ${(bytes / 1024).toStringAsFixed(0)}KB';
  }

  static pw.Widget _buildPremiumSheetTicket({
    required Voucher voucher,
    required double width,
    required double height,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
    required String loginUrl,
    required String footerNote,
    Uint8List? logoBytes,
    PdfColor primaryColor = PdfColors.green,
    int? overallIndex,
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    final String priceText = voucher.formattedPrice;
    final String genDate = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';

    return pw.Container(
      width: width,
      height: height,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 1),
      ),
      child: pw.Column(
        children: [
          pw.Expanded(
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 55,
                  child: pw.Container(
                    color: PdfColors.white,
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            if (logoBytes != null)
                              pw.Container(
                                width: 12,
                                height: 12,
                                child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
                              )
                            else
                              pw.Container(
                                width: 12,
                                height: 12,
                                decoration: pw.BoxDecoration(
                                  color: primaryColor,
                                  shape: pw.BoxShape.circle,
                                ),
                              ),
                            pw.SizedBox(width: 4),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(hotspotName.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.grey800)),
                                  pw.Text('INTERNET HOTSPOT SERVICE', style: pw.TextStyle(font: baseFont, fontSize: 3.5, color: PdfColors.grey600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Divider(thickness: 1, color: PdfColors.grey400),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('User: ', style: pw.TextStyle(font: boldFont, fontSize: 11)),
                            pw.Text(voucher.name, style: pw.TextStyle(font: boldFont, fontSize: 11)),
                          ],
                        ),
                          pw.Divider(thickness: 2, color: primaryColor),
                          pw.SizedBox(height: 2),
                          if (hasPassword) ...[
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Text('Pass: ', style: pw.TextStyle(font: boldFont, fontSize: 11)),
                                pw.Text(voucher.password, style: pw.TextStyle(font: boldFont, fontSize: 11)),
                              ],
                            ),
                            pw.Divider(thickness: 2, color: primaryColor),
                          ],
                        pw.Expanded(child: pw.SizedBox()),
                        pw.Center(
                          child: pw.Text(
                            footerNote,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: baseFont, fontSize: 5, color: PdfColors.black),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: 45,
                  child: pw.Container(
                    color: PdfColors.grey200,
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(priceText == '0' ? 'Free' : 'P$priceText', style: pw.TextStyle(font: boldFont, fontSize: 14, color: primaryColor)),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('Validity: ${voucher.limitUptime.isEmpty ? "Unlimited" : voucher.limitUptime}', style: pw.TextStyle(font: boldFont, fontSize: 6)),
                        pw.SizedBox(height: 2),
                        if (voucher.customerName.isNotEmpty) ...[
                          pw.Text('Name: ${voucher.customerName}', style: pw.TextStyle(font: boldFont, fontSize: 6)),
                          pw.SizedBox(height: 2),
                        ],
                        pw.Text('Time: ${voucher.limitUptime.isEmpty ? "Unlimited" : voucher.limitUptime}', style: pw.TextStyle(font: boldFont, fontSize: 6)),
                        pw.SizedBox(height: 2),
                        pw.Text(_formatDataLimit(voucher.limitBytes), style: pw.TextStyle(font: boldFont, fontSize: 6)),
                        pw.SizedBox(height: 2),
                        pw.Text('Generated: $genDate', style: pw.TextStyle(font: baseFont, fontSize: 5)),
                        pw.Expanded(child: pw.SizedBox()),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(4),
                          color: PdfColors.white,
                          child: pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: loginUrl,
                            width: 32,
                            height: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 8),
            color: primaryColor,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Login : $loginUrl',
                  style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.white),
                ),
                if (overallIndex != null)
                  pw.Text(
                    '#$overallIndex',
                    style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.white),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPremiumThermalTicket({
    required Voucher voucher,
    required double usableWidth,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
    int? overallIndex,
  }) {
    // Thermal representation for premium design
    return _buildClassicThermalTicket(
      voucher: voucher,
      usableWidth: usableWidth,
      baseFont: baseFont,
      boldFont: boldFont,
      hotspotName: hotspotName,
      overallIndex: overallIndex,
    );
  }
}
