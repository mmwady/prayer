/// ML Kit Android returns coordinates in the rotation-corrected image. The current
/// iOS byte-image plugin ignores rotation metadata, so rotate its raw landmarks here.
(double, double) uprightCameraPoint(
    double x, double y, double width, double height, int rotation,
    {required bool alreadyRotated}) {
  final swapped = rotation == 90 || rotation == 270;
  if (alreadyRotated) {
    return (x / (swapped ? height : width), y / (swapped ? width : height));
  }
  return switch (rotation) {
    90 => (1 - y / height, x / width),
    180 => (1 - x / width, 1 - y / height),
    270 => (y / height, 1 - x / width),
    _ => (x / width, y / height),
  };
}
