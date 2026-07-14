/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

@class RdzWx;

@interface OfflineTileCache : NSObject

@property (nonatomic, weak) RdzWx *plugin;

- (void)initializeWithPlugin:(RdzWx*)plugin;

// Open a raster MBTiles file (open-in-place URL from the document picker or
// a file in the app's Documents directory). Returns NO with a description in
// *error if the file is not a readable raster MBTiles database.
- (BOOL)openMapFileAtURL:(NSURL*)url error:(NSError**)error;
- (void)closeMapFile;
- (BOOL)isOpen;

// Returns a "data:image/...;base64,..." URI usable as an <img> src,
// or nil if no tile is available at (or above) this position.
- (NSString*)getTileAtX:(int)x y:(int)y z:(int)z;

@end
