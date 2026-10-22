#!/usr/bin/env python3
"""Compare an accelerator output PGM against a golden Sobel of the input PGM.

Golden pixel = min(|Dx| + |Dy|, 255), same kernels as src/rtl/sobel_alu.sv.
Border: neighbours outside the image replicate the nearest edge pixel, i.e.
coordinates are clamped (for (row 0, col 0) the left, top-left and top
neighbours are all (0,0) itself).

On mismatch, writes <result>_golden.pgm next to the result and exits 1.

Usage: check_sobel.py <input.pgm> <result.pgm>
"""
import sys


def read_pgm(path):
    with open(path) as f:
        tokens = [t for line in f for t in line.split('#', 1)[0].split()]
    if tokens[0] != 'P2':
        sys.exit(f'{path}: not an ASCII (P2) PGM')
    w, h = int(tokens[1]), int(tokens[2])
    px = [int(t) for t in tokens[4:4 + w * h]]
    if len(px) != w * h:
        sys.exit(f'{path}: expected {w * h} pixels, got {len(px)}')
    return w, h, px


def sobel(w, h, px):
    def p(r, c):
        return px[min(max(r, 0), h - 1) * w + min(max(c, 0), w - 1)]

    out = []
    for r in range(h):
        for c in range(w):
            dx = (p(r-1, c+1) + 2*p(r, c+1) + p(r+1, c+1)) - (p(r-1, c-1) + 2*p(r, c-1) + p(r+1, c-1))
            dy = (p(r-1, c-1) + 2*p(r-1, c) + p(r-1, c+1)) - (p(r+1, c-1) + 2*p(r+1, c) + p(r+1, c+1))
            out.append(min(abs(dx) + abs(dy), 255))
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src_path, res_path = sys.argv[1:]
    w, h, src = read_pgm(src_path)
    rw, rh, res = read_pgm(res_path)
    if (rw, rh) != (w, h):
        sys.exit(f'FAIL: size {rw}x{rh}, expected {w}x{h}')

    golden = sobel(w, h, src)
    bad = [i for i in range(w * h) if res[i] != golden[i]]
    if not bad:
        print(f'PASS: {w}x{h} pixels match golden Sobel')
        return

    for i in bad[:10]:
        print(f'  (row {i // w}, col {i % w}): got {res[i]}, expected {golden[i]}')
    golden_path = res_path.rsplit('.', 1)[0] + '_golden.pgm'
    with open(golden_path, 'w') as f:
        f.write(f'P2\n{w} {h}\n255\n' + '\n'.join(map(str, golden)) + '\n')
    sys.exit(f'FAIL: {len(bad)}/{w * h} pixels differ (golden written to {golden_path})')


if __name__ == '__main__':
    main()
