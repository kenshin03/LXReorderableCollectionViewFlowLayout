//
//  LXReorderableCollectionViewFlowLayout.h
//
//  Created by Stan Chang Khin Boon on 1/10/12.
//  Copyright (c) 2012 d--buzz. All rights reserved.
//

#import "FLCollectionViewFlowLayout.h"

@interface LXReorderableCollectionViewFlowLayout : FLCollectionViewFlowLayout <UIGestureRecognizerDelegate>

@property (assign, nonatomic) UIEdgeInsets triggerScrollingEdgeInsets;
@property (assign, nonatomic) CGFloat scrollingSpeed;
@property (strong, nonatomic) NSTimer *scrollingTimer;

@property (weak, nonatomic) UILongPressGestureRecognizer *longPressGestureRecognizer;
@property (weak, nonatomic) UIPanGestureRecognizer *panGestureRecognizer;

@property (strong, nonatomic) NSIndexPath *selectedItemIndexPath;
@property (weak, nonatomic) UIView *currentView;
@property (assign, nonatomic) CGPoint currentViewCenter;
@property (assign, nonatomic) CGPoint panTranslationInCollectionView;

@property (assign, nonatomic) BOOL shouldCrossfadeFromHighlighted; // Defaults to YES
@property (assign, nonatomic) BOOL shouldShowDropshadowWhenDragging; // Defaults to NO
@property (assign, nonatomic) BOOL shouldStretchFirstCell; // Defaults to NO
@property (assign, nonatomic) BOOL shouldParallaxFirstCell; // Defaults to NO. Ignored if should stretch first cell is NO.
@property (assign, nonatomic) CGFloat editingCellScale; // Defaults to kFLCollectionViewFlowLayoutEditingCellScale. Defines the scale that we shrink to when a dragged tile is released. Makes the transtion smooth.
@property (assign, nonatomic) CGFloat draggingCellScale; // Defaults to 1.1. The selected tile will be transformed up to this scale while it is dragged.

/// Defaults to NO. If NO, the tile will be dragged inside the collection view when reordering.
/// If YES, the tile will be dragged above the collection view (in its superview).
/// An example where this property is used is for dragging tiles above the header in the profile tab.
@property (assign, nonatomic) BOOL shouldDragTileAboveCollectionView;

- (void)setUpGestureRecognizersOnCollectionView;

@end

@protocol LXReorderableCollectionViewDelegateFlowLayout <UICollectionViewDelegateFlowLayout>

- (void)collectionView:(UICollectionView *)theCollectionView layout:(UICollectionViewLayout *)theLayout itemAtIndexPath:(NSIndexPath *)theFromIndexPath willMoveToIndexPath:(NSIndexPath *)theToIndexPath;

@optional

- (BOOL)collectionView:(UICollectionView *)theCollectionView layout:(UICollectionViewLayout *)theLayout itemAtIndexPath:(NSIndexPath *)theFromIndexPath shouldMoveToIndexPath:(NSIndexPath *)theToIndexPath;
- (BOOL)collectionView:(UICollectionView *)theCollectionView layout:(UICollectionViewLayout *)theLayout shouldBeginReorderingAtIndexPath:(NSIndexPath *)theIndexPath;

- (void)collectionView:(UICollectionView *)theCollectionView layout:(UICollectionViewLayout *)theLayout willBeginReorderingAtIndexPath:(NSIndexPath *)theIndexPath;
- (void)collectionView:(UICollectionView *)theCollectionView layout:(UICollectionViewLayout *)theLayout didBeginReorderingAtIndexPath:(NSIndexPath *)theIndexPath;
- (void)collectionView:(UICollectionView *)theCollectionView layout:(UICollectionViewLayout *)theLayout willEndReorderingAtIndexPath:(NSIndexPath *)theIndexPath;
- (void)collectionView:(UICollectionView *)theCollectionView layout:(UICollectionViewLayout *)theLayout didEndReorderingAtIndexPath:(NSIndexPath *)theIndexPath;

@end