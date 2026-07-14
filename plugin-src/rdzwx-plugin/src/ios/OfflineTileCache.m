/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "OfflineTileCache.h"
#import "RdzWx.h"
#import <UIKit/UIKit.h>
#import <sqlite3.h>

// Maximum number of zoom levels to overzoom (upscale from an ancestor tile).
// At 6 levels a 256px tile is stretched from a 4px region.
#define MAX_OVERZOOM 6

static NSString *const kErrorDomain = @"OfflineTileCache";

@interface OfflineTileCache () {
    sqlite3 *_db;
    sqlite3_stmt *_tileStmt;
}
@property (nonatomic, strong) dispatch_queue_t dbQueue;
@property (nonatomic, strong) NSURL *mapURL;
@property (nonatomic, assign) BOOL accessingScopedResource;
@property (nonatomic, assign) int maxZoom;
@end

@implementation OfflineTileCache

- (void)initializeWithPlugin:(RdzWx*)plugin {
    self.plugin = plugin;
    self.dbQueue = dispatch_queue_create("de.dl9rdz.rdzwx.mbtiles", DISPATCH_QUEUE_SERIAL);
    NSLog(@"OfflineTileCache: Initialized (MBTiles backend)");
}

- (BOOL)isOpen {
    __block BOOL open;
    dispatch_sync(self.dbQueue, ^{ open = (self->_db != NULL); });
    return open;
}

- (void)closeMapFile {
    dispatch_sync(self.dbQueue, ^{ [self closeLocked]; });
}

// Must be called on dbQueue
- (void)closeLocked {
    if (_tileStmt) {
        sqlite3_finalize(_tileStmt);
        _tileStmt = NULL;
    }
    if (_db) {
        sqlite3_close(_db);
        _db = NULL;
    }
    if (self.accessingScopedResource) {
        [self.mapURL stopAccessingSecurityScopedResource];
        self.accessingScopedResource = NO;
    }
    self.mapURL = nil;
}

- (BOOL)openMapFileAtURL:(NSURL*)url error:(NSError**)error {
    __block NSError *err = nil;
    dispatch_sync(self.dbQueue, ^{
        [self closeLocked];

        // Returns NO for files inside our own container; that is fine.
        self.accessingScopedResource = [url startAccessingSecurityScopedResource];
        self.mapURL = url;

        int rc = sqlite3_open_v2(url.path.UTF8String, &self->_db,
                                 SQLITE_OPEN_READONLY, NULL);
        if (rc != SQLITE_OK) {
            err = [self errorWithCode:1 message:
                   [NSString stringWithFormat:@"Cannot open %@ as sqlite database (%s)",
                    url.lastPathComponent, sqlite3_errstr(rc)]];
            [self closeLocked];
            return;
        }

        NSString *format = [self metadataValueLocked:@"format"];
        if ([format isEqualToString:@"pbf"]) {
            err = [self errorWithCode:2 message:
                   @"Vector (pbf) MBTiles are not supported; use a raster (png/jpg) MBTiles file"];
            [self closeLocked];
            return;
        }

        rc = sqlite3_prepare_v2(self->_db,
                "SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?",
                -1, &self->_tileStmt, NULL);
        if (rc != SQLITE_OK) {
            err = [self errorWithCode:3 message:
                   [NSString stringWithFormat:@"%@ has no MBTiles 'tiles' table (%s)",
                    url.lastPathComponent, sqlite3_errmsg(self->_db)]];
            [self closeLocked];
            return;
        }

        self.maxZoom = [self queryMaxZoomLocked];
        NSLog(@"OfflineTileCache: opened %@ (format=%@, maxZoom=%d)",
              url.lastPathComponent, format ?: @"unknown", self.maxZoom);
    });
    if (error) *error = err;
    return err == nil;
}

// Must be called on dbQueue
- (NSString*)metadataValueLocked:(NSString*)name {
    sqlite3_stmt *stmt = NULL;
    NSString *value = nil;
    if (sqlite3_prepare_v2(_db, "SELECT value FROM metadata WHERE name=?", -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, name.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *text = sqlite3_column_text(stmt, 0);
            if (text) value = [NSString stringWithUTF8String:(const char*)text];
        }
    }
    sqlite3_finalize(stmt);
    return value;
}

