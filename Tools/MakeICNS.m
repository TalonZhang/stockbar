#import <AppKit/AppKit.h>

static void AppendUInt32(NSMutableData *data, uint32_t value) {
    uint32_t bigEndian = CFSwapInt32HostToBig(value);
    [data appendBytes:&bigEndian length:sizeof(bigEndian)];
}

static NSData *RenderIcon(NSImage *artwork, NSInteger size) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:size pixelsHigh:size
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:size * 4 bitsPerPixel:32];
    bitmap.size = NSMakeSize(size, size);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSGraphicsContext setCurrentContext:context];
    context.imageInterpolation = NSImageInterpolationHigh;
    NSRect bounds = NSMakeRect(0, 0, size, size);
    [NSColor.clearColor setFill];
    NSRectFillUsingOperation(bounds, NSCompositingOperationCopy);

    // Export the approved artwork into the standard rounded icon silhouette.
    // Only the exterior is clipped; the approved blue mark is never redrawn.
    CGFloat scale = (CGFloat)size / 1024.0;
    NSRect tile = NSMakeRect(104.0 * scale, 104.0 * scale, 816.0 * scale, 816.0 * scale);
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:tile
                                                         xRadius:205.0 * scale yRadius:205.0 * scale];
    [outline addClip];
    [artwork drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 4) {
            fprintf(stderr, "Usage: MakeICNS <artwork.png> <output.iconset> <output.icns>\n");
            return 64;
        }
        NSString *source = [NSString stringWithUTF8String:argv[1]];
        NSString *iconset = [NSString stringWithUTF8String:argv[2]];
        NSString *output = [NSString stringWithUTF8String:argv[3]];
        NSImage *artwork = [[NSImage alloc] initWithContentsOfFile:source];
        if (!artwork.isValid) {
            fprintf(stderr, "Cannot decode icon artwork\n");
            return 66;
        }
        NSError *error = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:iconset withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"Cannot create iconset: %@", error);
            return 73;
        }
        NSArray<NSArray *> *chunks = @[
            @[@"icp4", @"icon_16x16.png", @16],
            @[@"icp5", @"icon_32x32.png", @32],
            @[@"icp6", @"icon_32x32@2x.png", @64],
            @[@"ic07", @"icon_128x128.png", @128],
            @[@"ic08", @"icon_256x256.png", @256],
            @[@"ic09", @"icon_512x512.png", @512],
            @[@"ic10", @"icon_512x512@2x.png", @1024],
            @[@"ic11", @"icon_16x16@2x.png", @32],
            @[@"ic12", @"icon_32x32@2x.png", @64],
            @[@"ic13", @"icon_128x128@2x.png", @256],
            @[@"ic14", @"icon_256x256@2x.png", @512]
        ];
        NSMutableData *icon = [NSMutableData dataWithData:[@"icns" dataUsingEncoding:NSASCIIStringEncoding]];
        AppendUInt32(icon, 0);
        for (NSArray *chunk in chunks) {
            NSData *png = RenderIcon(artwork, [chunk[2] integerValue]);
            NSString *path = [iconset stringByAppendingPathComponent:chunk[1]];
            if (!png || ![png writeToFile:path options:NSDataWritingAtomic error:&error]) {
                NSLog(@"Cannot export icon size: %@", error);
                return 73;
            }
            [icon appendData:[chunk[0] dataUsingEncoding:NSASCIIStringEncoding]];
            AppendUInt32(icon, (uint32_t)(png.length + 8));
            [icon appendData:png];
        }
        uint32_t size = CFSwapInt32HostToBig((uint32_t)icon.length);
        [icon replaceBytesInRange:NSMakeRange(4, 4) withBytes:&size];
        if (![icon writeToFile:output options:NSDataWritingAtomic error:&error]) {
            NSLog(@"Cannot write ICNS: %@", error);
            return 73;
        }
        printf("Exported icon with %lu representations\n", (unsigned long)chunks.count);
    }
    return 0;
}
