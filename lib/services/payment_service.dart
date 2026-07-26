import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Handles integration with PayMongo for GCash / E-Wallet payments.
class PaymentService {
  // Use the LIVE key to accept real money, or TEST key for simulated payments.
  // static const String _secretKey = 'YOUR_PAYMONGO_LIVE_KEY_HERE';
  static const String _secretKey = 'YOUR_PAYMONGO_TEST_KEY_HERE';
  
  static const String _baseUrl = 'https://api.paymongo.com/v1';

  static Map<String, String> get _headers {
    final encodedKey = base64Encode(utf8.encode('$_secretKey:'));
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Basic $encodedKey',
    };
  }

  /// Creates a PayMongo Payment Link for the specified amount (in PHP).
  /// Returns a map containing the 'checkout_url' and the 'id' of the link.
  static Future<Map<String, String>> createPaymentLink({
    required double amount,
    required String description,
  }) async {
    // PayMongo expects amount in cents (e.g. 100 PHP = 10000)
    final amountInCents = (amount * 100).toInt();

    final response = await http.post(
      Uri.parse('$_baseUrl/links'),
      headers: _headers,
      body: jsonEncode({
        'data': {
          'attributes': {
            'amount': amountInCents,
            'description': description,
          }
        }
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final json = jsonDecode(response.body);
      final id = json['data']['id'] as String;
      final checkoutUrl = json['data']['attributes']['checkout_url'] as String;
      return {
        'id': id,
        'checkout_url': checkoutUrl,
      };
    } else {
      throw Exception('Failed to create payment link: ${response.body}');
    }
  }

  /// Checks if a given Payment Link ID has been paid on PayMongo.
  static Future<bool> isPaymentPaid(String linkId) async {
    if (linkId.trim().isEmpty) return false;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/links/$linkId'),
        headers: _headers,
      );

      debugPrint('PayMongo check status ${response.statusCode}: ${response.body}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final attributes = json['data']?['attributes'] as Map<String, dynamic>?;
        if (attributes != null) {
          final status = attributes['status'] as String?;
          if (status == 'paid') return true;

          final payments = attributes['payments'] as List<dynamic>?;
          if (payments != null && payments.isNotEmpty) {
            for (final item in payments) {
              if (item is Map<String, dynamic>) {
                final pStatus1 = item['attributes']?['status'] as String?;
                final pStatus2 = item['status'] as String?;
                final pData = item['data'] as Map<String, dynamic>?;
                final pStatus3 = pData?['attributes']?['status'] as String?;

                if (pStatus1 == 'paid' || pStatus2 == 'paid' || pStatus3 == 'paid') {
                  return true;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('PayMongo check error: $e');
    }

    return false;
  }
}
