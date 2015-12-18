//
//  LXReorderableCollectionViewFlowLayout.m
//
//  Created by Stan Chang Khin Boon on 1/10/12.
//  Copyright (c) 2012 d--buzz. All rights reserved.
//

#import "LXReorderableCollectionViewFlowLayout.h"
#import "FLSectionCollectionViewCell.h"
#import "UIView-Utility.h"
#import <QuartzCore/QuartzCore.h>

#define LX_FRAMES_PER_SECOND 60.0

#ifndef CGGEOMETRY_LXSUPPORT_H_
CG_INLINE CGPoint
LXS_CGPointAdd(CGPoint thePoint1, CGPoint thePoint2) {
    return CGPointMake(thePoint1.x + thePoint2.x, thePoint1.y + thePoint2.y);
}
#endif

typedef NS_ENUM(NSInteger, LXReorderableCollectionViewFlowLayoutScrollingDirection) {
    LXReorderableCollectionViewFlowLayoutScrollingDirectionUp = 1,
    LXReorderableCollectionViewFlowLayoutScrollingDirectionDown,
    LXReorderableCollectionViewFlowLayoutScrollingDirectionLeft,
    LXReorderableCollectionViewFlowLayoutScrollingDirectionRight
};

static NSString * const kLXReorderableCollectionViewFlowLayoutScrollingDirectionKey = @"LXScrollingDirection";

@implementation LXReorderableCollectionViewFlowLayout

#pragma mark - Life Cycle

