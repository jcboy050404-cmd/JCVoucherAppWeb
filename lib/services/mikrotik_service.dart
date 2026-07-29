import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/voucher.dart';
import '../models/user_profile.dart';
import '../models/router_script.dart';
import '../models/pppoe_user.dart';
import '../models/router_file.dart';

// ─── VoucherApp Script Encryption ────────────────────────────────────────────
// Secret key used to sign router flag script names with HMAC-SHA256.
// The email is never stored in plain text on the router.
//
// ⚠️ Loaded from .env at runtime. Like the Firebase secret, this is bundled
// inside the APK and therefore not truly secret — it only keeps the email
// out of Winbox/RouterOS listings and out of source control. See .env.
String get _kVoucherAppSecret {
  final secret = dotenv.env['VOUCHER_APP_SECRET'];
  if (secret == null || secret.isEmpty) {
    return 'va_fallback_secret';
  }
  return secret;
}

/// Returns a 16-character lowercase hex string derived from HMAC-SHA256
/// of [email] using [_kVoucherAppSecret].
/// This is used as the suffix for router script names so Gmail addresses
/// are never visible in Winbox or RouterOS script listings.
String _emailHash(String email) {
  final key = utf8.encode(_kVoucherAppSecret);
  final msg = utf8.encode(email.trim().toLowerCase());
  final hmac = Hmac(sha256, key);
  final digest = hmac.convert(msg);
  // Take first 16 hex chars (64-bit) — short enough for a script name,
  // long enough to be collision-resistant for this use-case.
  return digest.toString().substring(0, 16);
}

class MikrotikService {
  String host;
  int port;
  String username;
  String password;

  Socket? _socket;
  bool _connected = false;
  List<int> _buffer = [];
  int _readOffset = 0;
  Completer<void>? _operationLock;
  // Fired every time new data arrives on the socket — replaces polling loop
  Completer<void> _dataCompleter = Completer<void>();

