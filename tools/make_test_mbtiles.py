#!/usr/bin/env python3
"""Generate a small raster MBTiles file for testing offline maps.

Creates solid-color 256x256 PNG tiles (color derived from tile coordinates,
with a black border so tile boundaries are visible) around a center point.
Uses only the Python standard library.

Example:
    ./make_test_mbtiles.py --output test.mbtiles --lat 48.56 --lon 13.43 \\
        --minzoom 8 --maxzoom 12 --radius 3
"""

import argparse
import math
import sqlite3
import struct
import zlib


def make_png(r, g, b, size=256, border=1):
    """Build a solid-color RGB PNG with a black border, stdlib only."""
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter type: none
        for x in range(size):
            if x < border or y < border or x >= size - border or y >= size - border:
                raw += b"\x00\x00\x00"
            else:
                raw += bytes((r, g, b))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)  # 8-bit RGB
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
            + chunk(b"IEND", b""))


def latlon_to_tile(lat, lon, z):
    n = 1 << z
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return min(max(x, 0), n - 1), min(max(y, 0), n - 1)


def tile_color(x, y, z):
    h = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
    return 64 + (h & 0x7F), 64 + ((h >> 7) & 0x7F), 64 + ((h >> 14) & 0x7F)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--output", default="test.mbtiles")
    ap.add_argument("--lat", type=float, default=48.56)
    ap.add_argument("--lon", type=float, default=13.43)
    ap.add_argument("--minzoom", type=int, default=8)
    ap.add_argument("--maxzoom", type=int, default=12)
    ap.add_argument("--radius", type=int, default=3,
                    help="tiles around the center tile in each direction, per zoom level")
    args = ap.parse_args()

    db = sqlite3.connect(args.output)
    db.executescript("""
        DROP TABLE IF EXISTS metadata;
        DROP TABLE IF EXISTS tiles;
        CREATE TABLE metadata (name TEXT, value TEXT);
        CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER,
                            tile_row INTEGER, tile_data BLOB);
        CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
    """)

    count = 0
    for z in range(args.minzoom, args.maxzoom + 1):
        n = 1 << z
        cx, cy = latlon_to_tile(args.lat, args.lon, z)
        for x in range(max(0, cx - args.radius), min(n, cx + args.radius + 1)):
            for y in range(max(0, cy - args.radius), min(n, cy + args.radius + 1)):
                png = make_png(*tile_color(x, y, z))
                tms_row = n - 1 - y  # MBTiles stores rows in TMS order
                db.execute("INSERT INTO tiles VALUES (?,?,?,?)",
                           (z, x, tms_row, sqlite3.Binary(png)))
                count += 1

    metadata = {
        "name": "rdzwx test map",
        "type": "baselayer",
        "version": "1.1",
        "description": "Generated test tiles for rdzwx-go offline map testing",
        "format": "png",
        "minzoom": str(args.minzoom),
        "maxzoom": str(args.maxzoom),
    }
    db.executemany("INSERT INTO metadata VALUES (?,?)", metadata.items())
    db.commit()
    db.close()
    print(f"Wrote {count} tiles (z{args.minzoom}-z{args.maxzoom}) to {args.output}")


if __name__ == "__main__":
    main()
