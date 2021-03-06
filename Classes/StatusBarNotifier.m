//
//  StatusBarNotifier.m
//  CraigsFish
//
//  Created by Samuel Sutch on 1/10/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "StatusBarNotifier.h"
#import "UIColor+Extensions.h"
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import "NSString+UUID.h"

#define FLASH_LABEL_TAG 338
#define TOP_OFFSET 57
#define REGULAR_BACKGROUND [UIColor colorWithWhite:.1 alpha:.9]
#define ERROR_BACKGROUND [UIColor colorWithPatternImage: \
[UIImage imageNamed:@"errorstatusbarbg.png"]]


@implementation StatusBarNotifier

@synthesize deferredQueue;
@synthesize queuedViews;
@synthesize currentLine;
@synthesize isShown;
@synthesize isError;
@synthesize errorString;
@synthesize topOffset;

static StatusBarNotifier *__sharedNotifier;

+ (id)sharedNotifier {
  if (!__sharedNotifier) {
    __sharedNotifier = [[[StatusBarNotifier alloc] initWithFrame:
                         CGRectMake(0, 0, 320, 20)] retain];
    __sharedNotifier.topOffset = TOP_OFFSET;
  }
  return __sharedNotifier;
}

- (void)setTopOffset:(CGFloat)v
{
  topOffset = v;
//  UIScreen *scr = [UIScreen mainScreen];
//  self.center = CGPointMake(self.center.x, topOffset + (self.frame.size.height / 2.0));
  CGRect r = self.frame;
  r.origin.y = topOffset;
  self.frame = r;
}

- (id)initWithFrame:(CGRect)_frame {
  if ((self = [super initWithFrame:_frame])) {
    self.backgroundColor = REGULAR_BACKGROUND;
    self.clipsToBounds = YES;
    self.deferredQueue = [[DKMappedPriorityQueue alloc] init];
    self.queuedViews = [NSMutableDictionary dictionary];
    self.currentLine = nil;
    self.isShown = NO;
    self.isError = NO;
    views = [[NSMutableArray array] retain];
    orientation = [[UIDevice currentDevice] orientation];
    self.userInteractionEnabled = NO;
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(orientationChanged:) name:
     UIDeviceOrientationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(keyboardShowing:) name:
     UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(keyboardHiding:) name:
     UIKeyboardWillHideNotification object:nil];
  }
  return self;
}

#define degreesToRadians(x) (M_PI * x / 180.0)

- (void)orientationChanged:(NSNotification *)note
{
  UIDeviceOrientation o = [[UIDevice currentDevice] orientation];
  if (UIDeviceOrientationIsLandscape(o) || 
      !UIDeviceOrientationIsValidInterfaceOrientation(o)) {
    self.hidden = YES;
  } else self.hidden = NO;
//    if (self.isShown) {
//      [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
//      self.hidden = YES;
//    }
//  } else {
//    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
//    self.hidden = NO;
//  }
  orientation = [[UIDevice currentDevice] orientation];
//  [self flashLoading:@"omgwtf" deferred:[DKDeferred wait:1000 value:nil]];
//  UIDeviceOrientation o = [[UIDevice currentDevice] orientation]; 
//  if (o != orientation && (o == UIDeviceOrientationLandscapeLeft || o == UIDeviceOrientationLandscapeRight)) {
//    self.transform = CGAffineTransformRotate(self.transform, degreesToRadians((UIDeviceOrientationIsLandscape(o) ? 90 : 180)));
//    self.center = CGPointMake(self.superview.frame.size.width / 2, (self.topOffset - 160)/2);
//  } else if (o != orientation && (o == UIDeviceOrientationPortrait || o == UIDeviceOrientationPortraitUpsideDown)) {
//    self.transform = CGAffineTransformRotate(self.transform, degreesToRadians((UIDeviceOrientationIsPortrait(o) ? 180 : 90)));
//    self.center = CGPointMake(self.superview.frame.size.width / 2, (self.topOffset/2));
//  }
//  orientation = o;
}

- (void)keyboardShowing:(id)r
{
  [self setHidden:YES];
}

- (void)keyboardHiding:(id)r
{
  [self setHidden:NO];
}

