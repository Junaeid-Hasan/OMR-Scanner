"""
Image Preprocessing Pipeline
Handles image loading, resolution normalization, grayscale conversion,
illumination compensation, contrast enhancement, noise filtering, and edge map creation.
"""

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, uniform_filter, sobel
from typing import Tuple, Optional


class ImagePreprocessor:
    def __init__(self, target_max_dim: int = 1800):
        self.target_max_dim = target_max_dim

    def load_image(self, path: str) -> np.ndarray:
        """Loads an image from disk into an RGB numpy uint8 array."""
        img = Image.open(path).convert("RGB")
        arr = np.array(img, dtype=np.uint8)
        return arr

    def normalize_resolution(self, img_rgb: np.ndarray) -> Tuple[np.ndarray, float]:
        """
        Downscales the image if larger than target_max_dim to optimize CPU time,
        returning the resized image and the scale factor.
        """
        h, w = img_rgb.shape[:2]
        max_dim = max(h, w)
        if max_dim <= self.target_max_dim:
            return img_rgb.copy(), 1.0

        scale = self.target_max_dim / float(max_dim)
        new_w = int(round(w * scale))
        new_h = int(round(h * scale))
        pil_img = Image.fromarray(img_rgb).resize((new_w, new_h), Image.Resampling.BILINEAR)
        return np.array(pil_img, dtype=np.uint8), scale

    def to_grayscale(self, img_rgb: np.ndarray) -> np.ndarray:
        """Converts RGB image to grayscale float32 array in [0, 255]."""
        if len(img_rgb.shape) == 2:
            return img_rgb.astype(np.float32)
        gray = 0.299 * img_rgb[..., 0] + 0.587 * img_rgb[..., 1] + 0.114 * img_rgb[..., 2]
        return gray.astype(np.float32)

    def compensate_illumination(self, gray: np.ndarray, bg_sigma: float = 35.0) -> np.ndarray:
        """
        Removes uneven lighting, glare, and shadows across the sheet.
        Estimates smooth background luminance via large Gaussian blur and divides image by background.
        """
        background = gaussian_filter(gray, sigma=bg_sigma)
        background = np.clip(background, 15.0, 255.0)

        # Normalize: preserve local ink contrast regardless of global shadow
        normalized = (gray / background) * 220.0
        normalized = np.clip(normalized, 0.0, 255.0).astype(np.float32)
        return normalized

    def enhance_contrast(self, gray: np.ndarray) -> np.ndarray:
        """Applies percentile-based contrast stretching."""
        p2, p98 = np.percentile(gray, (2, 98))
        if p98 > p2:
            stretched = (gray - p2) / (p98 - p2) * 255.0
            return np.clip(stretched, 0.0, 255.0).astype(np.float32)
        return gray

    def reduce_noise(self, gray: np.ndarray, sigma: float = 1.0) -> np.ndarray:
        """Applies Gaussian smoothing to suppress sensor noise."""
        return gaussian_filter(gray, sigma=sigma)

    def adaptive_threshold(self, gray: np.ndarray, window_size: int = 25, c: float = 12.0) -> np.ndarray:
        """
        Computes local adaptive binary mask where True/1 indicates dark ink pixels.
        """
        local_mean = uniform_filter(gray, size=window_size)
        ink_mask = gray < (local_mean - c)
        return ink_mask

    def detect_edges(self, gray: np.ndarray) -> np.ndarray:
        """Computes gradient magnitude map for contour & sheet boundary detection."""
        smoothed = gaussian_filter(gray, sigma=1.5)
        sx = sobel(smoothed, axis=1)
        sy = sobel(smoothed, axis=0)
        magnitude = np.hypot(sx, sy)
        if magnitude.max() > 0:
            magnitude = (magnitude / magnitude.max()) * 255.0
        return magnitude.astype(np.float32)

    def process(self, img_rgb: np.ndarray) -> dict:
        """Full preprocessing pipeline returning all intermediate representations."""
        norm_rgb, scale = self.normalize_resolution(img_rgb)
        raw_gray = self.to_grayscale(norm_rgb)
        denoised = self.reduce_noise(raw_gray, sigma=1.0)
        edges = self.detect_edges(denoised)

        return {
            "original_rgb": img_rgb,
            "normalized_rgb": norm_rgb,
            "scale": scale,
            "raw_gray": raw_gray,
            "denoised_gray": denoised,
            "edges": edges,
        }
