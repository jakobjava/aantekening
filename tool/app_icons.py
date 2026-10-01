"""Makes the app's icons, for every platform, from its one picture.

The picture, packaging/icon/aantekening.png, is 512 pixels square. From it
come Windows's icon, at the sizes Explorer and the taskbar ask for, and
Android's launcher icons at each screen density. Linux takes the picture as
it is (packaging/arch/PKGBUILD). Run with Pillow, from the repository:

    python3 tool/app_icons.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app" / "aantekening"
PICTURE = ROOT / "packaging" / "icon" / "aantekening.png"

WINDOWS_SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]
ANDROID_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def main():
    picture = Image.open(PICTURE).convert("RGBA")
    picture.save(
        APP / "windows" / "runner" / "resources" / "app_icon.ico",
        sizes=[(size, size) for size in WINDOWS_SIZES],
    )
    for density, size in ANDROID_SIZES.items():
        picture.resize((size, size), Image.LANCZOS).save(
            APP / "android" / "app" / "src" / "main" / "res"
            / f"mipmap-{density}" / "ic_launcher.png",
            optimize=True,
        )


if __name__ == "__main__":
    main()
