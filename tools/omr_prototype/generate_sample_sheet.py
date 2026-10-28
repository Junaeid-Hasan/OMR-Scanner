"""
Synthetic OMR Sheet Generator & Camera Distortion Simulator
Creates realistic 30-question 3-section OMR sheets conforming to specification.
Used for calibration, ground-truth benchmarking, and distortion robustness testing.
"""

import random
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from tools.omr_prototype.omr_config import OMRTemplate, DEFAULT_TEMPLATE


def generate_clean_sheet(template: OMRTemplate = DEFAULT_TEMPLATE) -> Image.Image:
    """Generates a clean, blank printed OMR sheet."""
    w, h = template.canonical_width, template.canonical_height
    img = Image.new("RGB", (w, h), color=(252, 252, 252))
    draw = ImageDraw.Draw(img)

    # 1. Outer sheet border margin
    margin = 35
    draw.rectangle([margin, margin, w - margin, h - margin], outline=(60, 60, 60), width=2)

    # 2. Header Area
    draw.text((w // 2 - 140, 70), "EXAMINATION ANSWER SHEET", fill=(20, 20, 20))
    draw.text((w // 2 - 80, 95), "OMR EVALUATION SYSTEM", fill=(60, 60, 60))

    # Student Info Boxes
    box_y = 150
    draw.rectangle([100, box_y, 450, box_y + 80], outline=(100, 100, 100), width=1)
    draw.text((110, box_y + 8), "Student Name: _______________________", fill=(60, 60, 60))
    draw.text((110, box_y + 45), "Roll Number:  _______________________", fill=(60, 60, 60))

    draw.rectangle([500, box_y, 850, box_y + 80], outline=(100, 100, 100), width=1)
    draw.text((510, box_y + 8), "Subject: ____________________________", fill=(60, 60, 60))
    draw.text((510, box_y + 45), "Exam Date: ____ / ____ / ________", fill=(60, 60, 60))

    draw.rectangle([900, box_y, 1100, box_y + 80], outline=(100, 100, 100), width=1)
    draw.text((915, box_y + 12), "Instructions:", fill=(20, 20, 20))
    draw.text((915, box_y + 35), "Fill circle completely.", fill=(80, 80, 80))
    draw.text((915, box_y + 55), "Use blue/black pen.", fill=(80, 80, 80))

    # Divider bar
    draw.line([margin + 10, 280, w - margin - 10, 280], fill=(120, 120, 120), width=2)

    # 3. Section Column Headers
    sections = [
        ("SECTION 1 (Q 1 - 10)", 160),
        ("SECTION 2 (Q 11 - 20)", 530),
        ("SECTION 3 (Q 21 - 30)", 900),
    ]
    for title, sx in sections:
        draw.rectangle([sx - 65, 360, sx + 230, 400], fill=(235, 238, 245), outline=(150, 150, 160))
        draw.text((sx - 30, 372), title, fill=(20, 30, 60))

        # Column option labels (A, B, C, D)
        for i, opt in enumerate(template.options):
            draw.text((sx + i * 52 - 4, 415), opt, fill=(40, 40, 40))

    # 4. Draw Question Rows and Bubbles
    for q_num, opts in template.bubbles.items():
        first_bubble = opts["A"]
        # Question label
        draw.text((first_bubble.x - 55, first_bubble.y - 8), f"{q_num:2d}.", fill=(30, 30, 30))

        for opt, coord in opts.items():
            cx, cy = coord.x, coord.y
            r = coord.radius
            # Draw printed outer circle boundary (2px stroke)
            draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(40, 40, 40), width=2)
            # Draw option letter inside bubble
            draw.text((cx - 4, cy - 6), opt, fill=(120, 120, 120))

    return img


def mark_bubble(draw: ImageDraw.ImageDraw, cx: float, cy: float, radius: float, style: str = "pen"):
    """Simulates realistic student fill marks."""
    if style == "pen":
        # Solid dark ink
        color = (25, 25, 35)
        draw.ellipse([cx - radius + 1, cy - radius + 1, cx + radius - 1, cy + radius - 1], fill=color)
    elif style == "pencil":
        # Graphite pencil texture
        color = (55, 55, 60)
        draw.ellipse([cx - radius + 2, cy - radius + 2, cx + radius - 2, cy + radius - 2], fill=color)
    elif style == "light":
        # Light stroke (test uncertain threshold)
        color = (165, 165, 170)
        draw.ellipse([cx - radius + 3, cy - radius + 3, cx + radius - 3, cy + radius - 3], fill=color)
    elif style == "uneven":
        # Slightly off-center hand mark
        ox = random.uniform(-2.5, 2.5)
        oy = random.uniform(-2.5, 2.5)
        color = (30, 30, 40)
        draw.ellipse([cx + ox - radius + 2, cy + oy - radius + 2, cx + ox + radius - 2, cy + oy + radius - 2], fill=color)


def create_sample_marked_sheet(answers_map: dict, template: OMRTemplate = DEFAULT_TEMPLATE) -> Image.Image:
    """
    Generates a marked OMR sheet based on an answers dictionary:
    answers_map: {q_number: "A" | ["A", "C"] | None | "UNCERTAIN_C"}
    """
    sheet = generate_clean_sheet(template)
    draw = ImageDraw.Draw(sheet)

    for q_num, ans in answers_map.items():
        if q_num not in template.bubbles:
            continue
        q_bubbles = template.bubbles[q_num]

        if ans is None or ans == "BLANK":
            continue

        if isinstance(ans, str):
            if ans.startswith("LIGHT_"):
                opt = ans.split("_")[1]
                coord = q_bubbles[opt]
                mark_bubble(draw, coord.x, coord.y, coord.radius, style="light")
            else:
                coord = q_bubbles[ans]
                mark_bubble(draw, coord.x, coord.y, coord.radius, style="pen")
        elif isinstance(ans, list):
            # Multiple answers
            for opt in ans:
                coord = q_bubbles[opt]
                mark_bubble(draw, coord.x, coord.y, coord.radius, style="pen")

    return sheet


def simulate_phone_photo(
    sheet_img: Image.Image,
    desk_size: tuple = (1600, 2100),
    rotation_deg: float = 3.0,
    tilt_x: float = 25.0,
    tilt_y: float = 20.0,
) -> Tuple[Image.Image, np.ndarray]:
    """
    Simulates a smartphone photo of the OMR sheet resting on a wooden/dark desk,
    with perspective tilt, mild rotation, and ambient lighting variation.
    Returns: (photo_image, true_corners_in_photo)
    """
    dw, dh = desk_size
    # 1. Dark textured desk background
    desk = Image.new("RGB", (dw, dh), color=(50, 42, 36))
    desk_draw = ImageDraw.Draw(desk)
    # Add subtle desk grain
    for y in range(0, dh, 12):
        desk_draw.line([(0, y), (dw, y)], fill=(45, 37, 32), width=2)

    # 2. Sheet placement in center
    sw, sh = sheet_img.size
    offset_x = (dw - sw) // 2
    offset_y = (dh - sh) // 2

    # Original corners relative to desk
    c_tl = [offset_x + tilt_x, offset_y + tilt_y]
    c_tr = [offset_x + sw - tilt_x, offset_y - tilt_y]
    c_br = [offset_x + sw + tilt_x * 0.8, offset_y + sh + tilt_y]
    c_bl = [offset_x - tilt_x * 0.8, offset_y + sh - tilt_y]

    pts_src = np.array([[0, 0], [sw, 0], [sw, sh], [0, sh]], dtype=np.float32)
    pts_dst = np.array([c_tl, c_tr, c_br, c_bl], dtype=np.float32)

    # Warp sheet onto desk
    # Compute coeffs
    matrix = []
    for (u, v), (x, y) in zip(pts_dst, pts_src):
        matrix.append([u, v, 1, 0, 0, 0, -x * u, -x * v])
        matrix.append([0, 0, 0, u, v, 1, -y * u, -y * v])
    A = np.array(matrix, dtype=np.float64)
    B = pts_src.reshape(8).astype(np.float64)
    coeffs = np.linalg.lstsq(A, B, rcond=None)[0]

    warped_sheet = sheet_img.transform(
        (dw, dh),
        Image.Transform.PERSPECTIVE,
        coeffs,
        Image.Resampling.BILINEAR,
    )

    # Composite sheet over desk (masking out black pixels)
    gray_w = np.array(warped_sheet.convert("L"))
    mask = Image.fromarray((gray_w > 10).astype(np.uint8) * 255)
    desk.paste(warped_sheet, (0, 0), mask)

    # Rotate slight angle
    if abs(rotation_deg) > 0.1:
        desk = desk.rotate(rotation_deg, resample=Image.Resampling.BILINEAR, expand=False, fillcolor=(50, 42, 36))

    return desk, pts_dst
