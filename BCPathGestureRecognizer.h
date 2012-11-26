//
//  BCPathGestureRecognizer.h
//
//  Created by Bartosz Ciechanowski on 14.11.2012.
//  Copyright (c) 2012 Bartosz Ciechanowski. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface BCPathGestureRecognizer : UIGestureRecognizer

// Detected path, must be continuos, i.e. should only have only one moveToPoint element
@property (nonatomic) CGPathRef path;

// Width of the "detection corridor"
@property (nonatomic) CGFloat detectionWidth; // Defaults to 100.0f

// If YES then gesture must start at the path's start point
// If NO then the gesture can start anywhere on the recognizer's view, but still have to match path's shape
@property (nonatomic) BOOL attached; // Defaults to NO


@end
