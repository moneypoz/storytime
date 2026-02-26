"""
StoryTime — "Lion's Mane of Stardust" App Icon Generator
Produces a 1024x1024 PNG matching the design specification.
"""

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import math, random, os

SEED = 42
random.seed(SEED)
np.random.seed(SEED)

SIZE = 1024
CX, CY = SIZE / 2, SIZE / 2

# ── Color helpers ──────────────────────────────────────────────────────────────

def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def hex_to_rgbf(h):
    return tuple(c / 255.0 for c in hex_to_rgb(h))

# Palette
MIDNIGHT    = "#020617"
ACCENT_VIO  = "#6366f1"
MANE_GOLD   = "#F59E0B"
MANE_AMBER  = "#D97706"
MANE_BRIGHT = "#FBBF24"
LAVENDER    = "#C4B5FD"
ROSE_WISP   = "#F9A8D4"
MOON_WHITE  = "#FFF9E6"
KEY_VIOLET  = "#8B5CF6"

# Mane geometry
OUTER_R = SIZE * 0.42   # 430px
INNER_R = SIZE * 0.18   # 184px
MID_R   = (OUTER_R + INNER_R) / 2  # ~307px — ring center


# ── Pixel-space utilities ──────────────────────────────────────────────────────

def make_grid():
    Y, X = np.mgrid[0:SIZE, 0:SIZE]
    return X.astype(np.float32), Y.astype(np.float32)


def radial_dist(X, Y):
    return np.sqrt((X - CX)**2 + (Y - CY)**2)


def screen_blend(base, color_rgb, alpha_map):
    """Screen blend a solid color weighted by alpha_map (0..1) onto base float32 RGBA."""
    cr, cg, cb = [c / 255.0 for c in color_rgb]
    for ch, c in enumerate([cr, cg, cb]):
        base[:, :, ch] = 1.0 - (1.0 - base[:, :, ch]) * (1.0 - alpha_map * c)


def add_radial_glow(canvas, cx, cy, radius, color_rgb, peak_opacity, falloff=1.8):
    X, Y = make_grid()
    dist = np.sqrt((X - cx)**2 + (Y - cy)**2)
    t = np.clip(1.0 - dist / radius, 0, 1) ** falloff
    screen_blend(canvas, color_rgb, t * peak_opacity)


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def particle_color(r, inner_r=INNER_R, outer_r=OUTER_R):
    norm = (r - inner_r) / (outer_r - inner_r)
    gold  = hex_to_rgb(MANE_GOLD)
    white = hex_to_rgb(MOON_WHITE)
    lav   = hex_to_rgb(LAVENDER)
    rose  = hex_to_rgb(ROSE_WISP)
    cwh   = (200, 210, 240)
    norm  = max(0.0, min(1.0, norm))
    if norm < 0.35:
        return lerp_color(gold, white, norm / 0.35)
    elif norm < 0.65:
        return lerp_color(white, lav, (norm - 0.35) / 0.30)
    elif norm < 0.85:
        return lerp_color(lav, rose, (norm - 0.65) / 0.20)
    else:
        return lerp_color(rose, cwh, (norm - 0.85) / 0.15)


def ring_position(inner_r=INNER_R, outer_r=OUTER_R, bias=None):
    """Return (x, y, angle, r) with optional density bias."""
    for _ in range(300):
        angle = random.uniform(0, 2 * math.pi)
        r = random.uniform(inner_r, outer_r * 1.08)
        accept = True
        if bias is not None:
            norm = (r - inner_r) / (outer_r - inner_r)
            if norm < 0.15:
                accept = random.random() < 0.10
            elif norm < 0.50:
                accept = random.random() < 0.40
            elif norm <= 0.82:
                accept = True  # peak band always accept
            else:
                accept = random.random() < 0.55
        if accept:
            return CX + r * math.cos(angle), CY + r * math.sin(angle), angle, r
    return CX + MID_R, CY, 0, MID_R


# ── Layer builders ─────────────────────────────────────────────────────────────

def build_background(canvas):
    """Layer 1: Midnight base fill."""
    mr, mg, mb = hex_to_rgbf(MIDNIGHT)
    canvas[:, :, 0] = mr
    canvas[:, :, 1] = mg
    canvas[:, :, 2] = mb
    canvas[:, :, 3] = 1.0


def build_nebula(canvas):
    """Layer 2: Nebula bloom — three screen-blended radial glows."""
    # Core warmth — amber, 28% radius, 35%
    add_radial_glow(canvas, CX, CY, SIZE * 0.28, hex_to_rgb(MANE_GOLD), 0.38)
    # Violet sky — 50% radius, 22%
    add_radial_glow(canvas, CX, CY, SIZE * 0.50, hex_to_rgb(ACCENT_VIO), 0.24)
    # Upper-left key light — 40% radius, 18%
    add_radial_glow(canvas, SIZE * 0.20, SIZE * 0.18,
                    SIZE * 0.40, hex_to_rgb(KEY_VIOLET), 0.20)


