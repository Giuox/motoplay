#!/usr/bin/env python3
"""Genera icone PNG per MotoPlay PWA — solo stdlib, nessuna dipendenza."""
import struct, zlib, os

def make_png(size, r, g, b):
    def chunk(tag, data):
        c = tag + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
    ihdr = struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)
    rows = b''.join(b'\x00' + bytes([r, g, b] * size) for _ in range(size))
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(rows, 9))
            + chunk(b'IEND', b''))

def make_png_with_text(size):
    """Usa Pillow se disponibile per icona con testo MG."""
    try:
        from PIL import Image, ImageDraw, ImageFont
        img = Image.new('RGB', (size, size), (200, 16, 46))
        draw = ImageDraw.Draw(img)
        try:
            font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', size // 3)
        except Exception:
            font = ImageFont.load_default()
        text = 'MG'
        bbox = draw.textbbox((0,0), text, font=font)
        tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
        draw.text(((size-tw)//2, (size-th)//2 - size//12), text,
                  fill=(255,255,255), font=font)
        import io
        buf = io.BytesIO()
        img.save(buf, 'PNG')
        return buf.getvalue()
    except ImportError:
        return make_png(size, 200, 16, 46)

os.makedirs('assets', exist_ok=True)
for sz in [180, 192, 512]:
    data = make_png_with_text(sz)
    path = f'assets/icon-{sz}.png'
    with open(path, 'wb') as f:
        f.write(data)
    print(f'  {path}  ({sz}x{sz}, {len(data)} bytes)')
print('Icone generate. Puoi eseguire: python create_icons.py')
