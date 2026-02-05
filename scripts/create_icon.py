#!/usr/bin/env python3
"""
Create Term.app icon using macOS Quartz framework.
Run on macOS: python3 create_icon.py
Output: /tmp/Term.icns
"""
import subprocess
import os

iconset_dir = "/tmp/Term.iconset"
os.makedirs(iconset_dir, exist_ok=True)

sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes:
    png_path = f"{iconset_dir}/icon_{size}x{size}.png"

    script = f'''
import Quartz

size = {size}
colorSpace = Quartz.CGColorSpaceCreateDeviceRGB()
context = Quartz.CGBitmapContextCreate(None, size, size, 8, 0, colorSpace, Quartz.kCGImageAlphaPremultipliedLast)

# Background: dark gradient
Quartz.CGContextSetRGBFillColor(context, 0.08, 0.08, 0.1, 1.0)
Quartz.CGContextFillRect(context, Quartz.CGRectMake(0, 0, size, size))

# Rounded corners effect
corner = size * 0.18
Quartz.CGContextSetRGBFillColor(context, 0.12, 0.12, 0.15, 1.0)
rect = Quartz.CGRectMake(size*0.08, size*0.08, size*0.84, size*0.84)
path = Quartz.CGPathCreateWithRoundedRect(rect, corner, corner, None)
Quartz.CGContextAddPath(context, path)
Quartz.CGContextFillPath(context)

# Border
Quartz.CGContextSetRGBStrokeColor(context, 0.25, 0.25, 0.3, 1.0)
Quartz.CGContextSetLineWidth(context, max(1, size * 0.015))
Quartz.CGContextAddPath(context, path)
Quartz.CGContextStrokePath(context)

# Terminal prompt > symbol (green)
Quartz.CGContextSetRGBStrokeColor(context, 0.0, 0.85, 0.45, 1.0)
x = size * 0.25
y = size * 0.38
w = size * 0.18
h = size * 0.24
Quartz.CGContextSetLineWidth(context, max(2, size * 0.055))
Quartz.CGContextSetLineCap(context, Quartz.kCGLineCapRound)
Quartz.CGContextSetLineJoin(context, Quartz.kCGLineJoinRound)
Quartz.CGContextMoveToPoint(context, x, y + h)
Quartz.CGContextAddLineToPoint(context, x + w, y + h/2)
Quartz.CGContextAddLineToPoint(context, x, y)
Quartz.CGContextStrokePath(context)

# Cursor _ (white, blinking style)
Quartz.CGContextSetRGBFillColor(context, 0.95, 0.95, 0.95, 0.9)
cursorX = size * 0.5
cursorY = size * 0.38
cursorW = size * 0.22
cursorH = max(2, size * 0.045)
Quartz.CGContextFillRect(context, Quartz.CGRectMake(cursorX, cursorY, cursorW, cursorH))

# Save
image = Quartz.CGBitmapContextCreateImage(context)
url = Quartz.CFURLCreateWithFileSystemPath(None, "{png_path}", Quartz.kCFURLPOSIXPathStyle, False)
dest = Quartz.CGImageDestinationCreateWithURL(url, "public.png", 1, None)
Quartz.CGImageDestinationAddImage(dest, image, None)
Quartz.CGImageDestinationFinalize(dest)
print(f"Created {png_path}")
'''
    subprocess.run(["python3", "-c", script], check=True)

# Create @2x versions
for size in [16, 32, 128, 256, 512]:
    src = f"{iconset_dir}/icon_{size*2}x{size*2}.png"
    dst = f"{iconset_dir}/icon_{size}x{size}@2x.png"
    if os.path.exists(src):
        subprocess.run(["cp", src, dst], check=True)
        print(f"Created {dst}")

# Convert to icns
result = subprocess.run(
    ["iconutil", "-c", "icns", iconset_dir, "-o", "/tmp/Term.icns"],
    capture_output=True, text=True
)
if result.returncode == 0:
    print("\n✅ Icon created: /tmp/Term.icns")
    print("To install: cp /tmp/Term.icns ~/Applications/Term.app/Contents/Resources/")
else:
    print(f"Error: {result.stderr}")
