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
    }
  }

  bool get isThermal =>
      this == VoucherPaperSize.thermal58 || this == VoucherPaperSize.thermal80;
}

/// Template style options for voucher printing.
enum VoucherTemplate {
  standard, // Original design
  withInstructions, // With WiFi connection instructions (thermal 58mm)
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
  }) async {
    final pdf = pw.Document();
    final isThermal = paperSize.isThermal;
    final baseFont = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();

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
      var format = paperSize.pdfFormat;
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
    final vuMatch =
        RegExp(r'ValidUntil:(\d{4}-\d{2}-\d{2})').firstMatch(voucher.comment);
    if (vuMatch != null) {
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
              (voucher.password.isNotEmpty && voucher.password != voucher.name) ? 'User Login:' : 'Voucher Code:', 
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

          // Price
          _thermalRow('Price      :', priceStr,
              labelSize: fieldLabelSize,
              valueSize: fieldValueSize,
              baseFont: baseFont,
              boldFont: boldFont),

          // Valid Until
          _thermalRow('Valid Until:', validUntil,
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
    final vuMatch =
        RegExp(r'ValidUntil:(\d{4}-\d{2}-\d{2})').firstMatch(v.comment);
    if (vuMatch != null) {
      validUntil = vuMatch.group(1)!;
    } else if (v.createdDate != null) {
      final d = v.createdDate!;
      validUntil =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

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
                    pw.Text(
                      'Wi-Fi VOUCHER',
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 6,
                        color: PdfColors.black,
                      ),
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
                          (v.password.isNotEmpty && v.password != v.name) ? 'User Login:' : 'Voucher Code:', 
                          v.name.toUpperCase(),
                          baseFont: baseFont, boldFont: boldFont, bold: true),
                      if (v.password.isNotEmpty && v.password != v.name)
                        _sheetRow('Password :', v.password,
                            baseFont: baseFont, boldFont: boldFont, bold: true),
                      pw.Container(height: 0.5, color: PdfColors.black),
                      _sheetRow('Time Limit :', uptimeStr,
                          baseFont: baseFont, boldFont: boldFont),
                      _sheetRow('Price      :', priceStr,
                          baseFont: baseFont, boldFont: boldFont),
                      _sheetRow('Valid Until:', validUntil,
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
                'VOUCHER',
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
}
