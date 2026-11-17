abstract final class AuraSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AuraRadius {
  static const double control = 12;
  static const double card = 20;
  static const double panel = 24;
  static const double pill = 999;
}

abstract final class AuraBreakpoints {
  static const double mobile = 700;
  static const double desktop = 1100;
  static const double content = 1440;
}

double pageHorizontalPadding(double width) {
  if (width >= 1400) return AuraSpace.xl;
  if (width >= 760) return AuraSpace.lg;
  return AuraSpace.md;
}
