import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider<Object>? avatarImageProvider(String? path) {
  if (path == null || path.isEmpty) return null;
  final File file = File(path);
  if (!file.existsSync()) return null;
  return FileImage(file);
}