def build_mane_ring_glow(canvas):
    """
    Structural ring glow — ensures the mane shape reads at ALL sizes.
    Adds a soft toroidal amber/golden glow centered on the ring path.
    """
    X, Y = make_grid()
    dist_from_center = np.sqrt((X - CX)**2 + (Y - CY)**2)

    # Signed distance from the ring mid-line
    dist_from_ring = np.abs(dist_from_center - MID_R)

    # Ring width: half-width at half-max ≈ 90px
    ring_hw = 90.0
    t = np.exp(-(dist_from_ring ** 2) / (2 * (ring_hw * 0.55) ** 2))

    # Mask: only glow within [INNER_R*0.5 .. OUTER_R*1.2]
    mask = (dist_from_center >= INNER_R * 0.5) & (dist_from_center <= OUTER_R * 1.25)
    t[~mask] = 0.0

    # Color temperature: amber at ring mid, cooler outside
    outer_norm = np.clip((dist_from_center - INNER_R) / (OUTER_R - INNER_R), 0, 1)
    gold_r, gold_g, gold_b = hex_to_rgbf(MANE_GOLD)
    amber_r, amber_g, amber_b = hex_to_rgbf(MANE_AMBER)

    # Warm amber ring glow (strong)
    screen_blend(canvas, hex_to_rgb(MANE_GOLD), t * 0.78)

    # Secondary warm bright pass
    t2 = np.exp(-(dist_from_ring ** 2) / (2 * (ring_hw * 0.30) ** 2)) * mask
    screen_blend(canvas, hex_to_rgb(MANE_BRIGHT), t2 * 0.55)

    # Outer lavender/violet bloom trailing off
    outer_mask = (dist_from_center > MID_R) & (dist_from_center < OUTER_R * 1.35)
    outer_t = np.clip((dist_from_center - MID_R) / (OUTER_R * 0.35), 0, 1)
    outer_glow = t * outer_t * outer_mask.astype(float)
    screen_blend(canvas, hex_to_rgb(LAVENDER), outer_glow * 0.28)


def build_particles(base_img):
    """
    Layer 3: Draw particles on a separate RGBA PIL layer, then composite.
    Returns composited image.
    """
    # particle_layer: per-particle crisp dots
    pil = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(pil)

    # --- Micro dust: 300 particles, 1-4 px
    for _ in range(300):
        x, y, angle, r = ring_position(bias=True)
        sz = random.uniform(1.0, 4.0)
        op = int(random.uniform(0.40, 0.80) * 255)
        c = particle_color(r)
        draw.ellipse([x - sz, y - sz, x + sz, y + sz],
                     fill=(c[0], c[1], c[2], op))

    # --- Core glow orbs: 100 particles, 4-10 px
    for _ in range(100):
        x, y, angle, r = ring_position(bias=True)
        sz = random.uniform(4.0, 10.0)
        op = int(random.uniform(0.80, 1.0) * 255)
        c = particle_color(r)
        draw.ellipse([x - sz, y - sz, x + sz, y + sz],
                     fill=(c[0], c[1], c[2], op))

    # --- Feature stars: 28 particles, 12-18 px, bright core + amber halo
    for _ in range(28):
        x, y, angle, r = ring_position(INNER_R * 1.1, OUTER_R * 0.97, bias=True)
        sz = random.uniform(12.0, 18.0)
        halo_c = hex_to_rgb(MANE_GOLD)
        draw.ellipse([x - sz, y - sz, x + sz, y + sz],
                     fill=(halo_c[0], halo_c[1], halo_c[2], 160))
        core_sz = sz * 0.42
        draw.ellipse([x - core_sz, y - core_sz, x + core_sz, y + core_sz],
                     fill=(255, 250, 220, 255))

    # --- Light streaks: 12 clock positions
    for i in range(12):
        clock_angle = (i / 12.0) * 2 * math.pi - math.pi / 2
        streak_r = OUTER_R * random.uniform(0.72, 1.00)
        sx = CX + streak_r * math.cos(clock_angle)
        sy = CY + streak_r * math.sin(clock_angle)
        length = random.uniform(8.0, 14.0)
        ex = sx + length * math.cos(clock_angle)
        ey = sy + length * math.sin(clock_angle)
        op = int(random.uniform(0.30, 0.45) * 255)
        ww = hex_to_rgb(MOON_WHITE)
        draw.line([(sx, sy), (ex, ey)], fill=(ww[0], ww[1], ww[2], op), width=1)

    # Glow passes (multi-radius bloom: 2px + 5px + 12px)
    g1 = pil.filter(ImageFilter.GaussianBlur(radius=2.0))
    g2 = pil.filter(ImageFilter.GaussianBlur(radius=5.5))
    g3 = pil.filter(ImageFilter.GaussianBlur(radius=14.0))

    # Composite glow layers (g3 weakest, g1 sharpest)
    result = base_img.copy()
    result = Image.alpha_composite(result, g3)
    result = Image.alpha_composite(result, g2)
    result = Image.alpha_composite(result, g1)
    result = Image.alpha_composite(result, pil)   # crisp dots on top
    return result


