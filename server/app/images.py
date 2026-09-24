"""Image type detection for uploads.

Upload handlers identify images by their bytes rather than the client's
declared Content-Type. Clients frequently send `application/octet-stream` for
a perfectly good JPEG (Dart's `MultipartFile.fromPath` does exactly that unless
the caller names a type), and a declared type is unverified input in any case —
so the file itself is the only thing worth trusting.
"""

# The formats accepted for avatars and playlist covers.
ALLOWED_IMAGE_MIME = {"image/jpeg", "image/png", "image/webp"}


def sniff_image_mime(data: bytes) -> str | None:
    """Return the mime type of [data], or None when it isn't a supported image."""
    if len(data) < 12:
        return None
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    # RIFF container: bytes 0-3 "RIFF", 8-11 "WEBP" (4-7 are the length).
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "image/webp"
    return None
