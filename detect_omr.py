#!/usr/bin/env python3
"""
OMR Answer Sheet Detector & Evaluator
Implements dynamic 30-question grid reconstruction (3 columns x 10 rows),
bubble candidate filtering with Bengali label exclusion, Otsu binarization,
and circle-mask fill evaluation.
"""

import os
import sys
import argparse
import numpy as np

# Try importing OpenCV, with automatic pure-Python (NumPy/SciPy/PIL) fallback
try:
    import cv2
    HAS_CV2 = True
except ImportError:
    cv2 = None
    HAS_CV2 = False

try:
    from PIL import Image, ImageDraw
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

try:
    from scipy.ndimage import uniform_filter, label, find_objects
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False

try:
    import matplotlib
    import matplotlib.pyplot as plt
except ImportError:
    plt = None


OPTION_LABELS = ["ক", "খ", "গ", "ঘ"]
ENGLISH_LABELS = ["A", "B", "C", "D"]


def order_points(points):
    """
    Orders 4 points as: [Top-Left, Top-Right, Bottom-Right, Bottom-Left].
    """
    points = np.array(points, dtype=np.float32)

    s = points.sum(axis=1)
    diff = np.diff(points, axis=1).flatten()

    top_left = points[np.argmin(s)]
    top_right = points[np.argmin(diff)]
    bottom_right = points[np.argmax(s)]
    bottom_left = points[np.argmax(diff)]

    return np.array([top_left, top_right, bottom_right, bottom_left], dtype=np.float32)


def find_omr_contour(image):
    """
    Detects the 4 outer corner points of the OMR sheet.
    If the image is already cropped to the sheet, returns full frame bounds.
    """
    h, w = image.shape[:2]
    if HAS_CV2 and cv2 is not None:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blurred, 50, 150)

        kernel = np.ones((5, 5), np.uint8)
        edges = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel)

        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contours = sorted(contours, key=cv2.contourArea, reverse=True)

        image_area = h * w
        for contour in contours:
            area = cv2.contourArea(contour)
            if area < image_area * 0.10:
                continue

            perimeter = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.02 * perimeter, True)

            if len(approx) == 4:
                return approx.reshape(4, 2)

    # Fallback: Assume close-up / pre-cropped sheet filling the image
    return np.array([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]], dtype=np.float32)


def perspective_transform(image, corners):
    """
    Warps the quadrilateral defined by corners into a canonical rectangular image.
    """
    rect = order_points(corners)
    tl, tr, br, bl = rect

    width_top = np.linalg.norm(tr - tl)
    width_bottom = np.linalg.norm(br - bl)
    max_width = int(max(width_top, width_bottom))

    height_left = np.linalg.norm(bl - tl)
    height_right = np.linalg.norm(br - tr)
    max_height = int(max(height_left, height_right))

    # If already rectangular and close to canonical size, return image
    h, w = image.shape[:2]
    if (
        np.allclose(rect, [[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]], atol=2)
        and max_width == w
        and max_height == h
    ):
        return image

    destination = np.array(
        [
            [0, 0],
            [max_width - 1, 0],
            [max_width - 1, max_height - 1],
            [0, max_height - 1],
        ],
        dtype=np.float32,
    )

    if HAS_CV2 and cv2 is not None:
        matrix = cv2.getPerspectiveTransform(rect, destination)
        warped = cv2.warpPerspective(image, matrix, (max_width, max_height))
        return warped

    # Pure Python / PIL fallback
    if HAS_PIL:
        pil_img = Image.fromarray(image)
        warped = pil_img.resize((max_width, max_height))
        return np.array(warped)

    return image


