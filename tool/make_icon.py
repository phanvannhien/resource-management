"""Tạo bộ icon app AMV-WebManage từ ảnh gốc assets/icon/source.png.

Ảnh gốc là icon đã bo góc trên nền trắng. Script:
  - cắt sát khung icon, phủ 4 góc trắng bằng gradient cùng màu nền icon
    → icon vuông kín nền để iOS/Android tự bo góc theo khuôn của máy;
  - tạo bộ adaptive cho Android: nền gradient + toàn bộ icon thu nhỏ vào vùng hiển thị.

Chạy: python3 tool/make_icon.py && dart run flutter_launcher_icons
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent / 'assets' / 'icon'
SRC = ROOT / 'source.png'
SIZE = 1024

# Màu nền icon gốc ở 4 góc (lấy mẫu bên trong khung bo góc)
TL, TR = (9, 167, 253), (6, 68, 231)
BL, BR = (1, 65, 225), (0, 35, 212)


def bilinear(w: int, h: int) -> Image.Image:
    small = Image.new('RGB', (64, 64))
    px = small.load()
    for y in range(64):
        for x in range(64):
            u, v = x / 63, y / 63
            px[x, y] = tuple(
                round(a * (1 - u) * (1 - v) + b * u * (1 - v) + c * (1 - u) * v + d * u * v)
                for a, b, c, d in zip(TL, TR, BL, BR))
    return small.resize((w, h), Image.BICUBIC)


def crop_to_shape(src: Image.Image) -> Image.Image:
    """Cắt sát khung icon (bỏ viền trắng), trả về ảnh vuông."""
    rgb = src.convert('RGB')
    diff = ImageChops.difference(rgb, Image.new('RGB', rgb.size, (255, 255, 255)))
    bbox = diff.convert('L').point(lambda v: 255 if v > 40 else 0).getbbox()
    x0, y0, x1, y1 = bbox
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return rgb.crop((round(cx - side / 2), round(cy - side / 2), round(cx + side / 2), round(cy + side / 2)))


def full_bleed(art: Image.Image) -> Image.Image:
    """Phủ phần trắng ở 4 góc bằng gradient nền."""
    w, h = art.size
    # Vùng trắng/gần trắng nối với mép ảnh = phần nằm ngoài khung bo góc
    white = art.convert('L').point(lambda v: 255 if v > 235 else 0)
    outside = Image.new('L', (w, h), 0)
    for seed in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        tmp = white.copy()
        ImageDraw.floodfill(tmp, seed, 128)
        outside = ImageChops.lighter(outside, tmp.point(lambda v: 255 if v == 128 else 0))
    # Nới rộng vùng phủ vài px để xoá viền răng cưa sáng màu
    outside = outside.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(2))
    out = art.copy()
    out.paste(bilinear(w, h), mask=outside)
    return out


def main() -> None:
    art = crop_to_shape(Image.open(SRC))
    icon = full_bleed(art).resize((SIZE, SIZE), Image.LANCZOS)
    icon.save(ROOT / 'icon.png')

    # Android adaptive: launcher chỉ hiện ~72/108 phần giữa và cắt tròn/bo góc.
    # Đặt cả icon vào vùng đó để không mất chữ, phần ngoài là gradient nền.
    # Nền = chính icon làm mờ mạnh, để mép phần icon thu nhỏ hoà vào nền
    bg = icon.filter(ImageFilter.GaussianBlur(60))
    bg.save(ROOT / 'icon_bg.png')

    # Launcher chỉ hiện ~72/108 phần giữa rồi cắt tròn/bo góc:
    # đặt cả icon thu nhỏ vào đó, đủ nhỏ để chữ không bị cắt khi bo tròn.
    inner = round(SIZE * 72 / 108 * 0.84)
    fg = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    mask = Image.new('L', (inner, inner), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner, inner), radius=round(inner * 0.24), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(14))
    off = (SIZE - inner) // 2
    fg.paste(icon.resize((inner, inner), Image.LANCZOS), (off, off), mask)
    fg.save(ROOT / 'icon_fg.png')
    # macOS: khối bo góc ~80% khung, nền trong suốt (chuẩn icon Dock)
    mac_side = round(SIZE * 0.805)
    mac_mask = Image.new('L', (mac_side, mac_side), 0)
    ImageDraw.Draw(mac_mask).rounded_rectangle(
        (0, 0, mac_side - 1, mac_side - 1), radius=round(mac_side * 0.225), fill=255)
    mac = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    m_off = (SIZE - mac_side) // 2
    mac.paste(icon.resize((mac_side, mac_side), Image.LANCZOS), (m_off, m_off), mac_mask)
    mac.save(ROOT / 'icon_macos.png')
    print('Đã tạo icon.png, icon_bg.png, icon_fg.png, icon_macos.png trong', ROOT)


if __name__ == '__main__':
    main()
