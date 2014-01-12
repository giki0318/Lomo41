//
//  LoUICollectionViewController.m
//  Lomo41
//
//  Created by Adam Zethraeus on 12/26/13.
//  Copyright (c) 2013 Very Nice Co. All rights reserved.
//

#import "LoUICollectionViewController.h"

#import <AssetsLibrary/AssetsLibrary.h>

#import "ALAssetsLibrary+PhotoAlbumFunctionality.h"
#import "LoImagePreviewCell.h"
#import "LoImageViewController.h"
#import "LoAlbumProxy.h"

static void * AlbumAssetsRefreshContext = &AlbumAssetsRefreshContext;

@interface LoUICollectionViewController ()<UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate>
- (IBAction)doDelete:(id)sender;
- (IBAction)doShare:(id)sender;
- (IBAction)doShow:(id)sender;
@property (weak, nonatomic) IBOutlet UICollectionView *collectionView;
@property (nonatomic) NSUInteger deleteIndex;
@property (nonatomic) dispatch_queue_t sessionQueue;
@end

@implementation LoUICollectionViewController

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.sessionQueue = dispatch_queue_create("collection view proxy queue", DISPATCH_QUEUE_SERIAL);
    NSAssert(self.albumProxy != nil, @"albumProxy should have been setup by LoCaptureViewController");
}

- (void)viewWillAppear: (BOOL)animated {
    [super viewWillAppear:animated];
    self.deleteIndex = -1;
    [self.collectionView reloadData];
    dispatch_async(self.sessionQueue, ^{
        [self.albumProxy addObserver:self forKeyPath:@"assets" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:AlbumAssetsRefreshContext];
    });
}

- (void)viewDidAppear:(BOOL)animated {
    dispatch_async(self.sessionQueue, ^{
        //[self.albumProxy updateAssets];
    });
}

- (void)viewWillDisappear: (BOOL)animated {
    dispatch_async(self.sessionQueue, ^{
        [self.albumProxy removeObserver:self forKeyPath:@"assets" context:AlbumAssetsRefreshContext];
    });
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section {
    return self.albumProxy.assets.count;
}

- (LoImagePreviewCell *)collectionView: (UICollectionView *)collectionView cellForItemAtIndexPath: (NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"photoCell";
    ALAsset *asset = self.albumProxy.assets[self.albumProxy.assets.count - 1 - indexPath.row];
    CGImageRef thumbnailImageRef = [[asset defaultRepresentation] fullScreenImage];
    static BOOL nibMyCellLoaded = NO;
    if(!nibMyCellLoaded) {
        UINib *nib = [UINib nibWithNibName:@"photoCell" bundle: nil];
        [collectionView registerNib:nib forCellWithReuseIdentifier:CellIdentifier];
        nibMyCellLoaded = YES;
    }
    LoImagePreviewCell *cell = (LoImagePreviewCell*)[collectionView dequeueReusableCellWithReuseIdentifier:CellIdentifier forIndexPath:indexPath];

    UIImage *thumbnail = [UIImage imageWithCGImage:thumbnailImageRef];
    cell.imageView.image = thumbnail;
    cell.frontView.hidden = NO;
    cell.backView.hidden = YES;

    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(didSwipe:)];
    swipeRight.delegate = self;
    swipeRight.numberOfTouchesRequired = 1;
    [swipeRight setDirection:UISwipeGestureRecognizerDirectionRight];
    [cell addGestureRecognizer:swipeRight];

    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(didSwipe:)];
    swipeLeft.delegate = self;
    swipeLeft.numberOfTouchesRequired = 1;
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    [cell addGestureRecognizer:swipeLeft];

    return cell;
}

- (void)didSwipe: (UISwipeGestureRecognizer *)recognizer {
    LoImagePreviewCell *cell = (LoImagePreviewCell *)recognizer.view;
    UIViewAnimationOptions direction = UIViewAnimationOptionTransitionFlipFromLeft;
    if (recognizer.direction == UISwipeGestureRecognizerDirectionRight) {
        direction = UIViewAnimationOptionTransitionFlipFromRight;
    }
    if (!cell.frontView.isHidden) {
        [self flipAllCellsToFrontInDirection: direction];
        [LoUICollectionViewController flipToBackOfCell:cell inDirection:direction];
    } else {
        [self flipAllCellsToFrontInDirection: direction];
    }
}

- (void)flipAllCellsToFrontInDirection: (UIViewAnimationOptions) direction {
    for (LoImagePreviewCell *cell in self.collectionView.visibleCells) {
        [LoUICollectionViewController flipToFrontOfCell:cell inDirection:direction];
    }
}

+ (void)flipToFrontOfCell: (LoImagePreviewCell *)cell inDirection: (UIViewAnimationOptions) direction {
    if (cell.frontView.isHidden) {
        [UIView transitionWithView:cell
                          duration:0.2f
                           options:direction
                        animations:^{
                            cell.frontView.hidden = NO;
                            cell.backView.hidden = YES;
                        } completion:nil];
    }
}

+ (void)flipToBackOfCell: (LoImagePreviewCell *)cell inDirection: (UIViewAnimationOptions) direction {
    if (!cell.frontView.isHidden) {
        [UIView transitionWithView:cell
                          duration:0.2f
                           options:direction
                        animations:^{
                            cell.frontView.hidden = YES;
                            cell.backView.hidden = NO;
                        } completion:nil];
    }
}

- (IBAction)doDelete:(id)sender {
    NSIndexPath *indexPath = [self.collectionView indexPathForCell:(UICollectionViewCell *)((UIView *)sender).superview.superview.superview];
    self.deleteIndex = self.albumProxy.assets.count - 1 - indexPath.row;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Delete Picture"
                                                    message:@"Would you like to delete the picture?"
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:nil];
    [alert addButtonWithTitle:@"Delete"];
    [alert show];
}

- (IBAction)doShare:(id)sender {
    NSIndexPath *indexPath = [self.collectionView indexPathForCell:(UICollectionViewCell *)((UIView *)sender).superview.superview.superview];
    UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:@[self.albumProxy.assets[self.albumProxy.assets.count - 1 - indexPath.row]] applicationActivities:nil];
    [self presentViewController:activityController animated:YES completion:nil];
}

- (IBAction)doShow:(id)sender {
    [self performSegueWithIdentifier: @"viewImage" sender: ((UIView *)sender).superview.superview.superview];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"viewImage"]) {
        NSIndexPath *indexPath = [self.collectionView indexPathForCell:(UICollectionViewCell *)sender];
        LoImageViewController *destViewController = segue.destinationViewController;
        destViewController.asset = self.albumProxy.assets[self.albumProxy.assets.count - 1 - indexPath.row];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        NSAssert(self.deleteIndex >= 0, @"index for action was not set");
        [self.albumProxy deleteAssetAtIndex:self.deleteIndex];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
	if (context == AlbumAssetsRefreshContext) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.collectionView reloadData];
        });
	}
}


@end
