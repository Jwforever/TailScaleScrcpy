import struct, math

S = 768
BG = (23, 23, 26)
FG = (255, 255, 255)
px = 1.0 / S
T = [(0.44, 0.345), (0.44, 0.655), (0.615, 0.500)]


def sd_round_rect(x, y, cx, cy, hw, hh, r):
    dx = abs(x - cx) - (hw - r)
    dy = abs(y - cy) - (hh - r)
    ox = dx if dx > 0.0 else 0.0
    oy = dy if dy > 0.0 else 0.0
    return math.hypot(ox, oy) + min(max(dx, dy), 0.0) - r


def sd_seg(px_, py_, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px_ - ax, py_ - ay
    t = (wx * vx + wy * vy) / (vx * vx + vy * vy)
    t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    return math.hypot(px_ - (ax + t * vx), py_ - (ay + t * vy))


def inside_tri(x, y, a, b, c):
    def sg(p, q, r):
        return (p[0] - r[0]) * (q[1] - r[1]) - (q[0] - r[0]) * (p[1] - r[1])
    d1 = sg((x, y), a, b)
    d2 = sg((x, y), b, c)
    d3 = sg((x, y), c, a)
    return not (((d1 < 0) or (d2 < 0) or (d3 < 0)) and ((d1 > 0) or (d2 > 0) or (d3 > 0)))


master = bytearray(S * S * 4)
for y in range(S):
    fy = (y + 0.5) * px
    row = y * S * 4
    for x in range(S):
        fx = (x + 0.5) * px

        d0 = sd_round_rect(fx, fy, 0.5, 0.5, 0.46, 0.46, 0.215)
        bg_cov = min(max(0.5 - d0 / px, 0.0), 1.0)

        d1 = abs(sd_round_rect(fx, fy, 0.5, 0.5, 0.225, 0.290, 0.072)) - 0.024
        ring_cov = min(max(0.5 - d1 / px, 0.0), 1.0)

        d2 = min(sd_seg(fx, fy, T[0][0], T[0][1], T[1][0], T[1][1]),
                 sd_seg(fx, fy, T[1][0], T[1][1], T[2][0], T[2][1]),
                 sd_seg(fx, fy, T[2][0], T[2][1], T[0][0], T[0][1]))
        if inside_tri(fx, fy, T[0], T[1], T[2]):
            d2 = -d2
        tri_cov = min(max(0.5 - d2 / px, 0.0), 1.0)

        fg = min(ring_cov + tri_cov - ring_cov * tri_cov, 1.0)
        a = bg_cov
        i = row + x * 4
        if a <= 0.0:
            master[i:i + 4] = b'\x00\x00\x00\x00'
        else:
            master[i] = int(BG[0] * (1 - fg) + FG[0] * fg + 0.5)
            master[i + 1] = int(BG[1] * (1 - fg) + FG[1] * fg + 0.5)
            master[i + 2] = int(BG[2] * (1 - fg) + FG[2] * fg + 0.5)
            master[i + 3] = int(a * 255 + 0.5)

SIZES = [16, 24, 32, 48, 64, 128, 256]


def downsample(size):
    f = S // size
    out = bytearray(size * size * 4)
    for ty in range(size):
        for tx in range(size):
            acc = [0, 0, 0, 0]
            for sy in range(f):
                base = ((ty * f + sy) * S + tx * f) * 4
                for sx in range(f):
                    j = base + sx * 4
                    acc[0] += master[j]
                    acc[1] += master[j + 1]
                    acc[2] += master[j + 2]
                    acc[3] += master[j + 3]
            n = f * f
            o = (ty * size + tx) * 4
            for k in range(4):
                out[o + k] = acc[k] // n
    return bytes(out)


def bmp_image(size, rgba):
    hdr = struct.pack('<IiiHHIIiiII', 40, size, size * 2, 1, 32, 0, size * size * 4, 0, 0, 0, 0)
    xor = bytearray()
    for y in range(size - 1, -1, -1):
        base = y * size * 4
        for x in range(size):
            i = base + x * 4
            xor += bytes((rgba[i + 2], rgba[i + 1], rgba[i], rgba[i + 3]))
    mask_row = ((size + 31) // 32) * 4
    return hdr + bytes(xor) + bytes(mask_row * size)


imgs = [(s, bmp_image(s, downsample(s))) for s in SIZES]
out = bytearray(struct.pack('<HHH', 0, 1, len(imgs)))
off = 6 + 16 * len(imgs)
for s, d in imgs:
    w = 0 if s >= 256 else s
    out += struct.pack('<BBBBHHII', w, w, 0, 0, 1, 32, len(d), off)
    off += len(d)
for s, d in imgs:
    out += d
open('icon.ico', 'wb').write(bytes(out))
print('icon.ico', len(out), 'bytes')
