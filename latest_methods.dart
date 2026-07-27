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
      var format = (paperSize == VoucherPaperSize.custom && customFormat != null) ? customFormat : paperSize.pdfFormat;
      const int cols = 3; // Wider tickets for custom template
      const double cellH = 100.0;
      const double headerHeight = 16.0;
      const double headerSpacing = 4.0;
      const double colSpacing = 6.0;
      const double rowSpacing = 6.0;

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

static pw.Widget _buildClassicThermalTicket({
    required Voucher voucher,
    required double usableWidth,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
  }) {
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
            pw.Text(hotspotName, style: pw.TextStyle(font: boldFont, fontSize: 14)),
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
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1, style: pw.BorderStyle.dashed),
            pw.SizedBox(height: 4),
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
            pw.Divider(thickness: 1, style: pw.BorderStyle.dashed),
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
  }) async {

static pw.Widget _buildPremiumSheetTicket({
    required Voucher voucher,
    required double width,
    required double height,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
    required String loginUrl,
    required String footerNote,
  }) {

static pw.Widget _buildPremiumThermalTicket({
    required Voucher voucher,
    required double usableWidth,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required String hotspotName,
  }) {
    // Thermal representation for premium design
    return _buildClassicThermalTicket(
      voucher: voucher,
      usableWidth: usableWidth,
      baseFont: baseFont,
      boldFont: boldFont,
      hotspotName: hotspotName,
    );
  }

static pw.Widget _buildPremiumDarkSheetTicket({
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
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    final String priceText = voucher.formattedPrice;

    return pw.Container(
      width: width,
      height: height,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: primaryColor, width: 2),
      ),
      child: pw.Column(
        children: [
          pw.Expanded(
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 55,
                  child: pw.Container(
                    color: PdfColors.grey900,
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
                                  pw.Text(hotspotName.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.white)),
                                  pw.Text('INTERNET HOTSPOT SERVICE', style: pw.TextStyle(font: baseFont, fontSize: 3.5, color: PdfColors.grey400)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Divider(thickness: 1, color: PdfColors.grey700),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('User: ', style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.white)),
                            pw.Text(voucher.name, style: pw.TextStyle(font: boldFont, fontSize: 11, color: primaryColor)),
                          ],
                        ),
                        pw.Divider(thickness: 2, color: primaryColor),
                        pw.SizedBox(height: 2),
                        if (hasPassword) ...[
                          pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text('Pass: ', style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.white)),
                              pw.Text(voucher.password, style: pw.TextStyle(font: boldFont, fontSize: 11, color: primaryColor)),
                            ],
                          ),
                          pw.Divider(thickness: 2, color: primaryColor),
                        ],
                        pw.Expanded(child: pw.SizedBox()),
                        pw.Center(
                          child: pw.Text(
                            footerNote,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: baseFont, fontSize: 5, color: PdfColors.grey300),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: 45,
                  child: pw.Container(
                    color: PdfColors.black,
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
                        pw.Text('Validity: ${voucher.limitUptime.isEmpty ? "Unlimited" : voucher.limitUptime}', style: pw.TextStyle(font: boldFont, fontSize: 6, color: PdfColors.white)),
                        pw.SizedBox(height: 2),
                        pw.Text('Time: ${voucher.limitUptime.isEmpty ? "Unlimited" : voucher.limitUptime}', style: pw.TextStyle(font: boldFont, fontSize: 6, color: PdfColors.white)),
                        pw.SizedBox(height: 2),
                        pw.Text(_formatDataLimit(voucher.limitBytes), style: pw.TextStyle(font: boldFont, fontSize: 6, color: PdfColors.white)),
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
            child: pw.Text(
              'Login : $loginUrl',
              style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.white),
            ),
          ),
        ],
      ),
    );
  }

static pw.Widget _buildPremiumAccentSheetTicket({
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
  }) {
    final bool hasPassword = voucher.password.isNotEmpty && voucher.password != voucher.name;
    final String priceText = voucher.formattedPrice;

    return pw.Container(
      width: width,
      height: height,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: primaryColor, width: 2),
      ),
      child: pw.Column(
        children: [
          pw.Expanded(
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 55,
                  child: pw.Container(
                    color: primaryColor,
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
                                  color: PdfColors.white,
                                  shape: pw.BoxShape.circle,
                                ),
                              ),
                            pw.SizedBox(width: 4),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(hotspotName.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.white)),
                                  pw.Text('INTERNET HOTSPOT SERVICE', style: pw.TextStyle(font: baseFont, fontSize: 3.5, color: PdfColors.white)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Divider(thickness: 1, color: PdfColors.white),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('User: ', style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.white)),
                            pw.Text(voucher.name, style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.white)),
                          ],
                        ),
                        pw.Divider(thickness: 2, color: PdfColors.white),
                        pw.SizedBox(height: 2),
                        if (hasPassword) ...[
                          pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text('Pass: ', style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.white)),
                              pw.Text(voucher.password, style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.white)),
                            ],
                          ),
                          pw.Divider(thickness: 2, color: PdfColors.white),
                        ],
                        pw.Expanded(child: pw.SizedBox()),
                        pw.Center(
                          child: pw.Text(
                            footerNote,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: baseFont, fontSize: 5, color: PdfColors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: 45,
                  child: pw.Container(
                    color: PdfColors.white,
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
                        pw.Text('Validity: ${voucher.limitUptime.isEmpty ? "Unlimited" : voucher.limitUptime}', style: pw.TextStyle(font: boldFont, fontSize: 6, color: PdfColors.black)),
                        pw.SizedBox(height: 2),
                        pw.Text('Time: ${voucher.limitUptime.isEmpty ? "Unlimited" : voucher.limitUptime}', style: pw.TextStyle(font: boldFont, fontSize: 6, color: PdfColors.black)),
                        pw.SizedBox(height: 2),
                        pw.Text(_formatDataLimit(voucher.limitBytes), style: pw.TextStyle(font: boldFont, fontSize: 6, color: PdfColors.black)),
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
            color: PdfColors.black,
            child: pw.Text(
              'Login : $loginUrl',
              style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.white),
            ),
          ),
        ],
      ),
    );
  }