def detect_bubble_candidates(warped):
    """
    Extracts bubble candidates, excluding header and Bengali numeral labels (১-৩০).
    Returns: (unique_bubbles, expected_r, col_width, gray)
    """
    H, W = warped.shape[:2]
    if len(warped.shape) == 3:
        if HAS_CV2 and cv2 is not None:
            gray = cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY)
        else:
            gray = (
                0.299 * warped[:, :, 0]
                + 0.587 * warped[:, :, 1]
                + 0.114 * warped[:, :, 2]
            ).astype(np.uint8)
    else:
        gray = warped.copy()

    col_width = W / 3.0
    expected_r = H / (11 * 2 * 2.2)
    candidates = []

    if HAS_CV2 and cv2 is not None:
        thresh = cv2.adaptiveThreshold(
            gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 31, 9
        )
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        thresh_clean = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, kernel)
        contours, _ = cv2.findContours(thresh_clean, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)

        for cnt in contours:
            area = cv2.contourArea(cnt)
            perimeter = cv2.arcLength(cnt, True)
            if perimeter == 0:
                continue

            x, y, w, h = cv2.boundingRect(cnt)
            aspect_ratio = float(w) / h
            circularity = 4 * np.pi * (area / (perimeter * perimeter))

            if not (0.70 <= aspect_ratio <= 1.30 and circularity >= 0.50):
                continue

            r = max(w, h) / 2.0
            if not (expected_r * 0.4 <= r <= expected_r * 2.2):
                continue

            cx, cy = int(x + w / 2), int(y + h / 2)

            # Exclude top header
            if cy < H * 0.08:
                continue

            # Exclude Bengali numeral columns (১-৩০) in leftmost 16% of each column section
            rel_x = (cx % col_width) / col_width
            if rel_x < 0.16:
                continue

            candidates.append((cx, cy, int(r)))
    elif HAS_SCIPY:
        local_mean = uniform_filter(gray.astype(float), size=31)
        binary_inv = (gray < (local_mean - 9)).astype(np.uint8)
        labeled, num_features = label(binary_inv)
        slices = find_objects(labeled)

        for i, s in enumerate(slices):
            if s is None:
                continue
            mask = labeled[s] == (i + 1)
            area = np.sum(mask)
            y_slice, x_slice = s
            h = y_slice.stop - y_slice.start
            w = x_slice.stop - x_slice.start
            if w == 0 or h == 0:
                continue

            aspect_ratio = float(w) / h
            perimeter = 2 * (w + h)
            circularity = 4 * np.pi * (area / (perimeter * perimeter))
            r = max(w, h) / 2.0

            if not (0.70 <= aspect_ratio <= 1.30 and 0.25 <= circularity <= 1.5):
                continue
            if not (expected_r * 0.4 <= r <= expected_r * 2.2):
                continue

            cx = int(x_slice.start + w / 2)
            cy = int(y_slice.start + h / 2)

            if cy < H * 0.08:
                continue

            rel_x = (cx % col_width) / col_width
            if rel_x < 0.16:
                continue

            candidates.append((cx, cy, int(r)))

    # Remove duplicate detections
    unique_bubbles = []
    for c in candidates:
        x1, y1, r1 = c
        if not any(np.hypot(x1 - x2, y1 - y2) < r1 * 0.7 for x2, y2, _ in unique_bubbles):
            unique_bubbles.append(c)

    return unique_bubbles, expected_r, col_width, gray


def reconstruct_grid(unique_bubbles, W, H, col_width):
    """
    Reconstructs the 10x4 dynamic grid across all 3 columns (120 bubbles).
    Robust against outlier points by clustering and size filtering.
    """
    y_coords = sorted([pt[1] for pt in unique_bubbles])
    row_clusters = []
    for y in y_coords:
        if not row_clusters or abs(np.mean(row_clusters[-1]) - y) > (H / 25):
            row_clusters.append([y])
        else:
            row_clusters[-1].append(y)

    # Filter out small outlier clusters (e.g. stray points in header)
    valid_row_clusters = [c for c in row_clusters if len(c) >= 3]
    if len(valid_row_clusters) == 10:
        row_y_centers = [int(np.median(cluster)) for cluster in valid_row_clusters]
    elif len(valid_row_clusters) > 10:
        # Pick 10 most populous clusters sorted by vertical position
        top10 = sorted(valid_row_clusters, key=len, reverse=True)[:10]
        top10_sorted = sorted(top10, key=lambda c: np.median(c))
        row_y_centers = [int(np.median(cluster)) for cluster in top10_sorted]
    else:
        min_y = min(y_coords) if y_coords else int(H * 0.18)
        max_y = max(y_coords) if y_coords else int(H * 0.90)
        row_y_centers = np.linspace(min_y, max_y, 10).astype(int)

    final_grid = []

    for col_idx in range(3):
        x_min_bound = col_idx * col_width + 0.16 * col_width
        x_max_bound = (col_idx + 1) * col_width

        col_pts = [pt for pt in unique_bubbles if x_min_bound <= pt[0] <= x_max_bound]
        x_coords = sorted([pt[0] for pt in col_pts])

        opt_clusters = []
        for x in x_coords:
            if not opt_clusters or abs(np.mean(opt_clusters[-1]) - x) > (col_width / 8):
                opt_clusters.append([x])
            else:
                opt_clusters[-1].append(x)

        # Filter out stray border points
        valid_opt_clusters = [c for c in opt_clusters if len(c) >= 3]
        if len(valid_opt_clusters) == 4:
            col_x_centers = [int(np.median(c)) for c in valid_opt_clusters]
        elif len(opt_clusters) == 4:
            col_x_centers = [int(np.median(c)) for c in opt_clusters]
        elif len(valid_opt_clusters) > 4:
            top4 = sorted(valid_opt_clusters, key=len, reverse=True)[:4]
            top4_sorted = sorted(top4, key=lambda c: np.median(c))
            col_x_centers = [int(np.median(c)) for c in top4_sorted]
        else:
            col_start = x_min_bound + (col_width * 0.08)
            col_end = x_max_bound - (col_width * 0.05)
            col_x_centers = np.linspace(col_start, col_end, 4).astype(int)

        for q_idx, cy in enumerate(row_y_centers):
            q_num = col_idx * 10 + q_idx + 1
            for opt_idx, cx in enumerate(col_x_centers):
                final_grid.append((q_num, opt_idx, cx, cy))

    return final_grid


