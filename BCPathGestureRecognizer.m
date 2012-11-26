//
//  BCPathGestureRecognizer.m
//
//  Created by Bartosz Ciechanowski on 14.11.2012.
//  Copyright (c) 2012 Bartosz Ciechanowski. All rights reserved.
//

#import <UIKit/UIGestureRecognizerSubclass.h>
#import "BCPathGestureRecognizer.h"

static const CGFloat kSegmentLength = 70.0f;

typedef struct PointList
{
    NSUInteger count;
    NSUInteger maxCount;
    CGPoint *data;
} PointList;


typedef struct CGPathParseResult
{
    NSUInteger elementsCount;
    NSUInteger moveToElementsCount;
    PointList splitPoints;
} CGPathParseResult;


static void appendSegment(PointList *list, CGPoint start, CGPoint end);
static void appendQuadCurve(PointList *list, CGPoint start, CGPoint control, CGPoint end);
static void appendCubicCurve(PointList *list, CGPoint start, CGPoint control1, CGPoint control2, CGPoint end);

static void pointListClear(PointList *list);
static void pointListAddPoint(PointList *list, CGPoint point);
static void pointListClose(PointList *list);
static CGPoint pointListLastPoint(PointList *list);


@implementation BCPathGestureRecognizer
{
    CGPoint _startOffset;
    NSUInteger _currentSegment;
    PointList _targetPoints;
}


- (id)initWithTarget:(id)target action:(SEL)action
{
    self = [super initWithTarget:target action:action];
    if (self) {
        _detectionWidth = 100.0f;
    }
    return self;
}

- (void)dealloc
{
    [self setPath:nil]; // gotta clear _targetPoints
}


- (void) setPath:(CGPathRef)path
{
    CGPathParseResult parseResult = {0};
    CGPathApply(path, &parseResult, parsePath);
    
    if (parseResult.moveToElementsCount > 1) {
        NSLog(@"ERROR: The path contains gaps. It has been moved more than once by either \"CGPathMoveToPoint(...)\" or \"- (void)moveToPoint:(CGPoint)point\"");
        return;
    }
    
    path = CGPathCreateCopy(path);
    CGPathRelease(_path);
    
    _path = path;
    
    pointListClear(&_targetPoints);
    _targetPoints = parseResult.splitPoints;
}

- (UIBezierPath *) detectionBezierPath
{
    if (_targetPoints.count == 0) {
        return nil;
    }
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    path.lineCapStyle = kCGLineCapRound;
    path.lineJoinStyle = kCGLineJoinRound;
    path.lineWidth = self.detectionWidth;

    [path moveToPoint:_targetPoints.data[0]];
    
    for (int i = 1; i < _targetPoints.count; i++) {
        [path addLineToPoint:_targetPoints.data[i]];
    }
    
    return path;
}

#pragma mark - UIGestureRecognizer subclass overrides

