"""Generate the seamless faceted-fold map used only by natural landscape paper.

Offline dependencies: numpy, scipy, Pillow. Runtime has no Python dependency.
Run from the repository root. RGB stores signed x/y slopes (range +/-1.5)
plus eight-direction height-horizon occlusion (radians / .5). Alpha is opaque.
The four-world-unit repeat has broad waves and two irregular facet scales.
"""
from pathlib import Path
import numpy as np
from scipy.ndimage import gaussian_filter
from scipy.spatial import Delaunay
from PIL import Image

SIZE, PERIOD, SEED = 512, 4.0, 203
rng = np.random.default_rng(SEED)
y, x = np.mgrid[0:SIZE, 0:SIZE] * PERIOD / SIZE

def smooth(sigma, amplitude):
    h = gaussian_filter(rng.normal(size=(SIZE, SIZE)), sigma, mode="wrap")
    return h / h.std() * amplitude

def facets(count, amplitude):
    grid = np.arange(count) * PERIOD / count
    points = np.array([(a, b) for a in grid for b in grid])
    points += rng.uniform(-.4, .4, points.shape) * PERIOD / count
    heights = rng.normal(0, amplitude, len(points))
    # Periodic copies make the height function continuous at all four borders.
    tiled = np.concatenate([points + [a * PERIOD, b * PERIOD]
                            for a in [-1, 0, 1] for b in [-1, 0, 1]])
    h = np.tile(heights, 9)
    tri = Delaunay(tiled)
    q = np.c_[x.ravel(), y.ravel()]
    ids = tri.find_simplex(q)
    assert np.all(ids >= 0)
    transforms = tri.transform[ids]
    bary = np.einsum('ijk,ik->ij', transforms[:, :2], q-transforms[:, 2])
    weights = np.c_[bary, 1-bary.sum(axis=1)]
    z = np.einsum('ij,ij->i', h[tri.simplices[ids]], weights).reshape(SIZE, SIZE)
    return gaussian_filter(z, .65, mode='wrap')

height = smooth(16, .003) + smooth(7, .001) + facets(60, .0038) + facets(108, .0009)
dx = (np.roll(height, -1, axis=1)-np.roll(height, 1, axis=1)) * SIZE / (2*PERIOD)
dy = (np.roll(height, -1, axis=0)-np.roll(height, 1, axis=0)) * SIZE / (2*PERIOD)
occlusion = np.zeros_like(height)
for angle in np.linspace(0, 2*np.pi, 8, endpoint=False):
    horizon = np.zeros_like(height)
    for radius in [1, 2, 4, 8]:
        sx, sy = int(round(np.cos(angle)*radius)), int(round(np.sin(angle)*radius))
        distance = np.hypot(sx, sy)*PERIOD/SIZE
        neighbor = np.roll(height, (-sy, -sx), axis=(0, 1))
        horizon = np.maximum(horizon, (neighbor-height)/distance)
    occlusion += np.arctan(horizon) / 8
encoded = np.stack([dx/3+.5, dy/3+.5, occlusion/.5, np.ones_like(dx)], axis=-1)
path = Path('assets/textures/paper/landscape_crumple.png')
Image.fromarray(np.uint8(np.clip(encoded, 0, 1)*255+.5)).save(path)
print(f'{path}: {path.stat().st_size} bytes; {SIZE}x{SIZE}, {PERIOD} world units')