def build_glass_disc(img):
    """Layer 4: 3D Glass Disc Overlay."""
    disc_r = SIZE * 0.43

    # Shadow bloom behind disc (lower-right)
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sdraw  = ImageDraw.Draw(shadow)
    offset = 35
    sdraw.ellipse([CX - disc_r + offset, CY - disc_r + offset,
                   CX + disc_r + offset, CY + disc_r + offset],
                  fill=(0, 0, 0, int(0.15 * 255)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=26))
    img = Image.alpha_composite(img, shadow)

    # Frosted disc fill
    glass = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glass)
    gdraw.ellipse([CX - disc_r, CY - disc_r, CX + disc_r, CY + disc_r],
                  fill=(255, 255, 255, int(0.10 * 255)))

    # Edge stroke ring (top-left bright, bottom-right dim)
    stroke_r = disc_r + 0.5
    for deg in range(0, 360, 2):
        a = math.radians(deg)
        t = (math.cos(a - math.radians(225)) + 1) / 2
        op = int((0.22 * t + 0.04 * (1 - t)) * 255)
        px = CX + stroke_r * math.cos(a)
        py = CY + stroke_r * math.sin(a)
        gdraw.ellipse([px - 1.5, py - 1.5, px + 1.5, py + 1.5],
                      fill=(255, 255, 255, op))

    img = Image.alpha_composite(img, glass)

    # Specular catchlight — inside the disc, upper-left quadrant
    # Disc center (512,512), radius 440. Catchlight ~25% in from the 10-o'clock edge.
    # Position at ~(285, 265) which is 330px from center — well inside disc.
    spec_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    spec_cx, spec_cy = int(SIZE * 0.278), int(SIZE * 0.258)   # (285, 264)
    spec_w, spec_h   = int(SIZE * 0.075), int(SIZE * 0.032)   # 77x33px

    # Build on a padded temp canvas so blur has room
    pad = 60
    tmp_w, tmp_h = spec_w * 2 + pad * 2, spec_h * 2 + pad * 2
    tmp = Image.new("RGBA", (tmp_w, tmp_h), (0, 0, 0, 0))
    tdraw = ImageDraw.Draw(tmp)
    cx0, cy0 = tmp_w // 2, tmp_h // 2
    tdraw.ellipse([cx0 - spec_w, cy0 - spec_h, cx0 + spec_w, cy0 + spec_h],
                  fill=(255, 255, 255, int(0.72 * 255)))
    tmp = tmp.filter(ImageFilter.GaussianBlur(radius=spec_h * 0.55))
    tmp = tmp.rotate(-38, expand=True, resample=Image.BICUBIC)
    paste_x = spec_cx - tmp.width  // 2
    paste_y = spec_cy - tmp.height // 2
    spec_layer.paste(tmp, (paste_x, paste_y), tmp)

    img = Image.alpha_composite(img, spec_layer)
    return img


def build_vignette(img):
    """Layer 5: Global vignette — draws eye inward."""
    X, Y = make_grid()
    dist = np.sqrt((X - CX)**2 + (Y - CY)**2)
    max_d = math.sqrt(2) * SIZE / 2
    t = np.clip(dist / max_d, 0, 1) ** 1.4
    alpha = (t * 0.35 * 255).astype(np.uint8)
    vig = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    vig[:, :, 3] = alpha
    vig_img = Image.fromarray(vig, "RGBA")
    return Image.alpha_composite(img, vig_img)


# ── Main ──────────────────────────────────────────────────────────────────────

def build_icon():
    # Float32 RGBA canvas 0..1
    canvas = np.zeros((SIZE, SIZE, 4), dtype=np.float32)

    print("  Layer 1: Midnight base...")
    build_background(canvas)

    print("  Layer 2: Nebula bloom...")
    build_nebula(canvas)

    print("  Layer 3a: Ring glow structure...")
    build_mane_ring_glow(canvas)

    # Convert to PIL RGBA
    arr = np.clip(canvas * 255, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr, "RGBA")

    print("  Layer 3b: Stardust particles...")
    img = build_particles(img)

    print("  Layer 4: Glass disc overlay...")
    img = build_glass_disc(img)

    print("  Layer 5: Vignette...")
    img = build_vignette(img)

    # Flatten to RGB
    final = Image.new("RGB", (SIZE, SIZE), hex_to_rgb(MIDNIGHT))
    final.paste(img, mask=img.split()[3])
    return final


if __name__ == "__main__":
    out = "Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    print(f"Rendering {SIZE}x{SIZE} icon...")
    icon = build_icon()
    icon.save(out, "PNG")
    print(f"Saved: {out} ({os.path.getsize(out) // 1024} KB)")
