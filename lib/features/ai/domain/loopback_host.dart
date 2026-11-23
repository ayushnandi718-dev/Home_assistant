import 'package:aura_hub/core/platform/io_compat.dart';

/// Single source of truth for deciding whether an AI provider endpoint host is
/// loopback.
///
/// SECURITY: hostnames are never resolved. Only literal IP addresses are
/// parsed, so text such as `127.0.0.1.attacker.example` cannot be mistaken for
/// a loopback address and receive credentials over plain HTTP. DNS lookups are
/// deliberately avoided because resolution results can change between
/// validation and connection.
abstract final class LoopbackHost {
  /// True only for a literal IPv4 address in `127.0.0.0/8` or literal IPv6
  /// loopback `::1`.
  ///
  /// This is the strict rule used by adapters that must never permit a DNS
  /// lookup (native Ollama). IPv4-mapped IPv6 literals are rejected.
  static bool isLiteralLoopback(String host) {
    final InternetAddress? address =
        InternetAddress.tryParse(_stripBrackets(host.toLowerCase()));
    if (address == null) return false;
    if (address.type == InternetAddressType.IPv4) {
      final List<int> bytes = address.rawAddress;
      return bytes.length == 4 && bytes[0] == 127;
    }
    if (address.type == InternetAddressType.IPv6) {
      final List<int> bytes = address.rawAddress;
      return bytes.length == 16 &&
          bytes.take(15).every((int byte) => byte == 0) &&
          bytes[15] == 1;
    }
    return false;
  }

  /// True for a literal loopback address, plus the exact hostname `localhost`.
  ///
  /// `localhost` is retained for OpenAI-compatible endpoints because that is
  /// the established product behaviour; it is matched exactly and is never
  /// resolved. Adapters that require literal IPs use [isLiteralLoopback].
  static bool isLoopback(String host) {
    if (_stripBrackets(host.toLowerCase()) == 'localhost') return true;
    return isLiteralLoopback(host);
  }

  /// [Uri.host] may include brackets around an IPv6 literal on some SDKs.
  static String _stripBrackets(String host) {
    if (host.length >= 2 && host.startsWith('[') && host.endsWith(']')) {
      return host.substring(1, host.length - 1);
    }
    return host;
  }
}