// Must be called on dbQueue
- (int)queryMaxZoomLocked {
    NSString *meta = [self metadataValueLocked:@"maxzoom"];
    if (meta.length > 0) return meta.intValue;
    sqlite3_stmt *stmt = NULL;
    int maxZoom = -1;
    if (sqlite3_prepare_v2(_db, "SELECT MAX(zoom_level) FROM tiles", -1, &stmt, NULL) == SQLITE_OK
        && sqlite3_step(stmt) == SQLITE_ROW) {
        maxZoom = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    return maxZoom;
}

// Must be called on dbQueue. XYZ coordinates; performs the TMS row flip.
- (NSData*)tileDataLockedX:(int)x y:(int)y z:(int)z {
    if (!_tileStmt || z < 0 || z > 30) return nil;
    long long n = 1LL << z;
    if (x < 0 || y < 0 || x >= n || y >= n) return nil;
    long long tmsRow = n - 1 - y;

    sqlite3_reset(_tileStmt);
    sqlite3_bind_int(_tileStmt, 1, z);
    sqlite3_bind_int64(_tileStmt, 2, x);
    sqlite3_bind_int64(_tileStmt, 3, tmsRow);

    NSData *data = nil;
    if (sqlite3_step(_tileStmt) == SQLITE_ROW) {
        const void *blob = sqlite3_column_blob(_tileStmt, 0);
        int len = sqlite3_column_bytes(_tileStmt, 0);
        if (blob && len > 0) data = [NSData dataWithBytes:blob length:len];
    }
    return data;
}

static NSString* mimeTypeForTileData(NSData *data) {
    if (data.length >= 4) {
        const unsigned char *b = data.bytes;
        if (b[0] == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G') return @"image/png";
        if (b[0] == 0xFF && b[1] == 0xD8) return @"image/jpeg";
        if (b[0] == 0x1F && b[1] == 0x8B) return nil;   // gzip: vector tile, not renderable
    }
    return @"image/png";
}

static NSString* dataURIForTile(NSData *data) {
    NSString *mime = mimeTypeForTileData(data);
    if (!mime) return nil;
    return [NSString stringWithFormat:@"data:%@;base64,%@",
            mime, [data base64EncodedStringWithOptions:0]];
}

// Upscale the quadrant of an ancestor tile (dz levels up) covering (x,y,z).
- (NSString*)overzoomedTileFromData:(NSData*)data x:(int)x y:(int)y dz:(int)dz {
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return nil;

    CGFloat size = image.size.width;
    CGFloat subSize = size / (CGFloat)(1 << dz);
    if (subSize < 1) return nil;
    CGFloat offX = (CGFloat)(x & ((1 << dz) - 1)) * subSize;
    CGFloat offY = (CGFloat)(y & ((1 << dz) - 1)) * subSize;

    CGRect cropRect = CGRectMake(offX * image.scale, offY * image.scale,
                                 subSize * image.scale, subSize * image.scale);
    CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, cropRect);
    if (!cropped) return nil;

    CGSize outSize = CGSizeMake(256, 256);
    UIGraphicsBeginImageContextWithOptions(outSize, NO, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    [[UIImage imageWithCGImage:cropped] drawInRect:CGRectMake(0, 0, outSize.width, outSize.height)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGImageRelease(cropped);

    NSData *png = UIImagePNGRepresentation(scaled);
    if (!png) return nil;
    return [NSString stringWithFormat:@"data:image/png;base64,%@",
            [png base64EncodedStringWithOptions:0]];
}

- (NSString*)getTileAtX:(int)x y:(int)y z:(int)z {
    __block NSData *data = nil;
    __block int foundDz = 0;
    dispatch_sync(self.dbQueue, ^{
        if (!self->_db) return;
        data = [self tileDataLockedX:x y:y z:z];
        if (data) return;
        // Overzoom: look for the nearest ancestor tile
        for (int dz = 1; dz <= MAX_OVERZOOM && z - dz >= 0; dz++) {
            data = [self tileDataLockedX:(x >> dz) y:(y >> dz) z:(z - dz)];
            if (data) {
                foundDz = dz;
                return;
            }
        }
    });

    if (!data) return nil;
    if (foundDz == 0) return dataURIForTile(data);
    return [self overzoomedTileFromData:data x:x y:y dz:foundDz];
}

- (NSError*)errorWithCode:(NSInteger)code message:(NSString*)message {
    return [NSError errorWithDomain:kErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (void)dealloc {
    [self closeLocked];
}

@end
