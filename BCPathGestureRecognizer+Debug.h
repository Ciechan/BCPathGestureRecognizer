//
//  BCPathGestureRecognizer_Debug.h
//  PathRecognizer
//
//  Created by Bartosz Ciechanowski on 16.11.2012.
//  Copyright (c) 2012 Bartosz Ciechanowski. All rights reserved.
//

#import "BCPathGestureRecognizer.h"

@interface BCPathGestureRecognizer (Debug)

// Lazily created UIBezierPath showing the detection range of recognizer with proper width and line/join caps
@property (nonatomic, readonly) UIBezierPath *detectionBezierPath;

@end