- (id)init
{
    self = [super init];
    if (self) {
        // No need to initialize values to NO/0/nil (default).
        
        // Initialize default values
        self.shouldCrossfadeFromHighlighted = YES;
        self.editingCellScale = kFLCollectionViewFlowLayoutDefaultEditingCellScale;
        self.draggingCellScale = 1.1;
    }
    return self;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds
{
    // Quickly bail if we don't need to invalidate no matter what the bounds are.
    if (!self.shouldStretchFirstCell) {
        return NO;
    }
    
    // If we're stretching/parallaxing the first cell, we may need to invalidate layout to resize the first cell.
    // We only invalidate the layout if the size of the cell needs to change for the new bounds.
    CGFloat adjustedOffsetY = self.collectionView.contentInset.top + newBounds.origin.y;
    BOOL shouldInvalidateForStretch = self.shouldStretchFirstCell && adjustedOffsetY <= 0;
    BOOL shouldInvlaidateForParallax = NO;
    if (self.shouldParallaxFirstCell) {
        UICollectionViewLayoutAttributes *originalFirstCellAttributes = [super layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
        if (originalFirstCellAttributes.size.height >= adjustedOffsetY) {
            shouldInvlaidateForParallax = YES;
        }
    }
    return shouldInvalidateForStretch || shouldInvlaidateForParallax;
}

- (void)setUpGestureRecognizersOnCollectionView {
    UILongPressGestureRecognizer *theLongPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    // Links the default long press gesture recognizer to the custom long press gesture recognizer we are creating now
    // by enforcing failure dependency so that they doesn't clash.
    for (UIGestureRecognizer *theGestureRecognizer in self.collectionView.gestureRecognizers) {
        if ([theGestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
            [theGestureRecognizer requireGestureRecognizerToFail:theLongPressGestureRecognizer];
        }
    }
    theLongPressGestureRecognizer.delegate = self;
    [self.collectionView addGestureRecognizer:theLongPressGestureRecognizer];
    self.longPressGestureRecognizer = theLongPressGestureRecognizer;
    
    UIPanGestureRecognizer *thePanGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    thePanGestureRecognizer.delegate = self;
    // Setting the maximum number of touches to 1 prevents the item from quickly jumping to origin (0.0, 0.0) when doing following:
    // drag with one finger, place other finger down, release dragging finger
    thePanGestureRecognizer.maximumNumberOfTouches = 1;
    [self.collectionView addGestureRecognizer:thePanGestureRecognizer];
    self.panGestureRecognizer = thePanGestureRecognizer;
    
    self.triggerScrollingEdgeInsets = UIEdgeInsetsMake(50.0f, 50.0f, 50.0f, 50.0f);
    self.scrollingSpeed = 300.0f;
    [self.scrollingTimer invalidate];
    self.scrollingTimer = nil;
}

- (void)awakeFromNib {
    [self setUpGestureRecognizersOnCollectionView];
}

#pragma mark - Custom methods

- (void)applyLayoutAttributes:(UICollectionViewLayoutAttributes *)theLayoutAttributes {
    if ([theLayoutAttributes.indexPath isEqual:self.selectedItemIndexPath]) {
        theLayoutAttributes.hidden = YES;
    }
    
    // Sticky first cell
    // Inspired by https://nrj.io/stretchy-uicollectionview-headers
    if (self.shouldStretchFirstCell && theLayoutAttributes.indexPath.row == 0 && theLayoutAttributes.indexPath.section == 0) {
        
        // Check if we've pulled below past the lowest position
        CGFloat minY = -self.collectionView.contentInset.top;
        CGFloat offsetY = self.collectionView.contentOffset.y;
        CGFloat adjustedOffsetY = offsetY - minY;
        CGFloat originalCellHeight = theLayoutAttributes.size.height;
        if (adjustedOffsetY < 0.0) {
            // Adjust the first cell's height and y based on how much the user has pulled down.
            theLayoutAttributes.frame = CGRectInsetTopEdge(theLayoutAttributes.frame, adjustedOffsetY);
        } else if (self.shouldParallaxFirstCell && adjustedOffsetY < originalCellHeight) {
            // To get a parallax effect, shrink the cell by insetting the top as the user scrolls up.
            const CGFloat kParallaxFactor = 0.2;
            CGFloat deltaY = FLRound(adjustedOffsetY * kParallaxFactor);
            theLayoutAttributes.frame = CGRectInsetTopEdge(theLayoutAttributes.frame, deltaY);
        }
    }
}

- (void)invalidateLayoutIfNecessary {
    CGPoint currentViewCenterInCollectionView = [self.collectionView convertPoint:self.currentView.center fromView:self.currentView.superview];
    NSIndexPath *theIndexPathOfSelectedItem = [self.collectionView indexPathForItemAtPoint:currentViewCenterInCollectionView];
    if ((![theIndexPathOfSelectedItem isEqual:self.selectedItemIndexPath]) &&(theIndexPathOfSelectedItem)) {
        NSIndexPath *thePreviousSelectedIndexPath = self.selectedItemIndexPath;
        
        id<LXReorderableCollectionViewDelegateFlowLayout> theDelegate = (id<LXReorderableCollectionViewDelegateFlowLayout>) self.collectionView.delegate;
        
        if ([theDelegate conformsToProtocol:@protocol(LXReorderableCollectionViewDelegateFlowLayout)]) {
            
            // Check with the delegate to see if this move is even allowed.
            if ([theDelegate respondsToSelector:@selector(collectionView:layout:itemAtIndexPath:shouldMoveToIndexPath:)]) {
                BOOL shouldMove = [theDelegate collectionView:self.collectionView
                                                       layout:self
                                              itemAtIndexPath:thePreviousSelectedIndexPath
                                        shouldMoveToIndexPath:theIndexPathOfSelectedItem];
                
                if (!shouldMove) {
                    return;
                }
            }
            
            self.selectedItemIndexPath = theIndexPathOfSelectedItem;
            
            // Proceed with the move
            [theDelegate collectionView:self.collectionView
                                 layout:self
                        itemAtIndexPath:thePreviousSelectedIndexPath
                    willMoveToIndexPath:theIndexPathOfSelectedItem];
        }
        
        [self.collectionView performBatchUpdates:^{
            //[self.collectionView moveItemAtIndexPath:thePreviousSelectedIndexPath toIndexPath:theIndexPathOfSelectedItem];
            [self.collectionView deleteItemsAtIndexPaths:@[ thePreviousSelectedIndexPath ]];
            [self.collectionView insertItemsAtIndexPaths:@[ theIndexPathOfSelectedItem ]];
        } completion:^(BOOL finished) {
        }];
    }
}

#pragma mark - Target/Action methods

- (void)handleScroll:(NSTimer *)theTimer {
    LXReorderableCollectionViewFlowLayoutScrollingDirection theScrollingDirection = (LXReorderableCollectionViewFlowLayoutScrollingDirection)[theTimer.userInfo[kLXReorderableCollectionViewFlowLayoutScrollingDirectionKey] integerValue];
    
    // `theDistance` needs to be rounded to an integer to fix the "tile is slipping away under my finger" bug;
    // setting a non-integral value to `self.collectionView.contentOffset` will get rounded anyway but `self.currentViewCenter` and `self.currentView.center` won't and that's where the values slowly diverge.
    CGFloat theDistance = rint(self.scrollingSpeed / LX_FRAMES_PER_SECOND);
    
    CGPoint theContentOffset = self.collectionView.contentOffset;
    
    switch (theScrollingDirection) {
        case LXReorderableCollectionViewFlowLayoutScrollingDirectionUp: {
            theDistance = -theDistance;
            CGFloat theMinY = -self.collectionView.contentInset.top;
            if ((theContentOffset.y + theDistance) <= theMinY) {
                theDistance = theMinY - theContentOffset.y;
            }
            self.collectionView.contentOffset = LXS_CGPointAdd(theContentOffset, CGPointMake(0.0f, theDistance));
            if (!self.shouldDragTileAboveCollectionView) {
                self.currentViewCenter = LXS_CGPointAdd(self.currentViewCenter, CGPointMake(0.0f, theDistance));
                self.currentView.center = LXS_CGPointAdd(self.currentViewCenter, self.panTranslationInCollectionView);
            }
        } break;
        case LXReorderableCollectionViewFlowLayoutScrollingDirectionDown: {
            CGFloat insetCollectionViewHeight = CGRectGetHeight(self.collectionView.bounds) - self.collectionView.contentInset.bottom;
            CGFloat theMaxY = MAX(self.collectionView.contentSize.height, insetCollectionViewHeight) - insetCollectionViewHeight;
            if ((theContentOffset.y + theDistance) >= theMaxY) {
                theDistance = theMaxY - theContentOffset.y;
            }
            self.collectionView.contentOffset = LXS_CGPointAdd(theContentOffset, CGPointMake(0.0f, theDistance));
            if (!self.shouldDragTileAboveCollectionView) {
                self.currentViewCenter = LXS_CGPointAdd(self.currentViewCenter, CGPointMake(0.0f, theDistance));
                self.currentView.center = LXS_CGPointAdd(self.currentViewCenter, self.panTranslationInCollectionView);
            }
        } break;
            
        case LXReorderableCollectionViewFlowLayoutScrollingDirectionLeft: {
            theDistance = -theDistance;
            CGFloat theMinX = -self.collectionView.contentInset.left;
            if ((theContentOffset.x + theDistance) <= theMinX) {
                theDistance = theMinX - theContentOffset.x;
            }
            self.collectionView.contentOffset = LXS_CGPointAdd(theContentOffset, CGPointMake(theDistance, 0.0f));
            if (!self.shouldDragTileAboveCollectionView) {
                self.currentViewCenter = LXS_CGPointAdd(self.currentViewCenter, CGPointMake(theDistance, 0.0f));
                self.currentView.center = LXS_CGPointAdd(self.currentViewCenter, self.panTranslationInCollectionView);
            }
        } break;
        case LXReorderableCollectionViewFlowLayoutScrollingDirectionRight: {
            CGFloat theMaxX = MAX(self.collectionView.contentSize.width, CGRectGetWidth(self.collectionView.bounds)) - CGRectGetWidth(self.collectionView.bounds);
            if ((theContentOffset.x + theDistance) >= theMaxX) {
                theDistance = theMaxX - theContentOffset.x;
            }
            self.collectionView.contentOffset = LXS_CGPointAdd(theContentOffset, CGPointMake(theDistance, 0.0f));
            if (!self.shouldDragTileAboveCollectionView) {
                self.currentViewCenter = LXS_CGPointAdd(self.currentViewCenter, CGPointMake(theDistance, 0.0f));
                self.currentView.center = LXS_CGPointAdd(self.currentViewCenter, self.panTranslationInCollectionView);
            }
        } break;
            
        default: {
        } break;
    }
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)theLongPressGestureRecognizer {
    switch (theLongPressGestureRecognizer.state) {
        case UIGestureRecognizerStateBegan: {
            CGPoint theLocationInCollectionView = [theLongPressGestureRecognizer locationInView:self.collectionView];
            NSIndexPath *theIndexPathOfSelectedItem = [self.collectionView indexPathForItemAtPoint:theLocationInCollectionView];
            
            if ([self.collectionView.delegate conformsToProtocol:@protocol(LXReorderableCollectionViewDelegateFlowLayout)]) {
                id<LXReorderableCollectionViewDelegateFlowLayout> theDelegate = (id<LXReorderableCollectionViewDelegateFlowLayout>)self.collectionView.delegate;
                if ([theDelegate respondsToSelector:@selector(collectionView:layout:shouldBeginReorderingAtIndexPath:)]) {
                    BOOL shouldStartReorder =  [theDelegate collectionView:self.collectionView layout:self shouldBeginReorderingAtIndexPath:theIndexPathOfSelectedItem];
                    if (!shouldStartReorder) {
                        return;
                    }
                }
                
                if ([theDelegate respondsToSelector:@selector(collectionView:layout:willBeginReorderingAtIndexPath:)]) {
                    [theDelegate collectionView:self.collectionView layout:self willBeginReorderingAtIndexPath:theIndexPathOfSelectedItem];
                }
            }
            
            UICollectionViewCell *theCollectionViewCell = [self.collectionView cellForItemAtIndexPath:theIndexPathOfSelectedItem];
            
            // Force hide remove button for snapshotting
            FLSectionCollectionViewCell *sectionCollectionViewCell = nil;
            if ([theCollectionViewCell isKindOfClass:[FLSectionCollectionViewCell class]]) {
                sectionCollectionViewCell = (FLSectionCollectionViewCell *)theCollectionViewCell;
            }
            sectionCollectionViewCell.forceHideRemoveButton = YES;
            // Post notification for snapshotting;
            // important to not have a gray tile when reordering.
            // Note 1: Also see symetric ...DidSnapshot... call below.
            // Note 2: Pass the cell as argument, not self.
            [[NSNotificationCenter defaultCenter] postNotificationName:kFLViewWillSnapshotNotification object:theCollectionViewCell];
            
            theCollectionViewCell.highlighted = YES;
            UIGraphicsBeginImageContextWithOptions(theCollectionViewCell.bounds.size, NO, 0.0f);
            [theCollectionViewCell.layer renderInContext:UIGraphicsGetCurrentContext()];
            UIImage *theHighlightedImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            theCollectionViewCell.highlighted = NO;
            UIGraphicsBeginImageContextWithOptions(theCollectionViewCell.bounds.size, NO, 0.0f);
            [theCollectionViewCell.layer renderInContext:UIGraphicsGetCurrentContext()];
            UIImage *theImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            sectionCollectionViewCell.forceHideRemoveButton = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:kFLViewDidSnapshotNotification object:theCollectionViewCell];
            
            UIImageView *theImageView = [[UIImageView alloc] initWithImage:theImage];
            theImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; // Not using constraints, lets auto resizing mask be translated automatically...
            if (self.shouldShowDropshadowWhenDragging) {
                theImageView.layer.shadowOpacity = 0.8;
                theImageView.layer.shadowRadius = 3.0;
                theImageView.layer.shadowOffset = CGSizeMake(0.0, 1.0);
                theImageView.layer.shadowColor = [UIColor blackColor].CGColor;
                theImageView.layer.shadowPath = [UIBezierPath bezierPathWithRect:theImageView.bounds].CGPath;
            }
            
            UIImageView *theHighlightedImageView = [[UIImageView alloc] initWithImage:theHighlightedImage];
            theHighlightedImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; // Not using constraints, lets auto resizing mask be translated automatically...
            
            UIView *containerViewForDraggedTile = self.shouldDragTileAboveCollectionView ? self.collectionView.superview : self.collectionView;
            UIView *theView = [[UIView alloc] initWithFrame:[containerViewForDraggedTile convertRect:theCollectionViewCell.frame fromView:theCollectionViewCell.superview]];
            
            [theView addSubview:theImageView];
            [theView addSubview:theHighlightedImageView];
            
            [containerViewForDraggedTile addSubview:theView];
            
            self.selectedItemIndexPath = theIndexPathOfSelectedItem;
            self.currentView = theView;
            self.currentViewCenter = theView.center;
            
            theImageView.alpha = 0.0f;
            theHighlightedImageView.alpha = 1.0f;
            
            [UIView
             animateWithDuration:0.3
             animations:^{
                 theView.transform = CGAffineTransformMakeScale(self.draggingCellScale, self.draggingCellScale);
                 theImageView.alpha = 1.0f;
                 if (self.shouldCrossfadeFromHighlighted) {
                     theHighlightedImageView.alpha = 0.0f;
                 }
             }
             completion:^(BOOL finished) {
                 [theHighlightedImageView removeFromSuperview];
                 
                 if ([self.collectionView.delegate conformsToProtocol:@protocol(LXReorderableCollectionViewDelegateFlowLayout)]) {
                     id<LXReorderableCollectionViewDelegateFlowLayout> theDelegate = (id<LXReorderableCollectionViewDelegateFlowLayout>)self.collectionView.delegate;
                     if ([theDelegate respondsToSelector:@selector(collectionView:layout:didBeginReorderingAtIndexPath:)]) {
                         [theDelegate collectionView:self.collectionView layout:self didBeginReorderingAtIndexPath:theIndexPathOfSelectedItem];
                     }
                 }
             }];
            
            [self invalidateLayout];
        } break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            NSIndexPath *theIndexPathOfSelectedItem = self.selectedItemIndexPath;
            
            if ([self.collectionView.delegate conformsToProtocol:@protocol(LXReorderableCollectionViewDelegateFlowLayout)]) {
                id<LXReorderableCollectionViewDelegateFlowLayout> theDelegate = (id<LXReorderableCollectionViewDelegateFlowLayout>)self.collectionView.delegate;
                if ([theDelegate respondsToSelector:@selector(collectionView:layout:willEndReorderingAtIndexPath:)]) {
                    [theDelegate collectionView:self.collectionView layout:self willEndReorderingAtIndexPath:theIndexPathOfSelectedItem];
                }
            }
            
            self.selectedItemIndexPath = nil;
            self.currentViewCenter = CGPointZero;
            
            if (theIndexPathOfSelectedItem) {
                UICollectionViewLayoutAttributes *theLayoutAttributes = [self layoutAttributesForItemAtIndexPath:theIndexPathOfSelectedItem];
                
                __weak LXReorderableCollectionViewFlowLayout *theWeakSelf = self;
                [UIView
                 animateWithDuration:0.3f
                 animations:^{
                     __strong LXReorderableCollectionViewFlowLayout *theStrongSelf = theWeakSelf;
                     
                     theStrongSelf.currentView.center = [theStrongSelf.collectionView convertPoint:theLayoutAttributes.center toView:theStrongSelf.currentView.superview];
                     theStrongSelf.currentView.transform = CGAffineTransformMakeScale(self.editingCellScale, self.editingCellScale);
                 }
                 completion:^(BOOL finished) {
                     __strong LXReorderableCollectionViewFlowLayout *theStrongSelf = theWeakSelf;
                     
                     [theStrongSelf.currentView removeFromSuperview];
                     [theStrongSelf invalidateLayout];

                     // Use theStrongSelf in case self is deallocated before the animation completes.
                     if ([theStrongSelf.collectionView.delegate conformsToProtocol:@protocol(LXReorderableCollectionViewDelegateFlowLayout)]) {
                         id<LXReorderableCollectionViewDelegateFlowLayout> theDelegate = (id<LXReorderableCollectionViewDelegateFlowLayout>)theStrongSelf.collectionView.delegate;
                         if ([theDelegate respondsToSelector:@selector(collectionView:layout:didEndReorderingAtIndexPath:)]) {
                             [theDelegate collectionView:theStrongSelf.collectionView layout:theStrongSelf didEndReorderingAtIndexPath:theIndexPathOfSelectedItem];
                         }
                     }
                 }];
            }
        } break;
        default: {
        } break;
    }
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)thePanGestureRecognizer {
    switch (thePanGestureRecognizer.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged: {
            CGPoint theTranslationInCollectionView = [thePanGestureRecognizer translationInView:self.collectionView];
            self.panTranslationInCollectionView = theTranslationInCollectionView;
            self.currentView.center = LXS_CGPointAdd(self.currentViewCenter, theTranslationInCollectionView);
            CGPoint theLocationInCollectionView = [self.collectionView convertPoint:self.currentView.center fromView:self.currentView.superview];
            
            [self invalidateLayoutIfNecessary];

            CGRect insetCollectionViewBounds = UIEdgeInsetsInsetRect(self.collectionView.bounds, self.collectionView.contentInset);
            
            switch (self.scrollDirection) {
                case UICollectionViewScrollDirectionVertical: {
                    if (theLocationInCollectionView.y < (CGRectGetMinY(insetCollectionViewBounds) + self.triggerScrollingEdgeInsets.top)) {
                        BOOL isScrollingTimerSetUpNeeded = YES;
                        if (self.scrollingTimer) {
                            if (self.scrollingTimer.isValid) {
                                isScrollingTimerSetUpNeeded = ([self.scrollingTimer.userInfo[kLXReorderableCollectionViewFlowLayoutScrollingDirectionKey] integerValue] != LXReorderableCollectionViewFlowLayoutScrollingDirectionUp);
                            }
                        }
                        if (isScrollingTimerSetUpNeeded) {
                            if (self.scrollingTimer) {
                                [self.scrollingTimer invalidate];
                                self.scrollingTimer = nil;
                            }
                            self.scrollingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / LX_FRAMES_PER_SECOND
                                                                                   target:self
                                                                                 selector:@selector(handleScroll:)
                                                                                 userInfo:@{ kLXReorderableCollectionViewFlowLayoutScrollingDirectionKey : @( LXReorderableCollectionViewFlowLayoutScrollingDirectionUp ) }
                                                                                  repeats:YES];
                        }
                    } else if (theLocationInCollectionView.y > (CGRectGetMaxY(insetCollectionViewBounds) - self.triggerScrollingEdgeInsets.bottom)) {
                        BOOL isScrollingTimerSetUpNeeded = YES;
                        if (self.scrollingTimer) {
                            if (self.scrollingTimer.isValid) {
                                isScrollingTimerSetUpNeeded = ([self.scrollingTimer.userInfo[kLXReorderableCollectionViewFlowLayoutScrollingDirectionKey] integerValue] != LXReorderableCollectionViewFlowLayoutScrollingDirectionDown);
                            }
                        }
                        if (isScrollingTimerSetUpNeeded) {
                            if (self.scrollingTimer) {
                                [self.scrollingTimer invalidate];
                                self.scrollingTimer = nil;
                            }
                            self.scrollingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / LX_FRAMES_PER_SECOND
                                                                                   target:self
                                                                                 selector:@selector(handleScroll:)
                                                                                 userInfo:@{ kLXReorderableCollectionViewFlowLayoutScrollingDirectionKey : @( LXReorderableCollectionViewFlowLayoutScrollingDirectionDown ) }
                                                                                  repeats:YES];
                        }
                    } else {
                        if (self.scrollingTimer) {
                            [self.scrollingTimer invalidate];
                            self.scrollingTimer = nil;
                        }
                    }
                } break;
                case UICollectionViewScrollDirectionHorizontal: {
                    if (theLocationInCollectionView.x < (CGRectGetMinX(insetCollectionViewBounds) + self.triggerScrollingEdgeInsets.left)) {
                        BOOL isScrollingTimerSetUpNeeded = YES;
                        if (self.scrollingTimer) {
                            if (self.scrollingTimer.isValid) {
                                isScrollingTimerSetUpNeeded = ([self.scrollingTimer.userInfo[kLXReorderableCollectionViewFlowLayoutScrollingDirectionKey] integerValue] != LXReorderableCollectionViewFlowLayoutScrollingDirectionLeft);
                            }
                        }
                        if (isScrollingTimerSetUpNeeded) {
                            if (self.scrollingTimer) {
                                [self.scrollingTimer invalidate];
                                self.scrollingTimer = nil;
                            }
                            self.scrollingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / LX_FRAMES_PER_SECOND
                                                                                   target:self
                                                                                 selector:@selector(handleScroll:)
                                                                                 userInfo:@{ kLXReorderableCollectionViewFlowLayoutScrollingDirectionKey : @( LXReorderableCollectionViewFlowLayoutScrollingDirectionLeft ) }
                                                                                  repeats:YES];
                        }
                    } else if (theLocationInCollectionView.x > (CGRectGetMaxX(insetCollectionViewBounds) - self.triggerScrollingEdgeInsets.right)) {
                        BOOL isScrollingTimerSetUpNeeded = YES;
                        if (self.scrollingTimer) {
                            if (self.scrollingTimer.isValid) {
                                isScrollingTimerSetUpNeeded = ([self.scrollingTimer.userInfo[kLXReorderableCollectionViewFlowLayoutScrollingDirectionKey] integerValue] != LXReorderableCollectionViewFlowLayoutScrollingDirectionRight);
                            }
                        }
                        if (isScrollingTimerSetUpNeeded) {
                            if (self.scrollingTimer) {
                                [self.scrollingTimer invalidate];
                                self.scrollingTimer = nil;
                            }
                            self.scrollingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / LX_FRAMES_PER_SECOND
                                                                                   target:self
                                                                                 selector:@selector(handleScroll:)
                                                                                 userInfo:@{ kLXReorderableCollectionViewFlowLayoutScrollingDirectionKey : @( LXReorderableCollectionViewFlowLayoutScrollingDirectionRight ) }
                                                                                  repeats:YES];
                        }
                    } else {
                        if (self.scrollingTimer) {
                            [self.scrollingTimer invalidate];
                            self.scrollingTimer = nil;
                        }
                    }
                } break;
            }
        } break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            if (self.scrollingTimer) {
                [self.scrollingTimer invalidate];
                self.scrollingTimer = nil;
            }
        } break;
        default: {
        } break;
    }
}