- (UILabel *)configuredLabel {
  UILabel *l = [[UILabel alloc] initWithFrame:
                CGRectMake(8, 0, self.frame.size.width, self.frame.size.height)];
  l.tag = FLASH_LABEL_TAG;
  l.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | 
  UIViewAutoresizingFlexibleBottomMargin;
  l.textColor = [UIColor colorWithWhite:.93 alpha:.95];
  l.font = [UIFont boldSystemFontOfSize:13];
  l.shadowColor = [UIColor colorWithWhite:0 alpha:.75];
  l.shadowOffset = CGSizeMake(0, -1);
  l.backgroundColor = [UIColor clearColor];
  l.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
  return l;
}

- (DKDeferred *)flashLine:(NSString *)line seconds:(NSTimeInterval)seconds {
  UILabel *l = [self configuredLabel];
  l.text = line;
  return [self flashLine:l deferred:
          [DKDeferred wait:seconds value:[NSNull null]]];
}

- (DKDeferred *)flashLine:(UIView *)line deferred:(DKDeferred *)d {
  @synchronized(self) {
    [self.deferredQueue enqueue:d key:[d deferredID]];
    [self.queuedViews setObject:line forKey:[d deferredID]];
  }
  [d addBoth:curryTS(self, @selector(_cbContinueFlashingView:deferred:result:), line, d)];
  [self _continueFlashing];
  return d;
}


- _cbContinueFlashingView:(UIView *)v 
                 deferred:(DKDeferred *)d result:(id)result {
  if (isDeferred(result)) {
    return [result addBoth:curryTS(self,
                                   @selector(_cbContinueFlashingView:deferred:result:), v, d)];
  }
  if (result && result != (id)[NSNull null]
      && [result isKindOfClass:[NSError class]]) {
    self.isError = YES;
    // show this error for 4 seconds
    // setting isError to NO calls _continueFlashing
    [self performSelector:@selector(setIsError:)
               withObject:NO afterDelay:4.0];
  } else {
    self.isError = NO;
    [self _continueFlashing];
  }
  return result;
}

- (void)_continueFlashing {
  NSArray *next;
  @synchronized(self) {
    next = [self.deferredQueue dequeue];
  }
  if (next && next != (id)[NSNull null]) {
    if ([[next objectAtIndex:0] fired] != -1) {
      // this deferred has already compleated, ignore it
      return [self _continueFlashing];
    } else {
      // retrieve the view and display it
      UIView *nextView;
      @synchronized(self) {
        nextView = [[[self.queuedViews objectForKey:
                      [next objectAtIndex:1]] retain] autorelease];
        [self.queuedViews removeObjectForKey:[next objectAtIndex:1]];
      }
      if (!nextView)
        return [self _continueFlashing];
      if (!self.isError)
        self.currentLine = nextView;
    }
  } else {
    if (!self.isError) {
      // continue displaying the error until it calls _continueFlashing
      self.currentLine = nil;
    }
  }
}

- (void)setCurrentLine:(UIView *)line {
  if (self.isShown)
    [[self superview] bringSubviewToFront:self];
  if (self.currentLine) {
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
    [UIView setAnimationDuration:.35];
    self.currentLine.frame = CGRectOffset(self.currentLine.frame, 0, -38);
    self.currentLine.alpha = 0;
    self.frame = CGRectMake(0, topOffset + (self.isError ? -18 : 0), 320, self.isError ? 38 : 20);
    [self _changingSize];
    [UIView commitAnimations];
    @synchronized(self) {
      [currentLine release];
      currentLine = nil;
    }
  }
  if (!line && self.isShown) {
    [self setHideTimer:self.isError ? 3.0 : .4];
  }
  if (line) {
    [self clearHideTimer];
    if (!self.isShown) {
      [self show];
    }
    @synchronized(self) {
      currentLine = [line retain];
    }
    self.currentLine.frame = CGRectOffset(self.currentLine.frame, 0, 38);
    self.currentLine.alpha = 0;
    [self addSubview:line];
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
    [UIView setAnimationDuration:.35];
    self.currentLine.frame = CGRectOffset(self.currentLine.frame, 0, -38);
    self.currentLine.alpha = 1;
    self.frame = CGRectMake(0, topOffset + (self.isError ? -18 : 0), 320, self.isError ? 38 : 20);
    [self _changingSize];
    [UIView commitAnimations];
  }
}

- (void)setIsError:(BOOL)error {
  @synchronized(self) {
    isError = error;
  }
  if (isError) {
    self.currentLine = [self errorView];
  } else {
    // when an error goes away run _continueFlashing
    // it will automatically remove the error view
    // and display the next line when isError is NO
    [self _continueFlashing];
  }
}

