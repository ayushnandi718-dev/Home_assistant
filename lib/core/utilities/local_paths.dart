import 'dart:io';

/// Windows-native user paths without a path_provider plugin dependency.
abstract final class LocalPaths {
  /// Prefers the user's Documents folder, falling back to the profile root and
  /// finally the current directory. Callers still handle write failures.
  static Future<Directory> documents() async {
    final String? profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) {
      final Directory documents =
          Directory('$profile${Platform.pathSeparator}Documents');
      if (await documents.exists()) return documents;
      return Directory(profile);
    }
    return Directory.current;
  }
}