#pragma mark - UICollectionViewFlowLayoutDelegate methods

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)theRect {
    NSArray *theLayoutAttributesForElementsInRect = [super layoutAttributesForElementsInRect:theRect];
    
    for (UICollectionViewLayoutAttributes *theLayoutAttributes in theLayoutAttributesForElementsInRect) {
        switch (theLayoutAttributes.representedElementCategory) {
            case UICollectionElementCategoryCell: {
                [self applyLayoutAttributes:theLayoutAttributes];
            } break;
            default: {
            } break;
        }
    }
    
    return theLayoutAttributesForElementsInRect;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)theIndexPath {
    UICollectionViewLayoutAttributes *theLayoutAttributes = [super layoutAttributesForItemAtIndexPath:theIndexPath];
    
    switch (theLayoutAttributes.representedElementCategory) {
        case UICollectionElementCategoryCell: {
            [self applyLayoutAttributes:theLayoutAttributes];
        } break;
        default: {
        } break;
    }
    
    return theLayoutAttributes;
}

#pragma mark - UIGestureRecognizerDelegate methods

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)theGestureRecognizer {
    if ([self.panGestureRecognizer isEqual:theGestureRecognizer]) {
        return (self.selectedItemIndexPath != nil);
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)theGestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)theOtherGestureRecognizer {
    if ([self.longPressGestureRecognizer isEqual:theGestureRecognizer]) {
        if ([self.panGestureRecognizer isEqual:theOtherGestureRecognizer]) {
            return YES;
        } else {
            return NO;
        }
    } else if ([self.panGestureRecognizer isEqual:theGestureRecognizer]) {
        if ([self.longPressGestureRecognizer isEqual:theOtherGestureRecognizer]) {
            return YES;
        } else {
            return NO;
        }
    }
    return NO;
}

@end
