#!/usr/bin/env python3
import math
import os
from PIL import Image, ImageDraw, ImageFilter

def create_master_icon(size=1024):
    # Render at 2x resolution (2048x2048) for ultra-sharp anti-aliased results
    scale = 2
    W = size * scale
    H = size * scale

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 1. Base Squircle / Rounded Background
    pad = int(40 * scale)
    bg_radius = int(220 * scale)
    
    # Create background with gradient
    bg_mask = Image.new("L", (W, H), 0)
    bg_draw = ImageDraw.Draw(bg_mask)
    bg_draw.rounded_rectangle([pad, pad, W - pad, H - pad], radius=bg_radius, fill=255)

    # Vertical gradient from vibrant indigo (#4F46E5) to deep indigo/midnight (#1E1B4B)
    gradient = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(gradient)
    top_color = (79, 70, 229, 255)     # #4F46E5
    mid_color = (67, 56, 202, 255)     # #4338CA
    bot_color = (30, 27, 75, 255)      # #1E1B4B

    for y in range(H):
        t = y / H
        if t < 0.5:
            factor = t / 0.5
            r = int(top_color[0] + (mid_color[0] - top_color[0]) * factor)
            g = int(top_color[1] + (mid_color[1] - top_color[1]) * factor)
            b = int(top_color[2] + (mid_color[2] - top_color[2]) * factor)
        else:
            factor = (t - 0.5) / 0.5
            r = int(mid_color[0] + (bot_color[0] - mid_color[0]) * factor)
            g = int(mid_color[1] + (bot_color[1] - mid_color[1]) * factor)
            b = int(mid_color[2] + (bot_color[2] - mid_color[2]) * factor)
        g_draw.line([(0, y), (W, y)], fill=(r, g, b, 255))

    # Apply background mask
    img.paste(gradient, (0, 0), bg_mask)

    # Subtle inner border for modern depth
    border_draw = ImageDraw.Draw(img)
    border_draw.rounded_rectangle(
        [pad, pad, W - pad, H - pad],
        radius=bg_radius,
        outline=(255, 255, 255, 30),
        width=int(4 * scale)
    )

    # 2. Paper Sheet with Drop Shadow
    paper_w = int(540 * scale)
    paper_h = int(680 * scale)
    paper_x = (W - paper_w) // 2
    paper_y = int(170 * scale)
    paper_radius = int(36 * scale)

    # Soft drop shadow for paper
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    s_offset = int(18 * scale)
    s_draw.rounded_rectangle(
        [paper_x, paper_y + s_offset, paper_x + paper_w, paper_y + paper_h + s_offset],
        radius=paper_radius,
        fill=(10, 15, 40, 110)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(24 * scale)))
    img = Image.alpha_composite(img, shadow)

    # Draw White Paper Sheet
    sheet = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(sheet)
    sh_draw.rounded_rectangle(
        [paper_x, paper_y, paper_x + paper_w, paper_y + paper_h],
        radius=paper_radius,
        fill=(255, 255, 255, 250),
        outline=(226, 232, 240, 240),
        width=int(3 * scale)
    )

    # Paper Header Elements (Mock exam header)
    hdr_y = paper_y + int(48 * scale)
    # Header bar
    sh_draw.rounded_rectangle(
        [paper_x + int(45 * scale), hdr_y, paper_x + int(240 * scale), hdr_y + int(14 * scale)],
        radius=int(7 * scale),
        fill=(67, 56, 202, 220)
    )
    # Secondary header lines
    sh_draw.rounded_rectangle(
        [paper_x + int(45 * scale), hdr_y + int(26 * scale), paper_x + int(160 * scale), hdr_y + int(36 * scale)],
        radius=int(5 * scale),
        fill=(148, 163, 184, 180)
    )
    # Registration / roll box icon
    sh_draw.rounded_rectangle(
        [paper_x + paper_w - int(120 * scale), hdr_y, paper_x + paper_w - int(45 * scale), hdr_y + int(34 * scale)],
        radius=int(6 * scale),
        fill=(241, 245, 249, 255),
        outline=(203, 213, 225, 255),
        width=int(2 * scale)
    )

    # Thin separator line
    sep_y = hdr_y + int(56 * scale)
    sh_draw.line(
        [(paper_x + int(45 * scale), sep_y), (paper_x + paper_w - int(45 * scale), sep_y)],
        fill=(226, 232, 240, 255),
        width=int(2 * scale)
    )

    # 3. OMR Bubble Grid
    # 5 rows, 4 options each (A, B, C, D)
    bubble_radius = int(22 * scale)
    row_start_y = sep_y + int(40 * scale)
    row_spacing = int(88 * scale)
    col_spacing = int(82 * scale)
    col_start_x = paper_x + int(135 * scale)

    filled_pattern = [1, 0, 2, 3, 1]  # Which bubble is filled in each row (B, A, C, D, B)

    for r_idx in range(5):
        cy = row_start_y + r_idx * row_spacing
        
        # Row number pill
        sh_draw.rounded_rectangle(
            [paper_x + int(45 * scale), cy - int(10 * scale), paper_x + int(85 * scale), cy + int(10 * scale)],
            radius=int(5 * scale),
            fill=(224, 231, 255, 255)
        )
        
        for c_idx in range(4):
            cx = col_start_x + c_idx * col_spacing
            box = [cx - bubble_radius, cy - bubble_radius, cx + bubble_radius, cy + bubble_radius]
            
            if c_idx == filled_pattern[r_idx]:
                # Filled bubble with rich indigo/teal fill
                sh_draw.ellipse(box, fill=(49, 46, 129, 255))
                # Inner highlight dot
                sh_draw.ellipse([cx - int(7*scale), cy - int(7*scale), cx + int(7*scale), cy + int(7*scale)], fill=(67, 56, 202, 255))
            else:
                # Empty bubble with clean crisp border
                sh_draw.ellipse(box, outline=(148, 163, 184, 255), width=int(3 * scale), fill=(248, 250, 252, 255))

    img = Image.alpha_composite(img, sheet)

    # 4. Laser Scan Beam & Glow Effect
    # Laser bar across row 3
    scan_y = row_start_y + int(2.1 * row_spacing)
    laser_glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    l_draw = ImageDraw.Draw(laser_glow)
    
    # Wide cyan glow
    l_draw.line([(paper_x - int(30 * scale), scan_y), (paper_x + paper_w + int(30 * scale), scan_y)],
                fill=(6, 182, 212, 140), width=int(22 * scale))
    laser_glow = laser_glow.filter(ImageFilter.GaussianBlur(int(14 * scale)))
    img = Image.alpha_composite(img, laser_glow)

    # Sharp bright central laser line
    bright_laser = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bl_draw = ImageDraw.Draw(bright_laser)
    bl_draw.line([(paper_x - int(15 * scale), scan_y), (paper_x + paper_w + int(15 * scale), scan_y)],
                 fill=(45, 212, 191, 255), width=int(5 * scale))
    img = Image.alpha_composite(img, bright_laser)

    # 5. Futuristic Viewfinder / Scanner Corner Reticles
    reticle = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    r_draw = ImageDraw.Draw(reticle)
    r_margin = int(24 * scale)
    rx1 = paper_x - r_margin
    ry1 = paper_y - r_margin
    rx2 = paper_x + paper_w + r_margin
    ry2 = paper_y + paper_h + r_margin
    arm = int(60 * scale)
    r_w = int(8 * scale)
    r_color = (20, 184, 166, 255) # Electric teal #14B8A6

    # Top-Left
    r_draw.line([(rx1, ry1), (rx1 + arm, ry1)], fill=r_color, width=r_w)
    r_draw.line([(rx1, ry1), (rx1, ry1 + arm)], fill=r_color, width=r_w)
    # Top-Right
    r_draw.line([(rx2, ry1), (rx2 - arm, ry1)], fill=r_color, width=r_w)
    r_draw.line([(rx2, ry1), (rx2, ry1 + arm)], fill=r_color, width=r_w)
    # Bottom-Left
    r_draw.line([(rx1, ry2), (rx1 + arm, ry2)], fill=r_color, width=r_w)
    r_draw.line([(rx1, ry2), (rx1, ry2 - arm)], fill=r_color, width=r_w)
    # Bottom-Right
    r_draw.line([(rx2, ry2), (rx2 - arm, ry2)], fill=r_color, width=r_w)
    r_draw.line([(rx2, ry2), (rx2 - arm, ry2)], fill=r_color, width=r_w)

    img = Image.alpha_composite(img, reticle)

    # 6. Success / Checkmark Badge at bottom-right
    badge_x = paper_x + paper_w - int(55 * scale)
    badge_y = paper_y + paper_h - int(55 * scale)
    badge_r = int(95 * scale)

    badge_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    b_draw = ImageDraw.Draw(badge_img)

    # Badge Shadow
    b_draw.ellipse(
        [badge_x - badge_r, badge_y - badge_r + int(10*scale), badge_x + badge_r, badge_y + badge_r + int(10*scale)],
        fill=(10, 15, 40, 120)
    )
    badge_img = badge_img.filter(ImageFilter.GaussianBlur(int(14 * scale)))

    # Badge Circle with gradient/teal-emerald (#059669 -> #10B981)
    b_draw = ImageDraw.Draw(badge_img)
    b_draw.ellipse(
        [badge_x - badge_r, badge_y - badge_r, badge_x + badge_r, badge_y + badge_r],
        fill=(16, 185, 129, 255),
        outline=(255, 255, 255, 240),
        width=int(7 * scale)
    )

    # Checkmark inside badge
    chk_w = int(14 * scale)
    # Points for checkmark:
    p1 = (badge_x - int(38 * scale), badge_y - int(4 * scale))
    p2 = (badge_x - int(10 * scale), badge_y + int(26 * scale))
    p3 = (badge_x + int(38 * scale), badge_y - int(28 * scale))

    b_draw.line([p1, p2], fill=(255, 255, 255, 255), width=chk_w)
    b_draw.line([p2, p3], fill=(255, 255, 255, 255), width=chk_w)
    b_draw.ellipse([p1[0]-chk_w//2, p1[1]-chk_w//2, p1[0]+chk_w//2, p1[1]+chk_w//2], fill=(255, 255, 255, 255))
    b_draw.ellipse([p2[0]-chk_w//2, p2[1]-chk_w//2, p2[0]+chk_w//2, p2[1]+chk_w//2], fill=(255, 255, 255, 255))
    b_draw.ellipse([p3[0]-chk_w//2, p3[1]-chk_w//2, p3[0]+chk_w//2, p3[1]+chk_w//2], fill=(255, 255, 255, 255))

    img = Image.alpha_composite(img, badge_img)

    # Downsample to target size with high-quality Lanczos resampling
    final_img = img.resize((size, size), Image.Resampling.LANCZOS)
    return final_img

def main():
    os.makedirs("assets/icons", exist_ok=True)
    master = create_master_icon(1024)
    master_path = "assets/icons/app_logo.png"
    master.save(master_path, "PNG")
    print(f"Master icon saved to {master_path}")

    # Generate Android mipmaps
    android_targets = {
        "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
        "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
        "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
        "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
        "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
    }

    for path, sz in android_targets.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        resized = master.resize((sz, sz), Image.Resampling.LANCZOS)
        resized.save(path, "PNG")
        print(f"Generated Android icon: {path} ({sz}x{sz})")

    # Generate iOS AppIcon set
    ios_dir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    ios_targets = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }

    for filename, sz in ios_targets.items():
        path = os.path.join(ios_dir, filename)
        resized = master.resize((sz, sz), Image.Resampling.LANCZOS)
        # iOS AppIcon should have RGB (no alpha) on 1024x1024 store icon
        if sz == 1024 or filename.startswith("Icon-App"):
            # create opaque background
            bg = Image.new("RGBA", (sz, sz), (30, 27, 75, 255))
            composed = Image.alpha_composite(bg, resized).convert("RGB")
            composed.save(path, "PNG")
        else:
            resized.save(path, "PNG")
        print(f"Generated iOS icon: {path} ({sz}x{sz})")

    # Generate Web icons & favicon
    web_dir = "web"
    web_targets = {
        "web/icons/Icon-192.png": 192,
        "web/icons/Icon-512.png": 512,
        "web/icons/Icon-maskable-192.png": 192,
        "web/icons/Icon-maskable-512.png": 512,
        "web/favicon.png": 32,
    }

    for path, sz in web_targets.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        resized = master.resize((sz, sz), Image.Resampling.LANCZOS)
        resized.save(path, "PNG")
        print(f"Generated Web icon: {path} ({sz}x{sz})")

if __name__ == "__main__":
    main()