def compute_otsu_threshold(gray):
    """Computes global Otsu threshold on grayscale image array."""
    if HAS_CV2 and cv2 is not None:
        thresh_val, binary_inv = cv2.threshold(
            gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU
        )
        return thresh_val, binary_inv

    # Pure NumPy implementation
    hist, _ = np.histogram(gray, bins=256, range=(0, 256))
    total = gray.size
    sum_total = np.dot(np.arange(256), hist)
    current_max = 0
    threshold = 128
    sum_b = 0
    weight_b = 0

    for i in range(256):
        weight_b += hist[i]
        if weight_b == 0:
            continue
        weight_f = total - weight_b
        if weight_f == 0:
            break
        sum_b += i * hist[i]
        mean_b = sum_b / weight_b
        mean_f = (sum_total - sum_b) / weight_f
        var_between = weight_b * weight_f * ((mean_b - mean_f) ** 2)
        if var_between > current_max:
            current_max = var_between
            threshold = i

    binary_inv = (gray < threshold).astype(np.uint8) * 255
    return threshold, binary_inv


def evaluate_answers(warped, gray, final_grid, expected_r):
    """
    Evaluates filled bubbles for questions 1 to 30.
    Returns: (results, debug_result, question_details)
    """
    H, W = gray.shape[:2]
    _, binary_inv = compute_otsu_threshold(gray)

    bubble_radius = int(expected_r)
    sample_r = int(bubble_radius * 0.75)
    circle_area = np.pi * (sample_r**2)

    questions = {}
    for q_num, opt_idx, cx, cy in final_grid:
        if q_num not in questions:
            questions[q_num] = []
        questions[q_num].append((opt_idx, cx, cy))

    for q_num in questions:
        questions[q_num].sort(key=lambda item: item[0])

    results = {}
    details = {}
    debug_result = warped.copy()

    for q_num in sorted(questions.keys()):
        options_data = questions[q_num]
        pixel_counts = []

        for opt_idx, cx, cy in options_data:
            if HAS_CV2 and cv2 is not None:
                mask = np.zeros(binary_inv.shape, dtype=np.uint8)
                cv2.circle(mask, (cx, cy), sample_r, 255, -1)
                filled_pixels = cv2.countNonZero(
                    cv2.bitwise_and(binary_inv, binary_inv, mask=mask)
                )
            else:
                y_min = max(0, cy - sample_r)
                y_max = min(H, cy + sample_r + 1)
                x_min = max(0, cx - sample_r)
                x_max = min(W, cx + sample_r + 1)
                patch = binary_inv[y_min:y_max, x_min:x_max]
                py, px = np.ogrid[y_min - cy : y_max - cy, x_min - cx : x_max - cx]
                cmask = (px**2 + py**2) <= (sample_r**2)
                filled_pixels = int(np.sum(patch[cmask] > 0))

            pixel_counts.append(filled_pixels)

        max_pixels = max(pixel_counts) if pixel_counts else 0
        best_opt_idx = int(np.argmax(pixel_counts)) if pixel_counts else 0

        is_filled = (max_pixels / circle_area) > 0.40 if circle_area > 0 else False
        sorted_counts = sorted(pixel_counts, reverse=True)
        is_distinct = (
            (sorted_counts[0] - sorted_counts[1]) > (0.15 * circle_area)
            if len(sorted_counts) > 1
            else is_filled
        )

        details[q_num] = {
            "pixel_counts": pixel_counts,
            "max_pixels": max_pixels,
            "fill_ratio": max_pixels / circle_area if circle_area > 0 else 0.0,
            "best_option_bangla": OPTION_LABELS[best_opt_idx],
            "best_option_english": ENGLISH_LABELS[best_opt_idx],
        }

        if is_filled and is_distinct:
            detected_choice = OPTION_LABELS[best_opt_idx]
            results[q_num] = detected_choice

            bcx, bcy = options_data[best_opt_idx][1], options_data[best_opt_idx][2]
            if HAS_CV2 and cv2 is not None:
                cv2.circle(debug_result, (bcx, bcy), bubble_radius + 2, (0, 255, 0), 3)
            elif HAS_PIL:
                # Draw circle on RGB image using PIL or numpy
                rr = bubble_radius + 2
                for angle in np.linspace(0, 2 * np.pi, 120):
                    for dr in range(-1, 2):
                        px = int(bcx + (rr + dr) * np.cos(angle))
                        py = int(bcy + (rr + dr) * np.sin(angle))
                        if 0 <= px < W and 0 <= py < H:
                            debug_result[py, px] = [0, 255, 0]
        else:
            results[q_num] = "Blank / Invalid"

    return results, debug_result, details


