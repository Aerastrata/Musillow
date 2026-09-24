"""Generate every app-icon asset from the one logo artwork.

Run:  python3 tool/generate_app_icons.py

Source of truth is ../new-musillow-logo-composited.png — the mascot drawn on a
flat white field. Everything the platforms need is derived from it here rather
than hand-maintained, so a new logo drop is one command instead of thirty files:

  * the Android adaptive icon's foreground and monochrome layers,
  * the legacy square/round launcher bitmaps for API 24-25, which predate
    adaptive icons and so have to carry the background baked in,
  * the status-bar notification mark, and
  * the iOS app-icon set.

The background stays a vector (drawable/ic_launcher_background.xml): it is a
flat radial gradient and loses nothing by not being a bitmap.

Two derivations are worth explaining.

*Cutting the mascot out.* The logo's field is flat white but so is the
marshmallow's body, so keying on colour alone would punch a hole through the
character. The cut is a flood fill from the border instead, which only reaches
white that is connected to the outside.

*The monochrome and notification marks.* A filled silhouette of this mascot is
a featureless blob at status-bar size. Both layers instead keep the artwork's
"ink" — the teal headphones, the body's rim, the face — and drop the white body
fill, which reads as an outline of the character and stays legible at 24px.
"""
import pathlib
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOGO = ROOT.parent / "new-musillow-logo-composited.png"
RES = ROOT / "android/app/src/main/res"
IOS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"

# Density buckets, as a multiple of mdpi.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

# An adaptive icon is a 108dp canvas whose outer 18dp on each side can be
# cropped away by the launcher's mask. The mascot is drawn at this fraction of
# the full canvas, which keeps it inside the guaranteed-visible area with room
# for the mask's parallax.
SAFE_FRACTION = 0.60

# The legacy (pre-adaptive) bitmap has no mask applied for it, so it carries its
# own corner radius, and the mascot sits larger because nothing will be cropped.
LEGACY_FRACTION = 0.72
LEGACY_RADIUS = 0.22  # of the icon's width

# The logo's background gradient, matching drawable/ic_launcher_background.xml.
BG_INNER = (36, 31, 48)
BG_OUTER = (15, 13, 19)

# Anything darker than this (in its darkest channel) counts as ink rather than
# body fill. Tuned so the body's teal rim survives and its white centre doesn't.
INK_THRESHOLD = 90


def mascot() -> Image.Image:
    """The logo with its white field removed, trimmed to the character."""
    if not LOGO.exists():
        sys.exit(f"no logo at {LOGO}")
    src = Image.open(LOGO).convert("RGB")
    field = Image.new("RGB", src.size, (255, 255, 255))
    box = (
        ImageChops.difference(src, field)
        .convert("L")
        .point(lambda p: 255 if p > 10 else 0)
        .getbbox()
    )
    if not box:
        sys.exit("the logo appears to be blank")
    cropped = src.crop(box)

    # ImageMagick's flood fill, which unlike a colour key only removes white
    # reachable from the border — the marshmallow's white body is enclosed by
    # its own rim and survives.
    tmp_in = ROOT / "build" / "_logo_crop.png"
    tmp_out = ROOT / "build" / "_logo_cut.png"
    tmp_in.parent.mkdir(parents=True, exist_ok=True)
    cropped.save(tmp_in)
    subprocess.run(
        [
            "magick", str(tmp_in),
            "-alpha", "set",
            "-bordercolor", "white", "-border", "1",
            "-fuzz", "10%", "-fill", "none", "-floodfill", "+0+0", "white",
            "-shave", "1x1",
            str(tmp_out),
        ],
        check=True,
    )
    out = Image.open(tmp_out).convert("RGBA")
    tmp_in.unlink()
    tmp_out.unlink()
    return out.crop(out.getbbox())


def ink(mark: Image.Image) -> Image.Image:
    """The mark as white-on-transparent ink: everything but the body fill.

    Used for the themed-icon monochrome layer and the notification icon, both
    of which are tinted by the system and so carry shape in their alpha only.
    """
    out = Image.new("RGBA", mark.size, (255, 255, 255, 0))
    src, dst = mark.load(), out.load()
    for y in range(mark.height):
        for x in range(mark.width):
            r, g, b, a = src[x, y]
            if a < 30:
                continue
            darkness = 255 - min(r, g, b)
            dst[x, y] = (255, 255, 255, int(a * min(1.0, darkness / INK_THRESHOLD)))
    return out


def centred(mark: Image.Image, size: int, fraction: float) -> Image.Image:
    """[mark] scaled to [fraction] of [size] and centred on a clear canvas."""
    span = max(mark.size)
    scale = (size * fraction) / span
    art = mark.resize(
        (max(1, round(mark.width * scale)), max(1, round(mark.height * scale))),
        Image.LANCZOS,
    )
    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    canvas.paste(art, ((size - art.width) // 2, (size - art.height) // 2), art)
    return canvas


def gradient(size: int) -> Image.Image:
    """The background gradient, matching the vector background layer."""
    bg = Image.new("RGB", (size, size))
    px = bg.load()
    cx, cy, radius = size / 2, size * 0.35, size * 0.75
    for y in range(size):
        for x in range(size):
            d = min(1.0, (((x - cx) ** 2 + (y - cy) ** 2) ** 0.5) / radius)
            px[x, y] = tuple(
                round(a + (b - a) * d) for a, b in zip(BG_INNER, BG_OUTER)
            )
    return bg


def rounded(image: Image.Image, radius: float) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, image.width - 1, image.height - 1),
        radius=round(image.width * radius),
        fill=255,
    )
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def circular(image: Image.Image) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, image.width - 1, image.height - 1), fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def write(image: Image.Image, path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    print("wrote", path.relative_to(ROOT))


def main() -> None:
    mark = mascot()
    mono = ink(mark)
    print(f"mascot cut to {mark.width}x{mark.height}")

    for bucket, factor in DENSITIES.items():
        # Adaptive layers: a 108dp canvas at this density.
        adaptive = round(108 * factor)
        write(
            centred(mark, adaptive, SAFE_FRACTION),
            RES / f"mipmap-{bucket}/ic_launcher_foreground.png",
        )
        write(
            centred(mono, adaptive, SAFE_FRACTION),
            RES / f"mipmap-{bucket}/ic_launcher_monochrome.png",
        )

        # Legacy launcher bitmaps (API 24-25), background baked in.
        legacy = round(48 * factor)
        plate = gradient(legacy)
        art = centred(mark, legacy, LEGACY_FRACTION)
        plate.paste(art, (0, 0), art)
        write(rounded(plate, LEGACY_RADIUS), RES / f"mipmap-{bucket}/ic_launcher.png")
        write(circular(plate), RES / f"mipmap-{bucket}/ic_launcher_round.png")

        # Status-bar mark: white ink, no background, tinted by the system.
        notif = round(24 * factor)
        write(
            centred(mono, notif, 1.0),
            RES / f"drawable-{bucket}/ic_notification.png",
        )

    # iOS has no adaptive layers, so every size is the finished square.
    if IOS.exists():
        for path in sorted(IOS.glob("Icon-App-*.png")):
            size = Image.open(path).size[0]
            plate = gradient(size)
            art = centred(mark, size, LEGACY_FRACTION)
            plate.paste(art, (0, 0), art)
            # iOS applies its own mask and rejects alpha, so this stays square.
            write(plate.convert("RGB"), path)


if __name__ == "__main__":
    main()
