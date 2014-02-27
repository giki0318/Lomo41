//
//  LoDefaultFilter.m
//  Lomo41
//
//  Created by Adam Zethraeus on 2/26/14.
//  Copyright (c) 2014 Very Nice Co. All rights reserved.
//

#import "LoDefaultFilter.h"
#import "GPUImagePicture.h"
#import "GPUImageLookupFilter.h"

@implementation LoDefaultFilter

- (id)init {
    if (!(self = [super init])) {
        return nil;
    }
    
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    UIImage *image = [UIImage imageNamed:@"lomo2.png"];
#else
    NSImage *image = [NSImage imageNamed:@"lomo2.png"];
#endif
    
    NSAssert(image, @"Image resource must be added to assets");
    
    lookupImageSource = [[GPUImagePicture alloc] initWithImage:image];
    GPUImageLookupFilter *lookupFilter = [[GPUImageLookupFilter alloc] init];
    [self addFilter:lookupFilter];
    
    [lookupImageSource addTarget:lookupFilter atTextureLocation:1];
    [lookupImageSource processImage];
    
    self.initialFilters = [NSArray arrayWithObjects:lookupFilter, nil];
    self.terminalFilter = lookupFilter;
    
    return self;
}

- (void)prepareForImageCapture {
    [lookupImageSource processImage];
    [super prepareForImageCapture];
}

@end
