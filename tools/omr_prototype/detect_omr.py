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
    points = np.array(points, dtype=np.float32)

    s = points.sum(axis=1)
    diff = np.diff(points, axis=1).flatten()

    top_left = points[np.argmin(s)]
    top_right = points[np.argmin(diff)]
    bottom_right = points[np.argmax(s)]
    bottom_left = points[np.argmax(diff)]

    return np.array([top_left, top_right, bottom_right, bottom_left], dtype=np.float32)


def find_omr_contour(image):
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

    return np.array([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]], dtype=np.float32)


def perspective_transform(image, corners):
    rect = order_points(corners)
    tl, tr, br, bl = rect

    width_top = np.linalg.norm(tr - tl)
    width_bottom = np.linalg.norm(br - bl)
    max_width = int(max(width_top, width_bottom))

    height_left = np.linalg.norm(bl - tl)
    height_right = np.linalg.norm(br - tr)
    max_height = int(max(height_left, height_right))

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

    if HAS_PIL:
        pil_img = Image.fromarray(image)
        warped = pil_img.resize((max_width, max_height))
        return np.array(warped)

    return image


def detect_bubble_candidates(warped):
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

            if cy < H * 0.08:
                continue

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

    unique_bubbles = []
    for c in candidates:
        x1, y1, r1 = c
        if not any(np.hypot(x1 - x2, y1 - y2) < r1 * 0.7 for x2, y2, _ in unique_bubbles):
            unique_bubbles.append(c)

    return unique_bubbles, expected_r, col_width, gray


def reconstruct_grid(unique_bubbles, W, H, col_width):
    y_coords = sorted([pt[1] for pt in unique_bubbles])
    row_clusters = []
    for y in y_coords:
        if not row_clusters or abs(np.mean(row_clusters[-1]) - y) > (H / 25):
            row_clusters.append([y])
        else:
            row_clusters[-1].append(y)

    valid_row_clusters = [c for c in row_clusters if len(c) >= 3]
    if len(valid_row_clusters) == 10:
        row_y_centers = [int(np.median(cluster)) for cluster in valid_row_clusters]
    elif len(valid_row_clusters) > 10:
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
    if HAS_CV2 and cv2 is not None:
        thresh_val, binary_inv = cv2.threshold(
            gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU
        )
        return thresh_val, binary_inv

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
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    if HAS_CV2 and cv2 is not None:
        cv2.imwrite(path, img_array)
    elif HAS_PIL:
        Image.fromarray(img_array).save(path)


def scan_omr_image(image_path: str, output_path: str = None, show_plot: bool = True):
    image = load_image(image_path)

    corners = find_omr_contour(image)
    warped = perspective_transform(image, corners)
    H, W = warped.shape[:2]

    unique_bubbles, expected_r, col_width, gray = detect_bubble_candidates(warped)
    final_grid = reconstruct_grid(unique_bubbles, W, H, col_width)
    results, debug_result, details = evaluate_answers(
        warped, gray, final_grid, expected_r
    )

    print("=== OMR EVALUATION RESULTS ===")
    for q in range(1, 31):
        ans = results.get(q, "N/A")
        print(f"Question {q:02d}: {ans}")

    if output_path:
        save_image(output_path, debug_result)
        print(f"\n[Annotated Result Saved] -> {output_path}")

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


def find_default_image():
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
        description="OMR Sheet Detection and Evaluation (Bangla 30-Q Format)"
    )
    parser.add_argument(
        "--image",
        default=find_default_image(),
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

    try:
        scan_omr_image(args.image, output_path=args.output, show_plot=not args.no_show)
    except Exception as e:
        print(f"Error executing OMR scanner: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