  MikrotikService({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  bool get isConnected => _connected;

  int get _unreadBytes => _buffer.length - _readOffset;

  void _compactBuffer() {
    if (_readOffset > 0) {
      if (_readOffset >= _buffer.length) {
        _buffer.clear();
        _readOffset = 0;
      } else if (_readOffset > 4096) {
        _buffer.removeRange(0, _readOffset);
        _readOffset = 0;
      }
      // Do NOT reset _readOffset if buffer was not actually compacted.
    }
  }

  // ─── Command Lock & Auto-Connect Wrapper ─────────────────────────────────

  Future<T> _execute<T>(Future<T> Function() action) async {
    final prevLock = _operationLock;
    final myLock = Completer<void>();
    _operationLock = myLock;
    
    if (prevLock != null) {
      await prevLock.future;
    }
    try {
      await _ensureConnected();
      return await action();
    } catch (e) {
      // Force clean disconnect on error/timeout so next call reconnects fresh
      await disconnect();
      rethrow;
    } finally {
      if (_operationLock == myLock) {
        _operationLock = null;
      }
      myLock.complete();
    }
  }

  Future<void> _ensureConnected() async {
    if (!_connected || _socket == null) {
      await connect();
      await login();
    }
  }

  // ─── Low-level sentence encoding ───────────────────────────────────────────

  List<int> _encodeLength(int length) {
    if (length < 0x80) {
      return [length];
    } else if (length < 0x4000) {
      length |= 0x8000;
      return [(length >> 8) & 0xFF, length & 0xFF];
    } else if (length < 0x200000) {
      length |= 0xC00000;
      return [(length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF];
    } else if (length < 0x10000000) {
      length |= 0xE0000000;
      return [
        (length >> 24) & 0xFF,
        (length >> 16) & 0xFF,
        (length >> 8) & 0xFF,
        length & 0xFF,
      ];
    } else {
      return [
        0xF0,
        (length >> 24) & 0xFF,
        (length >> 16) & 0xFF,
        (length >> 8) & 0xFF,
        length & 0xFF,
      ];
    }
  }

  List<int> _encodeWord(String word) {
    final bytes = utf8.encode(word);
    return [..._encodeLength(bytes.length), ...bytes];
  }

  List<int> _encodeSentence(List<String> words) {
    final result = <int>[];
    for (final word in words) {
      result.addAll(_encodeWord(word));
    }
    result.add(0); // end-of-sentence
    return result;
  }

  // ─── Low-level sentence decoding ───────────────────────────────────────────

  int _decodeLength(List<int> data, int offset, List<int> outNewOffset) {
    final b = data[offset] & 0xFF;
    if ((b & 0x80) == 0) {
      outNewOffset[0] = offset + 1;
      return b;
    } else if ((b & 0xC0) == 0x80) {
      final len = ((b & 0x3F) << 8) | (data[offset + 1] & 0xFF);
      outNewOffset[0] = offset + 2;
      return len;
    } else if ((b & 0xE0) == 0xC0) {
      final len =
          ((b & 0x1F) << 16) |
          ((data[offset + 1] & 0xFF) << 8) |
          (data[offset + 2] & 0xFF);
      outNewOffset[0] = offset + 3;
      return len;
    } else if ((b & 0xF0) == 0xE0) {
      final len =
          ((b & 0x0F) << 24) |
          ((data[offset + 1] & 0xFF) << 16) |
          ((data[offset + 2] & 0xFF) << 8) |
          (data[offset + 3] & 0xFF);
      outNewOffset[0] = offset + 4;
      return len;
    } else {
      final len =
          ((data[offset + 1] & 0xFF) << 24) |
          ((data[offset + 2] & 0xFF) << 16) |
          ((data[offset + 3] & 0xFF) << 8) |
          (data[offset + 4] & 0xFF);
      outNewOffset[0] = offset + 5;
      return len;
    }
  }

  // ─── Connection Management ──────────────────────────────────────────────────

  Future<void> connect() async {
    await disconnect();
    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 8),
      );
      _connected = true;
      _buffer = [];
      _readOffset = 0;
      _dataCompleter = Completer<void>();

      _socket!.listen(
        (data) {
          _buffer.addAll(data);
          // Wake up any waiting _waitForBytes call
          if (!_dataCompleter.isCompleted) _dataCompleter.complete();
          _dataCompleter = Completer<void>();
        },
        onError: (e) {
          _connected = false;
          _buffer.clear();
          _readOffset = 0;
          if (!_dataCompleter.isCompleted) _dataCompleter.complete();
        },
        onDone: () {
          _connected = false;
          _buffer.clear();
          _readOffset = 0;
          if (!_dataCompleter.isCompleted) _dataCompleter.complete();
        },
      );
    } catch (e) {
      _connected = false;
      _buffer.clear();
      _readOffset = 0;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _connected = false;
    _buffer.clear();
    _readOffset = 0;
    try {
      await _socket?.close();
      _socket?.destroy();
    } catch (e) {
      debugPrint('MikrotikService: $e');
    }
    _socket = null;
    if (!_dataCompleter.isCompleted) _dataCompleter.complete();
    _dataCompleter = Completer<void>();
  }

  void dispose() {
    disconnect();
  }

  // ─── Send & Receive ────────────────────────────────────────────────────────

  void _send(List<String> words) {
    if (_socket == null || !_connected) {
      throw Exception('Socket is not connected');
    }
    final bytes = _encodeSentence(words);
    _socket!.add(bytes);
  }

  /// Wait until buffer has [n] bytes, with timeout.
  /// Uses a polling loop with Future.delayed to avoid Completer race conditions.
  Future<void> _waitForBytes(int n,
      {Duration timeout = const Duration(seconds: 8)}) async {
    final deadline = DateTime.now().add(timeout);
    while (_unreadBytes < n) {
      if (!_connected || _socket == null) {
        throw Exception('Socket connection lost');
      }
      if (DateTime.now().isAfter(deadline)) {
        _buffer.clear();
        _readOffset = 0;
        _connected = false;
        throw TimeoutException('RouterOS API response timeout');
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Read a full sentence (list of words) from buffer.
  Future<List<String>> _readSentence() async {
    final words = <String>[];
    while (true) {
      await _waitForBytes(1);

      final newOffset = [0];
      final wordLen = _decodeLength(_buffer, _readOffset, newOffset);
      final headerLen = newOffset[0] - _readOffset;

      if (wordLen == 0) {
        _readOffset += 1;
        break;
      }

      await _waitForBytes(headerLen + wordLen);

      final wordBytes = _buffer.sublist(
          _readOffset + headerLen, _readOffset + headerLen + wordLen);
      words.add(utf8.decode(wordBytes));
      _readOffset += headerLen + wordLen;
    }
    return words;
  }

  Future<List<List<String>>> _readResponse() async {
    final sentences = <List<String>>[];
    while (true) {
      final sentence = await _readSentence();
      sentences.add(sentence);
      if (sentence.isEmpty) continue;
      // RouterOS always sends !done at the end, even after a !trap.
      // Breaking on !trap leaves the subsequent !done in the socket buffer,
      // permanently corrupting the stream for the next command.
      if (sentence[0] == '!done' || sentence[0] == '!fatal') break;
    }
    _compactBuffer();
    return sentences;
  }

  Map<String, String>? _getTrapData(List<List<String>> response) {
    final trap = response.lastWhere((s) => s.isNotEmpty && s[0] == '!trap', orElse: () => const <String>[]);
    return trap.isEmpty ? null : _parseWords(trap);
  }
  Map<String, String> _parseWords(List<String> words) {
    final map = <String, String>{};
    for (final word in words) {
      if (word.startsWith('=')) {
        final eq = word.indexOf('=', 1);
        if (eq != -1) {
          final key = word.substring(1, eq);
          final val = word.substring(eq + 1);
          map[key] = val;
        } else {
          // Flag parameter without value (e.g. =disabled)
          final key = word.substring(1);
          map[key] = 'true';
        }
      }
    }
    return map;
  }

  // ─── Login ─────────────────────────────────────────────────────────────────

  Future<void> login() async {
    _send(['/login', '=name=$username', '=password=$password']);
    final response = await _readResponse();

    if (response.isNotEmpty) {
      final lastTag = response.last.isNotEmpty ? response.last[0] : '';
      if (lastTag == '!done') {
        final data = _parseWords(response.first);
        if (data.containsKey('ret')) {
          // RouterOS v6 MD5 challenge response
          final challenge = data['ret']!;
          final md5Response = _computeMd5Response(password, challenge);
          _send(['/login', '=name=$username', '=response=$md5Response']);
          final resp2 = await _readResponse();
          if (resp2.isNotEmpty && resp2.last.isNotEmpty && resp2.last[0] != '!done') {
            final errData = _getTrapData(resp2)!;
            throw Exception(errData['message'] ?? 'Invalid username or password');
          }
        }
        return; // Success!
      } else if (lastTag == '!trap') {
        // Fallback for legacy RouterOS v6 if sending password in 1st step was trapped
        try {
          _send(['/login']);
          final respLegacy = await _readResponse();
          if (respLegacy.isNotEmpty && respLegacy.first.isNotEmpty && respLegacy.first[0] == '!done') {
            final dataLegacy = _parseWords(respLegacy.first);
            if (dataLegacy.containsKey('ret')) {
              final challenge = dataLegacy['ret']!;
              final md5Response = _computeMd5Response(password, challenge);
              _send(['/login', '=name=$username', '=response=$md5Response']);
              final resp2 = await _readResponse();
              if (resp2.isNotEmpty && resp2.last.isNotEmpty && resp2.last[0] == '!done') {
                return; // Success via legacy login!
              }
            }
          }
        } catch (e) {
        debugPrint('MikrotikService: $e');
      }

        final data = _getTrapData(response)!;
        throw Exception(data['message'] ?? 'Invalid username or password');
      }
    }

    throw Exception('Login failed: unexpected response from router');
  }

  String _computeMd5Response(String pass, String challenge) {
    final challengeBytes = <int>[];
    for (var i = 0; i < challenge.length; i += 2) {
      challengeBytes.add(int.parse(challenge.substring(i, i + 2), radix: 16));
    }
    final input = Uint8List.fromList([
      0,
      ...utf8.encode(pass),
      ...challengeBytes,
    ]);
    final digest = md5.convert(input);
    return '00${digest.toString()}';
  }

  // ─── System Resource Telemetry ──────────────────────────────────────────────

  Future<List<String>> getInterfaces() async {
    return _execute(() async {
      _send(['/interface/print']);
      final response = await _readResponse();
      List<String> names = [];
      for (final block in response) {
        if (block.isNotEmpty && block[0] == '!re') {
          final props = _parseWords(block);
          if (props.containsKey('name')) {
            names.add(props['name']!);
          }
        }
      }
      return names;
    });
  }

  Future<Map<String, String>> getTraffic(String interface) async {
    return _execute(() async {
      _send(['/interface/monitor-traffic', '=interface=$interface', '=once=']);
      final response = await _readResponse();
      Map<String, String> result = {'rx-bits-per-second': '0', 'tx-bits-per-second': '0'};
      for (final block in response) {
        if (block.isNotEmpty && block[0] == '!re') {
          result = _parseWords(block);
        }
      }
      return result;
    });
  }

  Future<Map<String, String>> getResourceInfo() async {
    return _execute(() async {
      _send(['/system/resource/print']);
      final response = await _readResponse();
      final map = <String, String>{};
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        map.addAll(_parseWords(sentence));
      }
      return map;
    });
  }

  // ─── Hotspot User Commands ──────────────────────────────────────────────────

  Future<List<Voucher>> getVouchers({String? profile}) async {
    return _execute(() async {
      final words = ['/ip/hotspot/user/print'];
      if (profile != null && profile.isNotEmpty) {
        words.add('?profile=$profile');
      }
      _send(words);
      final response = await _readResponse();

      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to get vouchers');
      }

      final vouchers = <Voucher>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final data = _parseWords(sentence);
        vouchers.add(Voucher.fromMap(data));
      }
      return vouchers;
    });
  }

  Future<List<HotspotActive>> getActiveSessions([List<Voucher>? existingVouchers]) async {
    return _execute(() async {
      final userLimits = <String, String>{};
      final userComments = <String, String>{};
      Set<String>? knownUsernames;

      if (existingVouchers != null) {
        knownUsernames = {};
        for (final v in existingVouchers) {
          knownUsernames.add(v.name);
          if (v.name.isNotEmpty && v.limitBytes.isNotEmpty) {
            userLimits[v.name] = v.limitBytes;
          }
          if (v.name.isNotEmpty && v.comment.isNotEmpty) {
            userComments[v.name] = v.comment;
          }
        }
      } else {
        _send(['/ip/hotspot/user/print', '=.proplist=name,limit-bytes-total,limit-bytes-out,comment']);
        final userResponse = await _readResponse();
        final trapData = _getTrapData(userResponse);
        if (trapData != null) {
          final data = trapData;
          throw Exception(data['message'] ?? 'Failed to fetch user limits');
        }
        knownUsernames = {};
        for (final sentence in userResponse) {
          if (sentence.isEmpty || sentence[0] != '!re') continue;
          final map = _parseWords(sentence);
          final name = map['name'] ?? '';
          final limit = map['limit-bytes-total'] ?? map['limit-bytes-out'] ?? '';
          final comment = map['comment'] ?? '';
          if (name.isNotEmpty) {
            knownUsernames.add(name);
            if (limit.isNotEmpty) {
              userLimits[name] = limit;
            }
            if (comment.isNotEmpty) {
              userComments[name] = comment;
            }
          }
        }
      }

      _send(['/ip/hotspot/active/print']);
      final activeResponse = await _readResponse();
      
      final trapData = _getTrapData(activeResponse);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to get active sessions');
      }

      final sessions = <HotspotActive>[];
      for (final sentence in activeResponse) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final data = _parseWords(sentence);
        final username = data['user'] ?? '';

        if (!knownUsernames.contains(username)) {
          continue;
        }

        if (data['user'] != null && userLimits.containsKey(data['user'])) {
          data['limit-bytes-total'] = userLimits[data['user']]!;
        }
        if (data['user'] != null && userComments.containsKey(data['user'])) {
          data['comment'] = userComments[data['user']]!;
        }
        sessions.add(HotspotActive.fromMap(data));
      }
      return sessions;
    });
  }

  Future<List<String>> getProfiles() async {
    return _execute(() async {
      _send(['/ip/hotspot/user/profile/print']);
      final response = await _readResponse();

      final profiles = <String>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final data = _parseWords(sentence);
        if (data.containsKey('name')) {
          profiles.add(data['name']!);
        }
      }
      return profiles;
    });
  }

  Future<Voucher> addVoucher({
    required String name,
    required String password,
    required String profile,
    String? comment,
    String? limitUptime,
    String? limitBytes,
  }) async {
    return _execute(() async {
      final words = [
        '/ip/hotspot/user/add',
        '=name=$name',
        '=password=$password',
        '=profile=$profile',
      ];
      if (comment != null && comment.isNotEmpty) words.add('=comment=$comment');
      if (limitUptime != null && limitUptime.isNotEmpty) {
        words.add('=limit-uptime=$limitUptime');
      }
      if (limitBytes != null && limitBytes.isNotEmpty && limitBytes != '0') {
        words.add('=limit-bytes-total=$limitBytes');
      }

      _send(words);
      final response = await _readResponse();

      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to add voucher');
      }

      String newId = '';
      for (final sentence in response) {
        if (sentence.isNotEmpty && sentence[0] == '!done') {
          final data = _parseWords(sentence);
          newId = data['ret'] ?? '';
        }
      }

      return Voucher(
        id: newId,
        name: name,
        password: password,
        profile: profile,
        comment: comment ?? '',
        limitUptime: limitUptime ?? '',
        limitBytes: limitBytes ?? '',
      );
    });
  }

  Future<void> removeVoucher(String id) async {
    return _execute(() async {
      _send(['/ip/hotspot/user/remove', '=.id=$id']);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to remove voucher');
      }
    });
  }

  Future<void> removeVouchers(List<String> ids) async {
    // Run removals sequentially to avoid racing on the serialized socket lock.
    // The lock serialises them anyway; running concurrently only risks triggering
    // the reconnect path from multiple waiters simultaneously on error.
    for (final id in ids) {
      await removeVoucher(id);
    }
  }

  // ─── Profile Management ─────────────────────────────────────────────────────

  Future<List<UserProfile>> getFullProfiles() async {
    return _execute(() async {
      _send(['/ip/hotspot/user/profile/print']);
      final response = await _readResponse();

      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to get profiles');
      }

      final list = <UserProfile>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final data = _parseWords(sentence);
        list.add(UserProfile.fromMap(data));
      }
      return list;
    });
  }

  Future<void> addProfile({
    required String name,
    String? rateLimit,
    String? sharedUsers,
    String? onLogin,
    String? onLogout,
  }) async {
    return _execute(() async {
      final words = ['/ip/hotspot/user/profile/add', '=name=$name'];
      if (rateLimit != null && rateLimit.isNotEmpty) {
        words.add('=rate-limit=$rateLimit');
      }
      if (sharedUsers != null && sharedUsers.isNotEmpty) {
        words.add('=shared-users=$sharedUsers');
      }
      if (onLogin != null && onLogin.isNotEmpty) {
        words.add('=on-login=$onLogin');
      }
      if (onLogout != null && onLogout.isNotEmpty) {
        words.add('=on-logout=$onLogout');
      }

      _send(words);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to add profile');
      }
    });
  }

  Future<void> updateProfile({
    required String id,
    required String name,
    String? rateLimit,
    String? sharedUsers,
    String? onLogin,
    String? onLogout,
  }) async {
    return _execute(() async {
      final words = ['/ip/hotspot/user/profile/set', '=.id=$id', '=name=$name'];
      if (rateLimit != null) words.add('=rate-limit=$rateLimit');
      if (sharedUsers != null) words.add('=shared-users=$sharedUsers');
      if (onLogin != null) words.add('=on-login=$onLogin');
      if (onLogout != null) words.add('=on-logout=$onLogout');

      _send(words);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to update profile');
      }
    });
  }

  Future<void> removeProfile(String id) async {
    return _execute(() async {
      _send(['/ip/hotspot/user/profile/remove', '=.id=$id']);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to remove profile');
      }
    });
  }

  // ─── System Script Management ─────────────────────────────────────────────

  Future<List<RouterScript>> getScripts() async {
    return _execute(() async {
      _send(['/system/script/print']);
      final response = await _readResponse();

      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to get scripts');
      }

      final list = <RouterScript>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final data = _parseWords(sentence);
        list.add(RouterScript.fromMap(data));
      }
      return list;
    });
  }

  Future<void> addScript({
    required String name,
    required String source,
  }) async {
    return _execute(() async {
      _send(['/system/script/add', '=name=$name', '=source=$source']);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to add script');
      }
    });
  }

  Future<void> updateScript({
    required String id,
    required String name,
    required String source,
  }) async {
    return _execute(() async {
      _send(['/system/script/set', '=.id=$id', '=name=$name', '=source=$source']);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to update script');
      }
    });
  }

  Future<void> runScript(String nameOrId) async {
    return _execute(() async {
      // 1. Try running directly by name or ID using =number=
      _send(['/system/script/run', '=number=$nameOrId']);
      var response = await _readResponse();
      var trapData = _getTrapData(response);
      if (trapData == null) return; // Succeeded!

      // 2. If =number= failed, query /system/script to find the .id
      _send(['/system/script/print', '?name=$nameOrId']);
      response = await _readResponse();
      String? targetId;
      for (final sentence in response) {
        if (sentence.isNotEmpty && sentence[0] == '!re') {
          final data = _parseWords(sentence);
          targetId = data['.id'];
        }
      }

      // If we found the internal .id (e.g. *1), try running with =.id=
      if (targetId != null) {
        _send(['/system/script/run', '=.id=$targetId']);
        response = await _readResponse();
        trapData = _getTrapData(response);
        if (trapData == null) return; // Succeeded!
      }

      // 3. Fallback: try =number= with targetId
      if (targetId != null) {
        _send(['/system/script/run', '=number=$targetId']);
        response = await _readResponse();
        trapData = _getTrapData(response);
        if (trapData == null) return;
      }

      throw Exception(trapData['message'] ?? 'Failed to run script');
    });

  }

  Future<void> removeScript(String id) async {
    return _execute(() async {
      _send(['/system/script/remove', '=.id=$id']);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to remove script');
      }
    });
  }

  Future<void> removeActiveSession(String id) async {
    return _execute(() async {
      _send(['/ip/hotspot/active/remove', '=.id=$id']);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to disconnect session');
      }
    });
  }

  Future<void> activateValidity(String username) async {
    return _execute(() async {
      final scriptName = 'temp_activate_val_$username';
      final scriptSource = '''
:local user "$username";
:local uComment [/ip hotspot user get [find name=\$user] comment];
:local valPos [:find \$uComment "val:"];
:if ([:typeof \$valPos] = "num") do={
    :local valEnd [:find \$uComment " " \$valPos];
    :if ([:typeof \$valEnd] = "nil") do={ :set valEnd [:len \$uComment]; }
    :local valStr [:pick \$uComment (\$valPos+4) \$valEnd];
    :local interval "0s";
    :if ([:find \$valStr "d"] >= 0) do={ :set interval ([:pick \$valStr 0 [:find \$valStr "d"]] . "d"); }
    :if ([:find \$valStr "h"] >= 0) do={ :set interval ([:pick \$valStr 0 [:find \$valStr "h"]] . "h"); }
    :local schedName ("exp_" . \$user);
    :local onEvent ("/ip hotspot user set [find name=\\"" . \$user . "\\"] comment=([/ip hotspot user get [find name=\\"" . \$user . "\\"] comment] . \" expired\"); /ip hotspot user disable [find name=\\"" . \$user . "\\"]; /ip hotspot active remove [find user=\\"" . \$user . "\\"]; /system scheduler remove [find name=\\"" . \$schedName . "\\"];");
    /system scheduler add name=\$schedName interval=\$interval start-date=[/system clock get date] start-time=[/system clock get time] on-event=\$onEvent;
    :delay 1s;
    :local nextRun [/system scheduler get [find name=\$schedName] next-run];
    :local nextDate [:pick \$nextRun 0 [:find \$nextRun " "]];
    :local nextTime [:pick \$nextRun ([:find \$nextRun " "] + 1) [:len \$nextRun]];
    :local newComment ([:pick \$uComment 0 \$valPos] . "exp:" . \$nextDate . "/" . \$nextTime . " log:" . [/system clock get date] . "/" . [/system clock get time] . [:pick \$uComment \$valEnd [:len \$uComment]]);
    /ip hotspot user set [find name=\$user] comment=\$newComment;
}
''';
      // Add temp script
      _send(['/system/script/add', '=name=$scriptName', '=source=$scriptSource']);
      await _readResponse();

      // Run script
      _send(['/system/script/run', '=.id=$scriptName']);
      await _readResponse();

      // Remove script
      _send(['/system/script/remove', '=.id=$scriptName']);
      await _readResponse();
    });
  }

  Future<void> removeActiveSessionByUsername(String username) async {
    return _execute(() async {
      _send(['/ip/hotspot/active/print', '?user=$username']);
      final response = await _readResponse();
      
      final idsToRemove = <String>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final data = _parseWords(sentence);
        if (data.containsKey('.id')) {
          idsToRemove.add(data['.id']!);
        }
      }
      
      for (final id in idsToRemove) {
        _send(['/ip/hotspot/active/remove', '=.id=$id']);
        await _readResponse();
      }
    });
  }

  // ─── PPPoE Management API ──────────────────────────────────────────────────

  Future<List<PppoeUser>> getPppoeSecrets() async {
    return _execute(() async {
      _send(['/ppp/secret/print']);
      final response = await _readResponse();
      final users = <PppoeUser>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final map = _parseWords(sentence);
        users.add(PppoeUser.fromSecretMap(map));
      }
      return users;
    });
  }

  Future<List<PppoeActiveSession>> getPppoeActive() async {
    return _execute(() async {
      _send(['/ppp/active/print']);
      final response = await _readResponse();
      final sessions = <PppoeActiveSession>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final map = _parseWords(sentence);
        sessions.add(PppoeActiveSession.fromMap(map));
      }
      return sessions;
    });
  }

  Future<List<String>> getPppProfiles() async {
    return _execute(() async {
      _send(['/ppp/profile/print']);
      final response = await _readResponse();
      final profiles = <String>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final map = _parseWords(sentence);
        final name = map['name'];
        if (name != null && name.isNotEmpty) {
          profiles.add(name);
        }
      }
      if (profiles.isEmpty) profiles.add('default');
      return profiles;
    });
  }

  Future<void> addPppoeSecret({
    required String name,
    required String password,
    required String profile,
    String remoteAddress = '',
    String comment = '',
  }) async {
    return _execute(() async {
      final words = [
        '/ppp/secret/add',
        '=name=$name',
        '=password=$password',
        '=service=pppoe',
        '=profile=$profile',
      ];
      if (remoteAddress.isNotEmpty) words.add('=remote-address=$remoteAddress');
      if (comment.isNotEmpty) words.add('=comment=$comment');

      _send(words);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to create PPPoE client');
      }
    });
  }

  Future<void> updatePppoeSecret({
    required String id,
    required String name,
    required String password,
    required String profile,
    String remoteAddress = '',
    String comment = '',
  }) async {
    return _execute(() async {
      final words = [
        '/ppp/secret/set',
        '=.id=$id',
        '=name=$name',
        '=password=$password',
        '=profile=$profile',
        '=comment=$comment',
      ];
      // Only send remote-address when it has a valid value.
      // Sending an empty string causes MikroTik to return 'invalid arguments'.
      // Omitting it entirely leaves the existing router value unchanged.
      if (remoteAddress.isNotEmpty) {
        words.add('=remote-address=$remoteAddress');
      }
      _send(words);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to update PPPoE client');
      }
    });
  }

  Future<void> togglePppoeSecret(String id, bool disable, {String username = ''}) async {
    return _execute(() async {
      final cmd = disable ? '/ppp/secret/disable' : '/ppp/secret/enable';
      _send([cmd, '=.id=$id']);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to toggle PPPoE client');
      }

      // If disabling and username is provided, terminate any active sessions immediately
      if (disable && username.isNotEmpty) {
        try {
          _send(['/ppp/active/print']);
          final activeResp = await _readResponse();
          for (final sentence in activeResp) {
            if (sentence.isEmpty || sentence[0] != '!re') continue;
            final map = _parseWords(sentence);
            final activeName = map['name'] ?? '';
            final activeId = map['.id'];
            if (activeId != null && activeName.toLowerCase() == username.toLowerCase()) {
              _send(['/ppp/active/remove', '=.id=$activeId']);
              await _readResponse();
            }
          }
        } catch (e) {
        debugPrint('MikrotikService: $e');
      }
      }
    });
  }

  Future<void> removePppoeSecret(String id) async {
    return _execute(() async {
      _send(['/ppp/secret/remove', '=.id=$id']);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to remove PPPoE client');
      }
    });
  }

  Future<void> disconnectPppoeActive(String id) async {
    return _execute(() async {
      _send(['/ppp/active/remove', '=.id=$id']);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to disconnect PPPoE session');
      }
    });
  }

  // ─── Payment Redirect API ──────────────────────────────────────────────────

  /// Enable MikroTik web proxy on the given port (default 8080).
  /// [cacheAdmin] sets the cache-administrator text shown on the proxy error page.
  /// On RouterOS v7, this is the ONLY way to show a custom message on the deny page.
  Future<void> setWebProxyEnabled({int port = 8080, String cacheAdmin = 'webmaster'}) async {
    return _execute(() async {
      final commands = [
        ['/ip/proxy/set', '=enabled=yes', '=port=$port', '=cache-administrator=$cacheAdmin'],
        ['/ip/proxy/set', '=enabled=yes', '=port=$port'],
        ['/ip/web-proxy/set', '=enabled=yes', '=port=$port', '=cache-administrator=$cacheAdmin'],
        ['/ip/web-proxy/set', '=enabled=yes', '=port=$port'],
        ['/ip/proxy/set', '=enabled=yes'],
        ['/ip/web-proxy/set', '=enabled=yes'],
      ];

      for (final cmd in commands) {
        _send(cmd);
        final resp = await _readResponse();
        if (_getTrapData(resp) == null) {
          return; // Successfully enabled!
        }
      }

      throw Exception(
        'Web Proxy is currently disabled on your MikroTik router.\n\n'
        'To enable it in Winbox:\n'
        '1. Go to IP -> Proxy\n'
        '2. Check "Enabled"\n'
        '3. Set Port to 8080\n'
        '4. Click Apply / OK',
      );
    });
  }

  /// Add a firewall NAT redirect rule for the payment guard.
  /// Uses chain=dstnat to intercept HTTP port 80 before masquerade.
  Future<void> addPaymentNatRule({
    required String addressList,
    required int proxyPort,
    String comment = 'pppoe-payment-guard',
  }) async {
    return _execute(() async {
      _send([
        '/ip/firewall/nat/add',
        '=chain=dstnat',
        '=src-address-list=$addressList',
        '=protocol=tcp',
        '=dst-port=80',
        '=action=redirect',
        '=to-ports=$proxyPort',
        '=comment=$comment',
      ]);
      final response = await _readResponse();
      final trapData = _getTrapData(response);
      if (trapData != null) {
        final data = trapData;
        throw Exception(data['message'] ?? 'Failed to add NAT rule');
      }
    });
  }

  /// Add firewall filter to mark overdue traffic so FastTrack doesn't bypass the NAT redirect.
  Future<void> addPaymentFilterRule({
    required String addressList,
    String comment = 'pppoe-payment-guard',
  }) async {
    return _execute(() async {
      // Add a FORWARD rule to passthrough (accept) the overdue src traffic,
      // ensuring it is NOT fast-tracked and the dstnat redirect takes effect.
      _send([
        '/ip/firewall/filter/add',
        '=chain=forward',
        '=src-address-list=$addressList',
        '=action=passthrough',
        '=comment=$comment',
      ]);
      final resp = await _readResponse();
      // fallback: if passthrough not supported, use accept
      if (_getTrapData(resp) != null) {
        _send([
          '/ip/firewall/filter/add',
          '=chain=forward',
          '=src-address-list=$addressList',
          '=action=accept',
          '=comment=$comment',
        ]);
        await _readResponse();
      }
    });
  }

  /// Remove firewall filter rules with the given comment.
  Future<void> removeFilterRulesByComment(String comment) async {
    return _execute(() async {
      _send(['/ip/firewall/filter/print']);
      final response = await _readResponse();
      final ids = <String>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final map = _parseWords(sentence);
        if ((map['comment'] ?? '') == comment) {
          final id = map['.id'];
          if (id != null) ids.add(id);
        }
      }
      for (final id in ids) {
        _send(['/ip/firewall/filter/remove', '=.id=$id']);
        await _readResponse();
      }
    });
  }

  /// Add a web proxy access deny rule.
  /// RouterOS v6 supports deny-message for custom HTML.
  /// RouterOS v7 does NOT support deny-message — falls back to plain action=deny.
  Future<void> addWebProxyDenyRule({
    required String denyMessage,
    String comment = 'pppoe-payment-guard',
  }) async {
    return _execute(() async {
      // Try proxy access paths with deny-message first (works on v6)
      final accessPaths = ['/ip/web-proxy/access', '/ip/proxy/access'];
      for (final p in accessPaths) {
        _send([
          '$p/add',
          '=action=deny',
          '=deny-message=$denyMessage',
          '=comment=$comment',
        ]);
        final resp = await _readResponse();
        if (resp.isEmpty || resp.last.isEmpty || resp.last[0] != '!trap') {
          return; // success with deny-message (v6)
        }
      }

      // Fallback: RouterOS v7 doesn't support deny-message.
      // Add plain deny rule (shows default "ERROR: Forbidden" page).
      for (final p in accessPaths) {
        _send([
          '$p/add',
          '=action=deny',
          '=comment=$comment',
        ]);
        final resp = await _readResponse();
        if (resp.isEmpty || resp.last.isEmpty || resp.last[0] != '!trap') {
          return; // success without deny-message (v7)
        }
      }

      throw Exception('Could not add proxy deny rule. Enable proxy in Winbox: IP → Proxy.');
    });
  }

  /// Add an IP to a firewall address-list.
  Future<void> addAddressListEntry({
    required String list,
    required String address,
    String comment = 'pppoe-auto',
  }) async {
    return _execute(() async {
      _send([
        '/ip/firewall/address-list/add',
        '=list=$list',
        '=address=$address',
        '=comment=$comment',
      ]);
      await _readResponse();
    });
  }

  /// Remove all entries from a specific address-list with a given comment tag.
  Future<void> clearAddressList({
    required String list,
    String comment = 'pppoe-auto',
  }) async {
    return _execute(() async {
      _send(['/ip/firewall/address-list/print', '?list=$list', '?comment=$comment']);
      final response = await _readResponse();
      final ids = <String>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final map = _parseWords(sentence);
        final id = map['.id'];
        if (id != null) ids.add(id);
      }
      for (final id in ids) {
        _send(['/ip/firewall/address-list/remove', '=.id=$id']);
        await _readResponse();
      }
    });
  }

  /// Get current entries in an address-list.
  Future<List<Map<String, String>>> getAddressListEntries(String list) async {
    return _execute(() async {
      _send(['/ip/firewall/address-list/print', '?list=$list']);
      final response = await _readResponse();
      final entries = <Map<String, String>>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        entries.add(_parseWords(sentence));
      }
      return entries;
    });
  }

  /// Check if a NAT rule with a given comment already exists.
  Future<bool> isNatRuleInstalled(String comment) async {
    return _execute(() async {
      _send(['/ip/firewall/nat/print']);
      final response = await _readResponse();
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final map = _parseWords(sentence);
        if ((map['comment'] ?? '') == comment) return true;
      }
      return false;
    });
  }

  /// Remove all NAT rules with the given comment.
  Future<void> removeNatRulesByComment(String comment) async {
    return _execute(() async {
      _send(['/ip/firewall/nat/print']);
      final response = await _readResponse();
      final ids = <String>[];
      for (final sentence in response) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final map = _parseWords(sentence);
        if ((map['comment'] ?? '') == comment) {
          final id = map['.id'];
          if (id != null) ids.add(id);
        }
      }
      for (final id in ids) {
        _send(['/ip/firewall/nat/remove', '=.id=$id']);
        await _readResponse();
      }
    });
  }

  /// Remove all web-proxy access rules with the given comment.
  Future<void> removeWebProxyRulesByComment(String comment) async {
    return _execute(() async {
      // 1. Try /ip/web-proxy/access/print
      _send(['/ip/web-proxy/access/print']);
      var response = await _readResponse();
      var pathPrefix = '/ip/web-proxy/access';

      if (_getTrapData(response) != null) {
        // Fallback to /ip/proxy/access/print for RouterOS v7
        _send(['/ip/proxy/access/print']);
        response = await _readResponse();
        pathPrefix = '/ip/proxy/access';
      }

      if (_getTrapData(response) == null) {
        final ids = <String>[];
        for (final sentence in response) {
          if (sentence.isEmpty || sentence[0] != '!re') continue;
          final map = _parseWords(sentence);
          if ((map['comment'] ?? '') == comment) {
            final id = map['.id'];
            if (id != null) ids.add(id);
          }
        }
        for (final id in ids) {
          _send(['$pathPrefix/remove', '=.id=$id']);
          await _readResponse();
        }
      }
    });
  }

  /// Sync overdue PPPoE clients' IPs to the address-list.
  /// [timeout] optional duration string (e.g. '00:05:00' for 5 minutes) after which RouterOS auto-removes the IP and restores internet.
  Future<int> syncOverdueAddressList({
    required String list,
    required List<String> overdueNames,
    String? timeout = '',
  }) async {
    return _execute(() async {
      final overdueSet = {for (var n in overdueNames) n.toLowerCase()};
      final targetIps = <String>{};

      // 1. Get IPs from active sessions
      _send(['/ppp/active/print']);
      final activeResp = await _readResponse();
      for (final sentence in activeResp) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final map = _parseWords(sentence);
        final name = (map['name'] ?? '').toLowerCase();
        final address = map['address'] ?? '';
        if (address.isNotEmpty && overdueSet.contains(name)) {
          targetIps.add(address);
        }
      }

      // 2. Get static remoteAddress from secrets (if configured)
      _send(['/ppp/secret/print']);
      final secretResp = await _readResponse();
      for (final sentence in secretResp) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final map = _parseWords(sentence);
        final name = (map['name'] ?? '').toLowerCase();
        final remote = map['remote-address'] ?? '';
        if (remote.isNotEmpty && remote != '0.0.0.0' && overdueSet.contains(name)) {
          targetIps.add(remote);
        }
      }

      // 3. Clear old auto-entries
      _send(['/ip/firewall/address-list/print', '?list=$list', '?comment=pppoe-auto']);
      final existing = await _readResponse();
      for (final sentence in existing) {
        if (sentence.isEmpty || sentence[0] != '!re') continue;
        final map = _parseWords(sentence);
        final id = map['.id'];
        if (id != null) {
          _send(['/ip/firewall/address-list/remove', '=.id=$id']);
          await _readResponse();
        }
      }

      // 4. Add current overdue IPs (with optional timeout)
      for (final ip in targetIps) {
        final words = [
          '/ip/firewall/address-list/add',
          '=list=$list',
          '=address=$ip',
          '=comment=pppoe-auto',
        ];
        if (timeout != null && timeout.isNotEmpty) {
          words.add('=timeout=$timeout');
        }
        _send(words);
        await _readResponse();
      }

      // Write to MikroTik RouterOS System Log
      try {
        final timeInfo = (timeout != null && timeout.isNotEmpty) ? ' (Timeout: $timeout)' : '';
        _send([
          '/log/info',
          '=message=PPPoE Guard: Synced ${targetIps.length} overdue client IP(s) to address-list "$list"$timeInfo',
        ]);
        await _readResponse();
      } catch (e) {
        debugPrint('MikrotikService: $e');
      }

      return targetIps.length;
    });
  }

  /// Write an entry to MikroTik RouterOS System Log (/log info).
  Future<void> addLogMessage(String message) async {
    return _execute(() async {
      _send(['/log/info', '=message=$message']);
      await _readResponse();
    });
  }

  /// Checks if ANY trial flag exists on the connected MikroTik router.
  /// To prevent the loophole of using multiple Gmail accounts on the same router,
  /// this now checks if ANY script starting with 'va_trial_' exists.
  Future<bool> checkRouterTrialFlag(String email) async {
    return _execute(() async {
      try {
        _send(['/system/script/print']);
        final response = await _readResponse();
        for (final sentence in response) {
          if (sentence.isNotEmpty && sentence[0] == '!re') {
            final data = _parseWords(sentence);
            final scriptName = data['name'] ?? '';
            if (scriptName.startsWith('va_trial_')) {
              return true;
            }
          }
        }
      } catch (e) {
        debugPrint('MikrotikService: $e');
      }
      return false;
    });
  }

  /// Writes an encrypted trial flag for [email] on the connected MikroTik router.
  /// The script name is an HMAC-SHA256 hash — no plain email in Winbox.
  Future<void> setRouterTrialFlag(String email) async {
    return _execute(() async {
      try {
        final hash = _emailHash(email);
        // comment is also hashed — no email visible in RouterOS
        _send([
          '/system/script/add',
          '=name=va_trial_$hash',
          '=source=# VoucherApp Trial Flag',
          '=comment=va_trial_$hash',
        ]);
        await _readResponse();
      } catch (e) {
        debugPrint('MikrotikService: $e');
      }
    });
  }

  /// Removes ALL trial script flags (`va_trial_*`) from the connected MikroTik router.
  /// This ensures that if the admin resets the trial, the router is fully cleared.
  Future<void> removeRouterTrialFlag(String email) async {
    return _execute(() async {
      try {
        _send(['/system/script/print']);
        final response = await _readResponse();
        final idsToRemove = <String>[];
        for (final sentence in response) {
          if (sentence.isNotEmpty && sentence[0] == '!re') {
            final data = _parseWords(sentence);
            final name = data['name'] ?? '';
            if (name.startsWith('va_trial_')) {
              final id = data['.id'];
              if (id != null) {
                idsToRemove.add(id);
              }
            }
          }
        }
        for (final id in idsToRemove) {
          _send(['/system/script/remove', '=.id=$id']);
          await _readResponse();
        }
      } catch (e) {
        debugPrint('MikrotikService: $e');
      }
    });
  }

  /// Checks if a PRO unlock flag for [email] exists on the connected MikroTik router.
  /// Script name is HMAC-SHA256 hashed — email is never stored in plain text.
  Future<bool> checkRouterProFlag(String email) async {
    return _execute(() async {
      try {
        final hash = _emailHash(email);
        final targetName = 'va_pro_$hash';
        _send(['/system/script/print']);
        final response = await _readResponse();
        for (final sentence in response) {
          if (sentence.isNotEmpty && sentence[0] == '!re') {
            final data = _parseWords(sentence);
            if (data['name'] == targetName) {
              return true;
            }
          }
        }
      } catch (e) {
        debugPrint('MikrotikService: $e');
      }
      return false;
    });
  }

  /// Writes an encrypted PRO unlock flag for [email] on the connected MikroTik router.
  /// The script name is an HMAC-SHA256 hash — no plain email in Winbox.
  Future<void> setRouterProFlag(String email) async {
    return _execute(() async {
      try {
        final hash = _emailHash(email);
        // comment is also hashed — no email visible in RouterOS
        _send([
          '/system/script/add',
          '=name=va_pro_$hash',
          '=source=# VoucherApp PRO Flag',
          '=comment=va_pro_$hash',
        ]);
        await _readResponse();
      } catch (e) {
        debugPrint('MikrotikService: $e');
      }
    });
  }

  /// Removes a PRO script flag (`va_pro_$hash`) from the connected MikroTik router.
  Future<void> removeRouterProFlag(String email) async {
    return _execute(() async {
      try {
        final hash = _emailHash(email);
        final targetName = 'va_pro_$hash';
        _send(['/system/script/print']);
        final response = await _readResponse();
        for (final sentence in response) {
          if (sentence.isNotEmpty && sentence[0] == '!re') {
            final data = _parseWords(sentence);
            if (data['name'] == targetName) {
              final id = data['.id'];
              if (id != null) {
                _send(['/system/script/remove', '=.id=$id']);
                await _readResponse();
              }
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('MikrotikService: $e');
      }
    });
  }

  /// Removes all PRO script flags (`va_pro_*`) from the connected MikroTik router.
  Future<void> removeAllProFlags() async {
    return _execute(() async {
      try {
        _send(['/system/script/print']);
        final response = await _readResponse();
        final idsToRemove = <String>[];
        for (final sentence in response) {
          if (sentence.isNotEmpty && sentence[0] == '!re') {
            final data = _parseWords(sentence);
            final name = data['name'] ?? '';
            final id = data['.id'];
            if (name.startsWith('va_pro_') && id != null) {
              idsToRemove.add(id);
            }
          }
        }
        for (final id in idsToRemove) {
          _send(['/system/script/remove', '=.id=$id']);
          await _readResponse();
        }
      } catch (e) {
        debugPrint('MikrotikService: $e');
      }
    });
  }

  // ─── DDNS (IP Cloud) Management ──────────────────────────────────────────

  Future<Map<String, String>> getCloudStatus() async {
    return _execute(() async {
      _send(['/ip/cloud/print']);
      final reply = await _readResponse();
      final trap = _getTrapData(reply);
      if (trap != null) return {};
      final reTag = reply.firstWhere((s) => s.isNotEmpty && s[0] == '!re', orElse: () => <String>[]);
      if (reTag.isNotEmpty) {
        return _parseWords(reTag);
      }
      return {};
    });
  }

  Future<void> setDdnsEnabled(bool enabled) async {
    return _execute(() async {
      _send([
        '/ip/cloud/set',
        '=ddns-enabled=${enabled ? "yes" : "no"}'
      ]);
      final reply = await _readResponse();
      final trap = _getTrapData(reply);
      if (trap != null) {
        final msg = trap['message']?.toLowerCase() ?? '';
        if (!enabled && msg.contains('auto')) {
          _send([
            '/ip/cloud/set',
            '=ddns-enabled=auto'
          ]);
          final retryReply = await _readResponse();
          final retryTrap = _getTrapData(retryReply);
          if (retryTrap != null) {
            throw Exception(retryTrap['message'] ?? 'Failed to update DDNS');
          }
          return;
        }
        throw Exception(trap['message'] ?? 'Failed to update DDNS');
      }
    });
  }

  // ─── WebFig (www) Service Management ─────────────────────────────────────

  Future<Map<String, String>> getWebFigStatus() async {
    return _execute(() async {
      _send(['/ip/service/print', '=?name=www']);
      final reply = await _readResponse();
      final trap = _getTrapData(reply);
      if (trap != null) return {};
      final reTag = reply.firstWhere((s) => s.isNotEmpty && s[0] == '!re', orElse: () => <String>[]);
      if (reTag.isNotEmpty) {
        return _parseWords(reTag);
      }
      return {};
    });
  }

  Future<void> setWebFigEnabled(bool enabled) async {
    return _execute(() async {
      _send([
        '/ip/service/set',
        '=disabled=${enabled ? "no" : "yes"}',
        '=.id=www'
      ]);
      final reply = await _readResponse();
      final trap = _getTrapData(reply);
      if (trap != null) {
        throw Exception(trap['message'] ?? 'Failed to update WebFig service');
      }
    });
  }

  Future<void> setWebFigPort(String port) async {
    return _execute(() async {
      _send([
        '/ip/service/set',
        '=port=$port',
        '=.id=www'
      ]);
      final reply = await _readResponse();
      final trap = _getTrapData(reply);
      if (trap != null) {
        throw Exception(trap['message'] ?? 'Failed to update WebFig port');
      }
    });
  }
  // ─── File Management (RouterOS) ───────────────────────────────────────────

  Future<List<RouterFile>> getFiles({String? directory}) async {
    return _execute(() async {
      final cmd = ['/file/print'];
      _send(cmd);
      final response = await _readResponse();
      final trap = _getTrapData(response);
      if (trap != null) {
        throw Exception(trap['message'] ?? 'Failed to get files');
      }

      final files = <RouterFile>[];
      for (final sentence in response) {
        if (sentence.isNotEmpty && sentence[0] == '!re') {
          final data = _parseWords(sentence);
          final rf = RouterFile.fromMap(data);
          // Simple client-side filtering if directory is specified
          if (directory != null && directory.isNotEmpty) {
            if (rf.name.startsWith(directory) && rf.name != directory) {
              files.add(rf);
            }
          } else {
            files.add(rf);
          }
        }
      }
      return files;
    });
  }

  Future<String> getFileContents(String id) async {
    return _execute(() async {
      _send(['/file/get', '=.id=$id', '=value-name=contents']);
      final response = await _readResponse();
      final trap = _getTrapData(response);
      if (trap != null) {
        throw Exception(trap['message'] ?? 'Failed to get file contents');
      }
      
      final reTag = response.firstWhere((s) => s.isNotEmpty && s[0] == '!re', orElse: () => <String>[]);
      if (reTag.isNotEmpty) {
        final data = _parseWords(reTag);
        return data['ret'] ?? '';
      }
      return '';
    });
  }

  Future<void> setFileContents(String id, String content) async {
    return _execute(() async {
      _send(['/file/set', '=.id=$id', '=contents=$content']);
      final response = await _readResponse();
      final trap = _getTrapData(response);
      if (trap != null) {
        throw Exception(trap['message'] ?? 'Failed to set file contents');
      }
    });
  }

  Future<void> deleteFile(String id) async {
    return _execute(() async {
      _send(['/file/remove', '=.id=$id']);
      final response = await _readResponse();
      final trap = _getTrapData(response);
      if (trap != null) {
        throw Exception(trap['message'] ?? 'Failed to delete file');
      }
    });
  }
}

