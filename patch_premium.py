import re

with open('lib/services/voucher_pdf_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add to enum
content = re.sub(
    r'(enum VoucherTemplate \{[^}]+)(})',
    r'\1  premium, // Premium Split layout\n\2',
    content
)

# 2. Add to displayName
content = re.sub(
    r'(case VoucherTemplate.classic: return \'Classic Bordered\';)',
    r"\1\n      case VoucherTemplate.premium: return 'Premium Split';",
    content
)

# 3. Add to buildPdf routing
router_code = """
    if (template == VoucherTemplate.premium) {
      return _buildPremiumTemplatePdf(
        vouchers,
        baseFont,
        boldFont,
        paperSize,
        hotspotName: hotspotName,
        loginUrl: loginUrl,
        customFormat: customFormat,
      );
    }
"""
content = re.sub(
    r'(if \(template == VoucherTemplate\.classic\) \{.*?\n    \})',
    r'\1\n' + router_code,
    content,
    flags=re.DOTALL
)

# 4. Append the builders at the end of the class (before the last closing brace)
builder_code = """

  static Future<Uint8List> _buildPremiumTemplatePdf(
    List<Voucher> vouchers,
    pw.Font baseFont,
    pw.Font boldFont,
    VoucherPaperSize paperSize, {
    required String hotspotName,
    required String loginUrl,
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
                  _buildPremiumThermalTicket(
                    voucher: vouchers[i],
                    usableWidth: usableWidth,
                    baseFont: baseFont,
                    boldFont: boldFont,
                    hotspotName: hotspotName,
                    loginUrl: loginUrl,
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
      const int cols = 2; // wider template, 2 columns
      const double cellH = 140.0;
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
                      children: slice.map((voucher) {
                        return _buildPremiumSheetTicket(
                          voucher: voucher,
                          width: cellW,
                          height: cellH,
                          baseFont: baseFont,
                          boldFont: boldFont,
                          hotspotName: hotspotName,
                          loginUrl: loginUrl,
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

  static pw.Widget _buildPremiumSheetTicket({
    required Voucher voucher,
    required double width,
    required double height,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
    required String loginUrl,
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;

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
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Container(
                              width: 16,
                              height: 16,
                              decoration: const pw.BoxDecoration(
                                color: PdfColors.blueAccent,
                                shape: pw.BoxShape.circle,
                              ),
                            ),
                            pw.SizedBox(width: 4),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(hotspotName.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.grey800)),
                                  pw.Text('INTERNET HOTSPOT SERVICE', style: pw.TextStyle(font: baseFont, fontSize: 5, color: PdfColors.grey600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 12),
                        pw.Text('KODE VOUCHER', style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.grey800)),
                        pw.Divider(thickness: 1, color: PdfColors.grey400),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('User: ', style: pw.TextStyle(font: boldFont, fontSize: 14)),
                            pw.Text(voucher.name, style: pw.TextStyle(font: boldFont, fontSize: 14)),
                          ],
                        ),
                        pw.Divider(thickness: 2, color: PdfColors.green),
                        pw.SizedBox(height: 4),
                        if (hasPassword) ...[
                          pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text('Pass: ', style: pw.TextStyle(font: boldFont, fontSize: 14)),
                              pw.Text(voucher.password, style: pw.TextStyle(font: boldFont, fontSize: 14)),
                            ],
                          ),
                          pw.Divider(thickness: 2, color: PdfColors.green),
                        ],
                        pw.Expanded(child: pw.SizedBox()),
                        pw.Center(
                          child: pw.Text(
                            'Jangan dibuang sebelum\\nmasa aktif habis',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: baseFont, fontSize: 6, color: PdfColors.black),
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
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Rp ', style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.green)),
                            pw.Text(voucher.formattedPrice.replaceAll('Rp', '').trim(), style: pw.TextStyle(font: boldFont, fontSize: 18, color: PdfColors.green)),
                          ],
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text('Expired: ${voucher.limitUptime.isEmpty ? "Unlimited" : voucher.limitUptime}', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                        pw.SizedBox(height: 2),
                        pw.Text('Masa Aktif: ${voucher.limitUptime.isEmpty ? "Unlimited" : voucher.limitUptime}', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                        pw.SizedBox(height: 2),
                        pw.Text('Unlimited Kuota', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                        pw.Expanded(child: pw.SizedBox()),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(4),
                          color: PdfColors.white,
                          child: pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: loginUrl,
                            width: 45,
                            height: 45,
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
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            color: PdfColors.green,
            child: pw.Text(
              'Login : $loginUrl',
              style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.white),
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
    required String loginUrl,
  }) {
    // A simplified thermal version of the premium design since thermal printers are black and white
    return _buildClassicThermalTicket(
      voucher: voucher,
      usableWidth: usableWidth,
      baseFont: baseFont,
      boldFont: boldFont,
      hotspotName: hotspotName,
    );
  }
"""

# Insert before the last brace
content = content.rstrip()
if content.endswith('}'):
    content = content[:-1] + builder_code + '\n}\n'

with open('lib/services/voucher_pdf_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("PATCH APPLIED")