- (UIView *)errorView {
  UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 38)];
  v.backgroundColor = ERROR_BACKGROUND;
  UILabel *l = [self configuredLabel];
  l.lineBreakMode = UILineBreakModeWordWrap;
  l.numberOfLines = 2;
  l.text = !self.errorString ? 
  @"There was a network error. Please ensure "
  @"connection to Wifi or Cellular Data." 
  : self.errorString;
  l.frame = CGRectMake(8, 0, 320, 38);
  l.textColor = [UIColor colorWithWhite:.9 alpha:.95];
  l.shadowColor = [UIColor colorWithWhite:.1 alpha:.7];
  [v addSubview:l];
  return v;
}

- (void)setHideTimer:(NSTimeInterval)seconds {
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(hide) object:nil];
  [self performSelector:@selector(hide)
             withObject:nil afterDelay:seconds];
}

- (void)clearHideTimer {
  [NSObject cancelPreviousPerformRequestsWithTarget:self 
                                           selector:@selector(hide) object:nil];
}

- (DKDeferred *)flashLoading:(NSString *)text deferred:(DKDeferred *)d {
  if (!d || !text) return [DKDeferred fail:nil];
  UILabel *l = [[self configuredLabel] autorelease];
  l.text = text;
  [l sizeToFit];
  
  UIActivityIndicatorView *activityIndicator =
  [[[UIActivityIndicatorView alloc] 
    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite]
   autorelease];
  [activityIndicator startAnimating];
  activityIndicator.frame = CGRectMake(l.frame.size.width + 16, 0, 20, 20);
  activityIndicator.transform = CGAffineTransformMakeScale(.7, .7);
  
  UIView *container = [[UIView alloc] initWithFrame:
                       CGRectMake(0, 0, self.frame.size.width, self.frame.size.height)];
  [container addSubview:l];
  [container addSubview:activityIndicator];
  return [self flashLine:container deferred:d];
}

- (void)show {
  if (self.isShown) 
    return;
  //  [[UIApplication sharedApplication] setStatusBarHidden:YES animated:YES];
  self.isShown = YES;
  [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
  
  return;
  
  UIWindow *window = [[UIApplication sharedApplication] keyWindow];
  //  window.autoresizesSubviews = NO;
  //  window.autoresizingMask = UIViewAutoresizingNone;
  
  [CATransaction begin];
  self.alpha = 0;
  //self.hidden = UIDeviceOrientationIsLandscape([[UIDevice currentDevice] orientation]);
  UIDeviceOrientation o = [[UIDevice currentDevice] orientation];
  if (!UIDeviceOrientationIsLandscape(o) && UIDeviceOrientationIsValidInterfaceOrientation(o)) {
    NSLog(@"device orientation is not landscape???");
    self.backgroundColor = REGULAR_BACKGROUND;
    self.frame = CGRectMake(0, topOffset + (self.isError ? -18 : 0), 320, self.isError ? 38 :  20);
    [self _changingSize];
    [window insertSubview:self atIndex:0];
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:.35];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
    self.alpha = 1;
    for (UIView *wv in [window subviews]) {
      [wv setNeedsLayout];
    }
    [UIView commitAnimations];
    [CATransaction flush];
    [CATransaction commit];
    [window bringSubviewToFront:self];
  }
  //NSLog(@"window.subviews %@", window.subviews);
}

- (void)hide {
  if (!self.isShown)
    return;
  self.isShown = NO;
  [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
  return;
  [CATransaction begin];
  //  [[UIApplication sharedApplication] setStatusBarHidden:NO animated:YES];
  [UIView beginAnimations:nil context:nil];
  [UIView setAnimationDuration:.35];
  [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
  [UIView setAnimationDelegate:self];
  [UIView setAnimationDidStopSelector:@selector(finishedDisappearing:)];
  [self setAlpha:0];
  [UIView commitAnimations];
  [CATransaction flush];
  [CATransaction commit];  
  self.isError = NO;
}

- (void)finishedDisappearing:arg {
  for (UIView *v in [self subviews])
    [v removeFromSuperview];
  
  [self removeFromSuperview];
}

- (void)_changingSize {
  //  [[NSNotificationCenter defaultCenter]
  //   postNotificationName:kStatusBarChangedSizeNotification
  //   object:self];
}

@end