- (void)reset
{
    [super reset];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    
    if (_targetPoints.count < 2) { // too short path
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    
    CGPoint touchPoint = [self pointLocationForTouches:touches];

    _currentSegment = 0;
    _startOffset = self.attached ? CGPointZero : vectorSub(touchPoint, _targetPoints.data[0]);
    
    touchPoint = vectorSub(touchPoint, _startOffset);

    if (! isPointCloseToSegment(touchPoint, _targetPoints.data[0], _targetPoints.data[1], self.detectionWidth)) {
        self.state = UIGestureRecognizerStateFailed;
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];
    
    CGPoint touchPoint = vectorSub([self pointLocationForTouches:touches], _startOffset);
    
    if (_currentSegment == _targetPoints.count - 2) { //last segment
        
        CGPoint vector = vectorForSegment(pointListLastPoint(&_targetPoints), touchPoint);
        if (vectorDot(vector, vector) < self.detectionWidth*self.detectionWidth/4.0) {
            self.state = UIGestureRecognizerStateRecognized;
            return;
        }
    }
    
    
    BOOL isAtLastSegment = _currentSegment >= _targetPoints.count - 2;
    BOOL doesTriggerNextSegment = NO;

    
    if (! isAtLastSegment) {
        doesTriggerNextSegment = isPointCloseToSegment(touchPoint, _targetPoints.data[_currentSegment + 1], _targetPoints.data[_currentSegment + 2], self.detectionWidth);
        
        if (doesTriggerNextSegment) {
            _currentSegment++;
            return;
        }
    }
    
    BOOL doesTriggerCurrentSegment = isPointCloseToSegment(touchPoint, _targetPoints.data[_currentSegment], _targetPoints.data[_currentSegment + 1], self.detectionWidth);
    
    if ( ! doesTriggerCurrentSegment) {
        self.state = UIGestureRecognizerStateFailed;
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    
    self.state = UIGestureRecognizerStateFailed;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled:touches withEvent:event];
    
    self.state = UIGestureRecognizerStateCancelled;
}


- (CGPoint) pointLocationForTouches: (NSSet *) touches
{
    UITouch *touch = [touches anyObject];
    
    return [touch locationInView:self.view];
}


#pragma mark - CGPathRef parsing


void parsePath(void *info, const CGPathElement *element)
{
    CGPathParseResult *parseResult = info;
    parseResult->elementsCount++;
    
    PointList *list = &parseResult->splitPoints;
    
    switch (element->type) {
        case kCGPathElementMoveToPoint:
            parseResult->moveToElementsCount++;
            pointListAddPoint(list, element->points[0]);
            break;
        case kCGPathElementAddLineToPoint:
            appendSegment(list, pointListLastPoint(list), element->points[0]);
            break;
        case kCGPathElementAddQuadCurveToPoint:
            appendQuadCurve(list, pointListLastPoint(list), element->points[0], element->points[1]);
            break;
        case kCGPathElementAddCurveToPoint:
            appendCubicCurve(list, pointListLastPoint(list), element->points[0], element->points[1], element->points[2]);
            break;
        case kCGPathElementCloseSubpath:
            appendSegment(list, pointListLastPoint(list), list->data[0]);
            break;
        default:
            break;
    }
}

#pragma mark - CGPoint Convinences

static inline CGPoint vectorForSegment(CGPoint a, CGPoint b)
{
    return CGPointMake(b.x - a.x, b.y - a.y);
}

static inline CGPoint vectorSub(CGPoint a, CGPoint b)
{
    return CGPointMake(a.x - b.x, a.y - b.y);
}

static inline CGFloat vectorDot(CGPoint a, CGPoint b)
{
	return a.x*b.x + a.y*b.y;
}

static inline CGFloat vectorLength(CGPoint a)
{
    return sqrtf(vectorDot(a, a));
}



BOOL isPointCloseToSegment(CGPoint testedPoint, CGPoint segStart, CGPoint segEnd, CGFloat width)
{
    //assert(! CGPointEqualToPoint(segStart, segEnd));
    
    CGPoint ab = vectorForSegment(segEnd, segStart);
    CGPoint ac = vectorForSegment(testedPoint, segStart);
    CGPoint bc = vectorForSegment(testedPoint, segEnd);
    
    CGFloat e = vectorDot(ac, ab);
    CGFloat f = vectorDot(ab, ab);
    
    CGFloat dist;
    
    if (e <= 0.0f) {
        dist = vectorDot(ac, ac);
    } else if (e >= f) {
        dist = vectorDot(bc, bc);
    } else {
        dist = vectorDot(ac, ac) - e*e/f;
    }

    return dist <= width*width/4.0;
}

#pragma mark - Curve Divisions

static void appendSegment(PointList *list, CGPoint start, CGPoint end)
{
    pointListAddPoint(list, end);
}

static void appendQuadCurve(PointList *list, CGPoint start, CGPoint control, CGPoint end)
{
    CGFloat approxLength = vectorLength(vectorForSegment(start, control)) + vectorLength(vectorForSegment(control, end));
    int subdivisions = (int)ceilf(approxLength/kSegmentLength);
    
    for (int i = 1; i <= subdivisions; i++) {
        CGFloat t = (float)i/(float)subdivisions;
        CGFloat nt = (1.0 - t);
        CGPoint point = CGPointMake(nt*nt*start.x + 2.0*nt*t*control.x + t*t*end.x,
                                    nt*nt*start.y + 2.0*nt*t*control.y + t*t*end.y);

        pointListAddPoint(list, point);
    }
}

static void appendCubicCurve(PointList *list, CGPoint start, CGPoint control1, CGPoint control2, CGPoint end)
{
    CGFloat approxLength = vectorLength(vectorForSegment(start, control1)) + vectorLength(vectorForSegment(control1, control2)) + vectorLength(vectorForSegment(control2, end));
    int subdivisions = (int)ceilf(approxLength/kSegmentLength);
    
    for (int i = 1; i <= subdivisions; i++) {
        CGFloat t = (float)i/(float)subdivisions;
        CGFloat nt = (1.0 - t);
        
        CGPoint point = CGPointMake(nt*nt*nt*start.x + 3.0*nt*nt*t*control1.x + 3.0*nt*t*t*control2.x + t*t*t*end.x,
                                    nt*nt*nt*start.y + 3.0*nt*nt*t*control1.y + 3.0*nt*t*t*control2.y + t*t*t*end.y);
        
        pointListAddPoint(list, point);
    }
}


#pragma mark - PointList manipulations

static void pointListPrint(PointList *list)
{
    for (int i = 0; i < list->count; i++) {
        NSLog(@"%d. %lg, %lg", i, list->data[i].x, list->data[i].y);
    }
}

static void pointListClear(PointList *list)
{
    free(list->data);
    list->data = NULL;
    list->count = 0;
    list->maxCount = 0;
}

static void pointListAddPoint(PointList *list, CGPoint point)
{
    if (list->count == list->maxCount)
    {
        NSUInteger newCount = 2*list->maxCount + 16;
        CGPoint *newData = reallocf(list->data, newCount*sizeof(CGPoint));

        assert(newData); // realocf fail
        
        list->maxCount = newCount;
        list->data = newData;
    }
    
    list->data[list->count++] = point;
}

static void pointListClose(PointList *list)
{
    if (list->count == 0) {
        return;
    }
    
    CGPoint first = list->data[0];
    CGPoint last = pointListLastPoint(list);
    
    if (CGPointEqualToPoint(first, last)) {
        return;
    }
    
    pointListAddPoint(list, first);
}

static CGPoint pointListLastPoint(PointList *list)
{
    assert(list->count != 0); // empty list
    
    return list->data[list->count - 1];
}

@end
