import 'dart:math';

import 'package:meta/meta.dart';

@internal
class ScreenshotRecorderConfig {
  final int? width;
  final int? height;

  ScreenshotRecorderConfig({
    this.width,
    this.height,
  });

  double? getPixelRatio(double srcWidth, double srcHeight) {
    assert((width == null) == (height == null));
    if (width == null || height == null) {
      return null;
    }
    return min(width! / srcWidth, height! / srcHeight);
  }
}