def load_image(image_path):
    """Loads an RGB image from file path using OpenCV or Pillow."""
    if not os.path.exists(image_path):
        raise FileNotFoundError(f"Image could not be found at {image_path}")

    if HAS_CV2 and cv2 is not None:
        img = cv2.imread(image_path)
        if img is not None:
            return img

    if HAS_PIL:
        pil_img = Image.open(image_path).convert("RGB")
        return np.array(pil_img, dtype=np.uint8)

    raise ValueError(f"Image could not be loaded from {image_path}")


def save_image(path, img_array):
    """Saves RGB image to disk using OpenCV or Pillow."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    if HAS_CV2 and cv2 is not None:
        cv2.imwrite(path, img_array)
    elif HAS_PIL:
        Image.fromarray(img_array).save(path)


def scan_omr_image(image_path: str, output_path: str = None, show_plot: bool = True):
    """
    Full pipeline to scan an OMR sheet image and return results.
    """
    image = load_image(image_path)

    # 1. Perspective Transform
    corners = find_omr_contour(image)
    warped = perspective_transform(image, corners)
    H, W = warped.shape[:2]

    # 2. Bubble Candidate Detection
    unique_bubbles, expected_r, col_width, gray = detect_bubble_candidates(warped)

    # 3. Dynamic Grid Reconstruction
    final_grid = reconstruct_grid(unique_bubbles, W, H, col_width)

    # 4. Detect Filled Bubbles
    results, debug_result, details = evaluate_answers(
        warped, gray, final_grid, expected_r
    )

    # 5. Output Display
    print("=== OMR EVALUATION RESULTS ===")
    for q in range(1, 31):
        ans = results.get(q, "N/A")
        print(f"Question {q:02d}: {ans}")

    # Save output visualization
    if output_path:
        save_image(output_path, debug_result)
        print(f"\n[Annotated Result Saved] -> {output_path}")

    # Show visualization plot if requested and display available
    if show_plot and plt is not None:
        try:
            display_available = bool(
                os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")
            )
            if not display_available:
                matplotlib.use("Agg")

            plt.figure(figsize=(12, 14))
            rgb_vis = (
                cv2.cvtColor(debug_result, cv2.COLOR_BGR2RGB)
                if (HAS_CV2 and cv2 is not None)
                else debug_result
            )
            plt.imshow(rgb_vis)
            plt.title("OMR Answers Detected (Green Circles)")
            plt.axis("off")

            if display_available:
                plt.show()
            elif output_path is None:
                default_save = "output/omr_detected_result.png"
                os.makedirs("output", exist_ok=True)
                plt.savefig(default_save, bbox_inches="tight", dpi=150)
                print(f"[Plot saved to {default_save} (Headless environment)]")
            plt.close()
        except Exception as e:
            print(f"[Visualization note: {e}]")

    return {
        "results": results,
        "debug_result": debug_result,
        "details": details,
        "warped_shape": (H, W),
        "bubble_count": len(unique_bubbles),
    }


def crop_omr_grid_class910(image_path, target_width=1200):
    if not HAS_CV2 or cv2 is None:
        raise RuntimeError("OpenCV (cv2) is required for Class 9-10 OMR detection.")
    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Could not load image from {image_path}")
    h, w = img.shape[:2]
    aspect = h / w
    if aspect < 1.15:
        target_h = int(round(target_width * aspect))
        return cv2.resize(img, (target_width, target_h))

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    otsu_thresh, _ = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    x_mid_start = int(round(0.20 * w))
    x_mid_end = int(round(0.80 * w))

    # Top border: prominent horizontal line in y in [0.22*h .. 0.28*h]
    y_top_start = int(round(0.22 * h))
    y_top_end = int(round(0.28 * h))
    best_y1 = int(round(0.258 * h))
    max_top_row_dark = 0

    for y in range(y_top_start, y_top_end):
        dark_count = np.sum(gray[y, x_mid_start:x_mid_end] <= otsu_thresh)
        if dark_count > max_top_row_dark:
            max_top_row_dark = dark_count
            best_y1 = max(0, y - 5)

    # Bottom border: prominent horizontal line in y in [0.78*h .. 0.84*h]
    y_bot_start = int(round(0.78 * h))
    y_bot_end = int(round(0.84 * h))
    best_y2 = int(round(0.817 * h))
    max_bot_row_dark = 0

    for y in range(y_bot_start, y_bot_end):
        dark_count = np.sum(gray[y, x_mid_start:x_mid_end] <= otsu_thresh)
        if dark_count > max_bot_row_dark:
            max_bot_row_dark = dark_count
            best_y2 = min(h, y + 14)

    # Left border: search x in [0 .. 0.08*w]
    x_left_end = int(round(0.08 * w))
    best_x1 = 0
    table_h = max(1, best_y2 - best_y1)
    for x in range(x_left_end):
        col_dark = np.sum(gray[best_y1:best_y2:2, x] <= otsu_thresh)
        if col_dark > (table_h / 2) * 0.15:
            best_x1 = max(0, x - 2)
            break

    # Right border: search x in [0.88*w .. w]
    x_right_start = int(round(0.88 * w))
    best_x2 = int(round(0.936 * w))
    for x in range(w - 1, x_right_start, -1):
        col_dark = np.sum(gray[best_y1:best_y2:2, x] <= otsu_thresh)
        if col_dark > (table_h / 2) * 0.10:
            best_x2 = min(w, x + 16)
            break

    cropped = img[best_y1:best_y2, best_x1:best_x2]
    c_h, c_w = cropped.shape[:2]
    c_aspect = c_h / c_w
    final_h = int(round(target_width * c_aspect))
    return cv2.resize(cropped, (target_width, final_h))


def scan_class9_10_image(image_path, output_path=None, show_plot=True):
    """
    Evaluates Class 9-10 OMR sheet, extracting:
    - 30 Questions (Q1-15 & Q16-30)
    - Roll Number (6 digits)
    - Set Code (ক, খ, গ, ঘ)
    - Registration Number (10 digits)
    - Subject Code (3 digits)
    """
    cropped = crop_omr_grid_class910(image_path)
    H, W = cropped.shape[:2]
    gray = cv2.cvtColor(cropped, cv2.COLOR_BGR2GRAY)
    otsu_thresh, _ = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    annotated = cropped.copy()

    # Color helpers (BGR)
    yellow_box = (0, 220, 255)
    circle_green = (0, 220, 0)
    dot_red = (30, 30, 220)
    filled_highlight = (50, 230, 0)

    def draw_box(ymin_p, xmin_p, ymax_p, xmax_p):
        x1 = int(round(xmin_p * W))
        y1 = int(round(ymin_p * H))
        x2 = int(round(xmax_p * W))
        y2 = int(round(ymax_p * H))
        cv2.rectangle(annotated, (x1, y1), (x2, y2), yellow_box, 2)

    def eval_bubble_metrics(cx, cy, r=11):
        cx, cy = int(round(cx)), int(round(cy))
        sample_r = max(4, int(round(r * 0.70)))
        mask = np.zeros(gray.shape, dtype=np.uint8)
        cv2.circle(mask, (cx, cy), sample_r, 255, -1)
        total_pixels = int(np.sum(mask == 255))
        if total_pixels == 0:
            return 0.0, 255.0
        dark_pixels = int(np.sum((gray <= otsu_thresh) & (mask == 255)))
        fill_ratio = dark_pixels / total_pixels
        mean_lum = float(np.mean(gray[mask == 255]))
        return fill_ratio, mean_lum

    def draw_bubble_mark(cx, cy, r=11, is_filled=False):
        cx, cy = int(round(cx)), int(round(cy))
        cv2.circle(annotated, (cx, cy), r, filled_highlight if is_filled else circle_green, 2)
        cv2.circle(annotated, (cx, cy), 2, dot_red, -1)
        if is_filled:
            cv2.circle(annotated, (cx, cy), r - 1, filled_highlight, -1)

    # Section boxes
    draw_box(0.080, 0.115, 0.900, 0.270)  # Q1_15
    draw_box(0.080, 0.345, 0.900, 0.495)  # Q16_30
    draw_box(0.075, 0.515, 0.465, 0.700)  # Roll
    draw_box(0.075, 0.730, 0.295, 0.785)  # Set
    draw_box(0.530, 0.530, 0.905, 0.830)  # Registration
    draw_box(0.530, 0.835, 0.905, 0.950)  # Subject

    scale_x = W / 1200.0
    scale_y = H / 924.0

    # 1. Set Code
    set_x = 907.0 * scale_x
    set_y_list = [y * scale_y for y in [109.5, 151.5, 193.5, 234.5]]
    set_labels = ['ক', 'খ', 'গ', 'ঘ']
    set_metrics = [eval_bubble_metrics(set_x, y, r=int(round(12 * scale_x))) for y in set_y_list]
    set_scores = [m[0] for m in set_metrics]
    sorted_set_idx = np.argsort(set_scores)[::-1]
    top_set_idx = int(sorted_set_idx[0])
    sec_set_idx = int(sorted_set_idx[1])
    is_set_filled = (
        set_scores[top_set_idx] >= 0.50
        and (set_scores[top_set_idx] - set_scores[sec_set_idx]) >= 0.14
        and set_metrics[top_set_idx][1] < 160.0
    )
    detected_set = set_labels[top_set_idx] if is_set_filled else None
    for idx, y in enumerate(set_y_list):
        draw_bubble_mark(set_x, y, r=int(round(12 * scale_x)), is_filled=(is_set_filled and idx == top_set_idx))

    # 2. Roll Number (6 digits)
    roll_x_cols = [x * scale_x for x in [639.6, 674.0, 710.4, 744.3, 781.6, 817.1]]
    roll_y_rows = [y * scale_y for y in [97.5, 129.5, 165.5, 197.5, 228.5, 264.5, 296.5, 330.5, 363.5, 396.5]]
    roll_digits = []
    for cx in roll_x_cols:
        metrics = [eval_bubble_metrics(cx, ry, r=int(round(10 * scale_x))) for ry in roll_y_rows]
        scores = [m[0] for m in metrics]
        sorted_idx = np.argsort(scores)[::-1]
        best_d = int(sorted_idx[0])
        sec_d = int(sorted_idx[1])
        filled = (
            scores[best_d] >= 0.50
            and (scores[best_d] - scores[sec_d]) >= 0.14
            and metrics[best_d][1] < 160.0
        )
        roll_digits.append(str(best_d) if filled else "")
        for r_idx, ry in enumerate(roll_y_rows):
            draw_bubble_mark(cx, ry, r=int(round(10 * scale_x)), is_filled=(filled and r_idx == best_d))
    detected_roll = "".join(roll_digits) if any(d != "" for d in roll_digits) else None

    # 3. Subject Code (3 digits)
    sub_x_cols = [x * scale_x for x in [1025.0, 1069.0, 1113.0]]
    sub_y_rows = [y * scale_y for y in [512.5, 546.5, 578.5, 610.5, 645.5, 678.5, 713.5, 744.5, 777.5, 810.5]]
    sub_digits = []
    # col 0: digits 1 (row 1), 2 (row 2)
    s1 = eval_bubble_metrics(sub_x_cols[0], sub_y_rows[1], r=int(round(10 * scale_x)))
    s2 = eval_bubble_metrics(sub_x_cols[0], sub_y_rows[2], r=int(round(10 * scale_x)))
    s1_filled = s1[0] >= 0.50 and (s1[0] - s2[0]) >= 0.14 and s1[1] < 160.0
    s2_filled = s2[0] >= 0.50 and (s2[0] - s1[0]) >= 0.14 and s2[1] < 160.0
    if s1_filled:
        sub_digits.append("1")
    elif s2_filled:
        sub_digits.append("2")
    else:
        sub_digits.append("")
    draw_bubble_mark(sub_x_cols[0], sub_y_rows[1], r=int(round(10 * scale_x)), is_filled=s1_filled)
    draw_bubble_mark(sub_x_cols[0], sub_y_rows[2], r=int(round(10 * scale_x)), is_filled=s2_filled)

    for cx in sub_x_cols[1:]:
        metrics = [eval_bubble_metrics(cx, ry, r=int(round(10 * scale_x))) for ry in sub_y_rows]
        scores = [m[0] for m in metrics]
        sorted_idx = np.argsort(scores)[::-1]
        best_d = int(sorted_idx[0])
        sec_d = int(sorted_idx[1])
        filled = (
            scores[best_d] >= 0.50
            and (scores[best_d] - scores[sec_d]) >= 0.14
            and metrics[best_d][1] < 160.0
        )
        sub_digits.append(str(best_d) if filled else "")
        for r_idx, ry in enumerate(sub_y_rows):
            draw_bubble_mark(cx, ry, r=int(round(10 * scale_x)), is_filled=(filled and r_idx == best_d))
    detected_sub = "".join(sub_digits) if any(d != "" for d in sub_digits) else None

    # 4. Registration Number (10 digits)
    reg_x_cols = [x * scale_x for x in [658.1, 693.7, 728.6, 764.0, 800.0, 835.4, 870.4, 905.1, 942.2, 976.0]]
    reg_y_rows = [y * scale_y for y in [514.5, 546.5, 579.5, 610.5, 645.5, 678.5, 713.5, 744.5, 777.5, 810.5]]
    reg_digits = []
    for cx in reg_x_cols:
        metrics = [eval_bubble_metrics(cx, ry, r=int(round(10 * scale_x))) for ry in reg_y_rows]
        scores = [m[0] for m in metrics]
        sorted_idx = np.argsort(scores)[::-1]
        best_d = int(sorted_idx[0])
        sec_d = int(sorted_idx[1])
        filled = (
            scores[best_d] >= 0.50
            and (scores[best_d] - scores[sec_d]) >= 0.14
            and metrics[best_d][1] < 160.0
        )
        reg_digits.append(str(best_d) if filled else "")
        for r_idx, ry in enumerate(reg_y_rows):
            draw_bubble_mark(cx, ry, r=int(round(10 * scale_x)), is_filled=(filled and r_idx == best_d))
    detected_reg = "".join(reg_digits) if any(d != "" for d in reg_digits) else None

    # 5. Q1..15 & Q16..30
    q_rows_y = [
        y * scale_y
        for y in [
            105.5, 154.5, 203.5, 252.5, 303.5, 353.5, 403.5, 451.5, 501.5, 551.5, 600.5, 650.5, 700.5, 750.5, 798.5
        ]
    ]
    q1_x_cols = [x * scale_x for x in [154.5, 205.0, 255.0, 304.5]]
    q2_x_cols = [x * scale_x for x in [428.5, 476.5, 525.5, 574.5]]
    answers = {}
    options = ["A", "B", "C", "D"]

    # Evaluate Q1..15
    for q_idx in range(15):
        q_num = q_idx + 1
        metrics = [eval_bubble_metrics(cx, q_rows_y[q_idx], r=int(round(11 * scale_x))) for cx in q1_x_cols]
        scores = [m[0] for m in metrics]
        sorted_idx = np.argsort(scores)[::-1]
        top_idx = int(sorted_idx[0])
        sec_idx = int(sorted_idx[1])
        top_mean = metrics[top_idx][1]

        is_filled = scores[top_idx] >= 0.48 and (scores[top_idx] - scores[sec_idx]) >= 0.14 and top_mean < 160.0
        is_multiple = scores[top_idx] >= 0.45 and scores[sec_idx] >= 0.45 and (scores[top_idx] - scores[sec_idx]) < 0.12 and top_mean < 160.0

        if is_filled:
            answers[q_num] = options[top_idx]
        elif is_multiple:
            answers[q_num] = "MULTIPLE"
        else:
            answers[q_num] = "BLANK"

        for opt_idx, cx in enumerate(q1_x_cols):
            draw_bubble_mark(cx, q_rows_y[q_idx], r=int(round(11 * scale_x)), is_filled=(is_filled and opt_idx == top_idx))

    # Evaluate Q16..30
    for q_idx in range(15):
        q_num = q_idx + 16
        metrics = [eval_bubble_metrics(cx, q_rows_y[q_idx], r=int(round(11 * scale_x))) for cx in q2_x_cols]
        scores = [m[0] for m in metrics]
        sorted_idx = np.argsort(scores)[::-1]
        top_idx = int(sorted_idx[0])
        sec_idx = int(sorted_idx[1])
        top_mean = metrics[top_idx][1]

        is_filled = scores[top_idx] >= 0.48 and (scores[top_idx] - scores[sec_idx]) >= 0.14 and top_mean < 160.0
        is_multiple = scores[top_idx] >= 0.45 and scores[sec_idx] >= 0.45 and (scores[top_idx] - scores[sec_idx]) < 0.12 and top_mean < 160.0

        if is_filled:
            answers[q_num] = options[top_idx]
        elif is_multiple:
            answers[q_num] = "MULTIPLE"
        else:
            answers[q_num] = "BLANK"

        for opt_idx, cx in enumerate(q2_x_cols):
            draw_bubble_mark(cx, q_rows_y[q_idx], r=int(round(11 * scale_x)), is_filled=(is_filled and opt_idx == top_idx))

    print("\n" + "=" * 55)
    print(" CLASS 9-10 OMR DETECTION RESULTS ")
    print("=" * 55)
    print(f"Set Code:             {detected_set if detected_set else '-'}")
    print(f"Roll Number:          {detected_roll if detected_roll else '-'}")
    print(f"Registration Number:  {detected_reg if detected_reg else '-'}")
    print(f"Subject Code:         {detected_sub if detected_sub else '-'}")
    print("-" * 55)
    print("Question Answers (Q1 to Q30):")
    for q in range(1, 31):
        print(f"  Q{q:02d}: {answers.get(q, 'BLANK')}", end="\n" if q % 5 == 0 else "  |  ")
    print("=" * 55 + "\n")

    if output_path:
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        cv2.imwrite(output_path, annotated)
        print(f"[Annotated output saved to {output_path}]")

    return {
        "set_code": detected_set,
        "roll_number": detected_roll,
        "registration_number": detected_reg,
        "subject_code": detected_sub,
        "answers": answers,
        "annotated_image": annotated,
    }


def find_default_image(mode="class_6_8"):
    if mode == "class_9_10":
        candidates = [
            "assets/test_images/bangla_omr_class9_10_sample.jpg",
        ]
    else:
        candidates = [
            "ome3.jpeg",
            "omr3.jpeg",
            "assets/test_images/bangla_omr_sample.jpg",
            "assets/test_images/test_marked_sheet.png",
        ]
    for p in candidates:
        if os.path.exists(p):
            return p
    return candidates[0]


def main():
    parser = argparse.ArgumentParser(
        description="OMR Sheet Detection and Evaluation (Class 6-8 and Class 9-10 Formats)"
    )
    parser.add_argument(
        "--mode",
        choices=["class_6_8", "class_9_10"],
        default="class_6_8",
        help="OMR Sheet format mode: 'class_6_8' (basic 30-Q) or 'class_9_10' (4-set with Roll, Reg, Sub, Set Code)",
    )
    parser.add_argument(
        "--image",
        default=None,
        help="Path to input OMR photograph/image",
    )
    parser.add_argument(
        "--output",
        default="output/omr_detected_result.png",
        help="Path to save annotated debug image",
    )
    parser.add_argument(
        "--no-show",
        action="store_true",
        help="Do not display interactive matplotlib plot",
    )
    args = parser.parse_args()

    image_path = args.image or find_default_image(args.mode)

    try:
        if args.mode == "class_9_10":
            scan_class9_10_image(image_path, output_path=args.output, show_plot=not args.no_show)
        else:
            scan_omr_image(image_path, output_path=args.output, show_plot=not args.no_show)
    except Exception as e:
        print(f"Error executing OMR scanner: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
