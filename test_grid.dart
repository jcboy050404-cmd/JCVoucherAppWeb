void main() {
  double usableWidth = 571.0;
  double gridUsableH = 798.0;
  double colSpacing = 8.0;
  double rowSpacing = 8.0;
  double targetRatio = 185.0 / 125.0;

  for (int targetTickets in [21, 30, 40, 50, 60, 100]) {
    int bestCols = 1;
    int bestRows = 1;
    double bestDiff = double.infinity;

    for (int c = 1; c <= targetTickets; c++) {
      int r = (targetTickets / c).ceil();
      
      double cellW = (usableWidth - (c - 1) * colSpacing) / c;
      double cellH = (gridUsableH - (r - 1) * rowSpacing) / r;
      
      if (cellW <= 0 || cellH <= 0) continue;
      
      double ratio = cellW / cellH;
      double diff = (ratio - targetRatio).abs();
      
      if (diff < bestDiff) {
        bestDiff = diff;
        bestCols = c;
        bestRows = r;
      }
    }
    print('Target: $targetTickets -> Cols: $bestCols, Rows: $bestRows (Total slots: ${bestCols * bestRows})');
  }
}
