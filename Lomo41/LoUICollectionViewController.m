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
#import "LoAppDelegate.h"

static void * AlbumAssetsRefreshContext = &AlbumAssetsRefreshContext;

typedef enum AlbumState {
    DEFAULT,
    SELECTION_ENABLED,
    DELETION_IN_PROGRESS
} AlbumState;

@interface LoUICollectionViewController ()<UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate>
- (IBAction)doDeleteSelection:(id)sender;
- (IBAction)doShare:(id)sender;
- (IBAction)doCellAction:(id)sender;
- (IBAction)doToggleSelect:(UIBarButtonItem *)sender;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *selectButton;
@property (weak, nonatomic) IBOutlet UICollectionView *collectionView;
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (strong, nonatomic) LoAppDelegate *appDelegate;
@property (strong, nonatomic) NSMutableSet *selectedAssets;
@property (strong, nonatomic) UIButton *deleteButton;
@property (strong, nonatomic) UIButton *shareButton;
@property (nonatomic) AlbumState state;
@end

@implementation LoUICollectionViewController

- (BOOL)prefersStatusBarHidden {
    return NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.sessionQueue = dispatch_queue_create("collection view proxy queue", DISPATCH_QUEUE_SERIAL);
    self.appDelegate = [[UIApplication sharedApplication] delegate];
    NSAssert(self.appDelegate.album != nil, @"album should have been set on AppDelegate");

    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    flex.width = 30;

    self.deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.deleteButton setFrame:CGRectMake(0, 0, 21, 28)];
    self.deleteButton.tintColor = self.navigationController.view.window.tintColor;
    UIImage *image = [[UIImage imageNamed:@"garbage.png"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.deleteButton setBackgroundImage:image forState:UIControlStateNormal];
    UIBarButtonItem *bar1 = [[UIBarButtonItem alloc]initWithCustomView:self.deleteButton];
    self.deleteButton.enabled = false;

    self.shareButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.shareButton setFrame:CGRectMake(0, 0, 21, 28)];
    self.shareButton.tintColor = self.navigationController.view.window.tintColor;
    UIImage *image2 = [[UIImage imageNamed:@"share.png"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.shareButton setBackgroundImage:image2 forState:UIControlStateNormal];
    UIBarButtonItem *bar2 = [[UIBarButtonItem alloc]initWithCustomView:self.shareButton];
    self.shareButton.enabled = false;

    self.navigationItem.leftBarButtonItems = [NSArray arrayWithObjects:bar1,flex,bar2, nil];
}

- (void)viewWillAppear: (BOOL)animated {
    [super viewWillAppear:animated];
    [self resetState];
    dispatch_async(self.sessionQueue, ^{
        [self.appDelegate.album addObserver:self forKeyPath:@"assets" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:AlbumAssetsRefreshContext];
    });
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    dispatch_async(self.sessionQueue, ^{
        [self.appDelegate.album updateAssets];
    });
}

- (void)viewWillDisappear: (BOOL)animated {
    [super viewWillDisappear:animated];
    [self resetState];
    dispatch_async(self.sessionQueue, ^{
        [self.appDelegate.album removeObserver:self forKeyPath:@"assets" context:AlbumAssetsRefreshContext];
    });
}

- (void)resetState {
    if (self.state == SELECTION_ENABLED) {
        self.selectButton.title = @"Select";
        self.selectedAssets = nil;
        self.deleteButton.enabled = false;
        self.shareButton.enabled = false;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData];
    });
    self.state = DEFAULT;
}

- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section {
    return self.appDelegate.album.assets.count;
}

