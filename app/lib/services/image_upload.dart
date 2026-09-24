import 'package:http_parser/http_parser.dart';

/// Content type for an image upload, derived from its file extension.
///
/// `http`'s `MultipartFile.fromPath` declares every file
/// `application/octet-stream` unless told otherwise, and a server filtering on
/// Content-Type will reject that outright. The backend identifies uploads by
/// their bytes regardless, so this is about sending an honest header rather
/// than about the server trusting it.
MediaType imageMediaType(String filePath) {
  final ext = filePath.toLowerCase().split('.').last;
  return switch (ext) {
    'png' => MediaType('image', 'png'),
    'webp' => MediaType('image', 'webp'),
    _ => MediaType('image', 'jpeg'),
  };
}
