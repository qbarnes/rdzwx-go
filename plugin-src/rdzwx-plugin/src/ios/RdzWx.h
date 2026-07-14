/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Cordova/CDVPlugin.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class JsonRdzHandler;
@class GPSHandler;
@class MDNSHandler;
@class WgsToEgm;
@class OfflineTileCache;

@interface RdzWx : CDVPlugin <UIDocumentPickerDelegate>

@property (nonatomic, strong) JsonRdzHandler *jsonrdzHandler;
@property (nonatomic, strong) GPSHandler *gpsHandler;
@property (nonatomic, strong) MDNSHandler *mdnsHandler;
@property (nonatomic, strong) WgsToEgm *wgsToEgm;
@property (nonatomic, strong) OfflineTileCache *offlineTileCache;

@property (nonatomic, strong) NSString *callbackId;
@property (nonatomic, assign) BOOL running;

// Plugin methods exposed to JavaScript
- (void)start:(CDVInvokedUrlCommand*)command;
- (void)stop:(CDVInvokedUrlCommand*)command;
- (void)closeconn:(CDVInvokedUrlCommand*)command;
- (void)showmap:(CDVInvokedUrlCommand*)command;
- (void)wgstoegm:(CDVInvokedUrlCommand*)command;
- (void)gettile:(CDVInvokedUrlCommand*)command;
- (void)selstorage:(CDVInvokedUrlCommand*)command;
- (void)mdnsUpdateDiscovery:(CDVInvokedUrlCommand*)command;
- (void)fetchUrl:(CDVInvokedUrlCommand*)command;

// Internal methods for handlers
- (void)handleJsonrdzData:(NSString*)data;
- (void)handleTtgoStatus:(NSString*)ip;
- (void)handleMdnsStatus:(NSString*)status details:(NSString*)details;
- (void)updateGps:(double)latitude longitude:(double)longitude altitude:(double)altitude bearing:(float)bearing accuracy:(float)accuracy;
- (void)runJsonRdz:(NSString*)host port:(int)port;

@end