- (LoImagePreviewCell *)collectionView: (UICollectionView *)collectionView cellForItemAtIndexPath: (NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"photoCell";
    ALAsset *asset = self.appDelegate.album.assets[self.appDelegate.album.assets.count - 1 - indexPath.row];
    CGImageRef thumbnailImageRef = [asset aspectRatioThumbnail];
    static BOOL nibMyCellLoaded = NO;
    if(!nibMyCellLoaded) {
        UINib *nib = [UINib nibWithNibName:@"photoCell" bundle: nil];
        [collectionView registerNib:nib forCellWithReuseIdentifier:CellIdentifier];
        nibMyCellLoaded = YES;
    }
    LoImagePreviewCell *cell = (LoImagePreviewCell*)[collectionView dequeueReusableCellWithReuseIdentifier:CellIdentifier forIndexPath:indexPath];

    UIImage *thumbnail = [UIImage imageWithCGImage:thumbnailImageRef];
    cell.imageView.image = thumbnail;

    if (self.state == SELECTION_ENABLED) {
        NSAssert(self.selectedAssets != nil, @"selectedAssets list must be available when state is SELECTION_ENABLED");
        if ([self.selectedAssets containsObject:asset]){
            cell.layer.borderColor = [self.navigationController.view.window.tintColor CGColor];
            cell.layer.borderWidth = 5.0;
        } else {
            cell.layer.borderWidth = 0;
        }
    } else {
        cell.layer.borderWidth = 0;
    }

//    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(didSwipe:)];
//    swipeRight.delegate = self;
//    swipeRight.numberOfTouchesRequired = 1;
//    [swipeRight setDirection:UISwipeGestureRecognizerDirectionRight];
//    [cell addGestureRecognizer:swipeRight];
//
//    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(didSwipe:)];
//    swipeLeft.delegate = self;
//    swipeLeft.numberOfTouchesRequired = 1;
//    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
//    [cell addGestureRecognizer:swipeLeft];

    return cell;
}

- (IBAction)doDeleteSelection:(id)sender {
    if (self.selectedAssets.count < 1) {
        return;
    }
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Delete Pictures"
                                                    message:@"Would you like to delete the selected pictures?"
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:nil];
    [alert addButtonWithTitle:@"Delete"];
    [alert show];
}

- (IBAction)doShare:(id)sender {
    NSIndexPath *indexPath = [self.collectionView indexPathForCell:(UICollectionViewCell *)((UIView *)sender).superview.superview.superview];
    UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:@[self.appDelegate.album.assets[self.appDelegate.album.assets.count - 1 - indexPath.row]] applicationActivities:nil];
    [self presentViewController:activityController animated:YES completion:nil];
}

- (IBAction)doCellAction:(id)sender {
    if (self.state == SELECTION_ENABLED){
        NSIndexPath *indexPath = [self.collectionView indexPathForCell: (UICollectionViewCell *)((UIView *)sender).superview.superview.superview];
        NSInteger index = self.appDelegate.album.assets.count - 1 - indexPath.row;
        ALAsset *asset = self.appDelegate.album.assets[index];
        if ([self.selectedAssets containsObject:asset]) {
            [self.selectedAssets removeObject:asset];
        } else {
            [self.selectedAssets addObject:asset];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.collectionView reloadData];
        });
    } else {
        [self performSegueWithIdentifier: @"viewImage" sender: ((UIView *)sender).superview.superview.superview];
    }
}

- (IBAction)doToggleSelect:(UIBarButtonItem *)sender {
    NSAssert(sender == self.selectButton, @"select toggle sender was not known select button");
    if (self.state == SELECTION_ENABLED) {
        [self resetState];
    } else {
        self.state = SELECTION_ENABLED;
        self.selectButton.title = @"Cancel";
        self.selectedAssets = [[NSMutableSet alloc] init];
        self.deleteButton.enabled = true;
        self.shareButton.enabled = true;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.collectionView reloadData];
        });
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"viewImage"]) {
        NSIndexPath *indexPath = [self.collectionView indexPathForCell:(UICollectionViewCell *)sender];
        LoImageViewController *destViewController = segue.destinationViewController;
        destViewController.initialIndex = self.appDelegate.album.assets.count - 1 - indexPath.row;
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        if (self.state == SELECTION_ENABLED) {
            NSAssert(self.selectedAssets != nil, @"selectedAssets set must exist for deletion in SELECTION_ENABLED state.");
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Deletion in progress"
                                                                message:@"brb"
                                                               delegate:self
                                                      cancelButtonTitle:nil
                                                      otherButtonTitles:nil];
                [alert show];
                dispatch_async(self.sessionQueue, ^(){
                    [self.appDelegate.album deleteAssetList: [NSMutableArray arrayWithArray:[self.selectedAssets allObjects]]
                                        withCompletionBlock:^(){
                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                [alert dismissWithClickedButtonIndex:0 animated:YES];
                                            });
                                        }];
                });
            });
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
	if (context == AlbumAssetsRefreshContext) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self resetState];
        });
	}
}


@end
