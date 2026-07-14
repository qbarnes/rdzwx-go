# Offline Maps on iOS (MBTiles)

On Android, rdzwx-go renders offline maps on-device from Mapsforge `.map` files. iOS has no Mapsforge port, so the iOS app instead uses **raster MBTiles** files: a single sqlite database containing pre-rendered PNG/JPEG map tiles.

## Creating an MBTiles file

Any tool that produces *raster* (png/jpg) MBTiles works. Vector MBTiles (`format: pbf`, e.g. from OpenMapTiles) are **not** supported and will be rejected when you select them.

The easiest free option is **QGIS**:

1. Open QGIS and add your desired base map (e.g. the OpenStreetMap XYZ layer).
2. Processing Toolbox → *Raster tools* → **Generate XYZ tiles (MBTiles)**.
3. Set the extent to your chasing region, choose min/max zoom (e.g. 8–15), and run.

Keep the area and max zoom reasonable — file size grows ~4x per zoom level. Zoom 15 for a ~100 km radius region is typically a few hundred MB.

For quick testing without QGIS, generate a synthetic map:

```bash
./tools/make_test_mbtiles.py --lat 48.56 --lon 13.43 --minzoom 8 --maxzoom 12
```

## Loading the map in the app

Two ways:

- **In-app picker**: menu → *Select map file*, then pick the `.mbtiles` file in the Files browser. The file is opened in place (not copied), and the choice persists across app restarts.
- **Files app**: copy the `.mbtiles` into *On My iPhone → rdzSonde*, then select it with *Select map file*.

Switch the map layer to **Offline** in the layer control (top right).

## Behavior and limitations

- Zooming beyond the file's max zoom shows upscaled tiles (up to 6 levels); areas outside the file's coverage show the "tile unavailable" placeholder.
- *Select map theme* is Android-only: raster tiles are pre-rendered, so themes do not apply on iOS.
- Only one map file is active at a time; selecting a new file replaces the previous choice.
