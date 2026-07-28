import 'package:flutter_test/flutter_test.dart';
import 'package:voucherapps/models/voucher.dart';

void main() {
  group('Voucher Sales Bug Fix Tests', () {
    test('price parsing supports P: tags, symbols, and numeric comments', () {
      final v1 = Voucher(id: '1', name: 'v1', password: '1', profile: 'def', comment: 'vc- P:50 Date:2026-07-28');
      expect(v1.price, equals(50.0));

      final v2 = Voucher(id: '2', name: 'v2', password: '2', profile: 'def', comment: '₱100 Date:2026-07-28');
      expect(v2.price, equals(100.0));

      final v3 = Voucher(id: '3', name: 'v3', password: '3', profile: 'def', comment: 'price: 25 Date:2026-07-28');
      expect(v3.price, equals(25.0));

      final v4 = Voucher(id: '4', name: 'v4', password: '4', profile: 'def', comment: '15');
      expect(v4.price, equals(15.0));
    });

    test('isUsed accurately identifies used/activated vouchers', () {
      final unused = Voucher(id: '1', name: 'v1', password: '1', profile: 'def', comment: 'P:50 Date:2026-07-28');
      expect(unused.isUsed, isFalse);

      final usedBytes = Voucher(id: '2', name: 'v2', password: '2', profile: 'def', bytesIn: '1024', comment: 'P:50 Date:2026-07-28');
      expect(usedBytes.isUsed, isTrue);

      final usedExp = Voucher(id: '3', name: 'v3', password: '3', profile: 'def', comment: 'P:50 exp:2026-07-28 Date:2026-07-28');
      expect(usedExp.isUsed, isTrue);
    });

    test('createdDate accurately parses Date: tag, exp: tag, and createdAt', () {
      final v1 = Voucher(id: '1', name: 'v1', password: '1', profile: 'def', comment: 'P:50 Date:2026-07-28');
      expect(v1.createdDate, equals(DateTime(2026, 7, 28)));

      final v2 = Voucher(id: '2', name: 'v2', password: '2', profile: 'def', comment: 'P:50 exp:2026-07-28');
      expect(v2.createdDate, equals(DateTime(2026, 7, 28)));

      final v3 = Voucher(id: '3', name: 'v3', password: '3', profile: 'def', createdAt: '2026-07-28T10:00:00.000');
      expect(v3.createdDate, equals(DateTime(2026, 7, 28, 10, 0, 0)));

      final v4 = Voucher(id: '4', name: 'v4', password: '4', profile: 'def', comment: 'exp:jul/28/2026/14:00:00');
      expect(v4.createdDate, equals(DateTime(2026, 7, 28)));
    });

    test('today sales calculation accurately filters today used vouchers', () {
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final list = [
        Voucher(id: '1', name: 'v1', password: '1', profile: 'def', bytesIn: '500', comment: 'P:50 Date:$todayStr'),
        Voucher(id: '2', name: 'v2', password: '2', profile: 'def', bytesIn: '0', comment: 'P:50 Date:$todayStr'), // unused
        Voucher(id: '3', name: 'v3', password: '3', profile: 'def', bytesIn: '500', comment: 'P:30 Date:2025-01-01'), // old date
      ];

      final todaySales = list.where((v) {
        if (!v.isUsed) return false;
        final cd = v.createdDate;
        if (cd == null) return false;
        return cd.year == now.year && cd.month == now.month && cd.day == now.day;
      }).fold(0.0, (sum, v) => sum + v.price);

      expect(todaySales, equals(50.0));
    });
  });
}
