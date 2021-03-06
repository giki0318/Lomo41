#import "LoImageViewController.h"

#import <AssetsLibrary/AssetsLibrary.h>

#import "LoAppDelegate.h"
#import "LoAlbumProxy.h"
#import "PhotoViewController.h"

@interface LoImageViewController()<UIPageViewControllerDataSource, UIPageViewControllerDelegate>
@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property (strong, nonatomic) IBOutlet UIView *container;
@property (nonatomic) NSInteger currentIndex;
@property (nonatomic) NSInteger potentialNextIndex;
@property (nonatomic) NSInteger deleteIndex;
@property (strong, nonatomic) UIPageViewController *pagerController;
@property (weak, nonatomic) LoAppDelegate *appDelegate;
@property (strong, nonatomic) UIButton *deleteButton;
@property (strong, nonatomic) UIButton *shareButton;
@end

@implementation LoImageViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSAssert(self.pagerController != nil, @"pagerController should have been set in prepareForSegue");
    self.appDelegate = [[UIApplication sharedApplication] delegate];
    self.deleteIndex = -1;
    self.currentIndex = self.initialIndex;
    self.potentialNextIndex = self.initialIndex;
    UIImage *initialImage = [self imageForIndex:self.initialIndex];
    self.pagerController.dataSource = self;
    self.pagerController.delegate = self;
    PhotoViewController *initialPage = [PhotoViewController photoViewControllerForIndex:self.initialIndex andImage:initialImage];
    if (initialPage != nil) {
        [self.pagerController setViewControllers:@[initialPage]
                                       direction:UIPageViewControllerNavigationDirectionForward
                                        animated:NO
                                      completion:NULL];
    }
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleToolbarVisibility)];
    tapGesture.numberOfTapsRequired = 1;
    [self.container addGestureRecognizer:tapGesture];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    flex.width = 30;
    
    self.deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.deleteButton setFrame:CGRectMake(0, 0, 21, 28)];
    self.deleteButton.tintColor = self.navigationController.view.window.tintColor;
    UIImage *image = [[UIImage imageNamed:@"garbage.png"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.deleteButton setBackgroundImage:image forState:UIControlStateNormal];
    UIBarButtonItem *bar1 = [[UIBarButtonItem alloc]initWithCustomView:self.deleteButton];
    [self.deleteButton addTarget:self action:@selector(doTrash) forControlEvents:UIControlEventTouchUpInside];
    
    self.shareButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.shareButton setFrame:CGRectMake(0, 0, 21, 28)];
    self.shareButton.tintColor = self.navigationController.view.window.tintColor;
    UIImage *image2 = [[UIImage imageNamed:@"share.png"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.shareButton setBackgroundImage:image2 forState:UIControlStateNormal];
    UIBarButtonItem *bar2 = [[UIBarButtonItem alloc]initWithCustomView:self.shareButton];
    [self.shareButton addTarget:self action:@selector(doShare) forControlEvents:UIControlEventTouchUpInside];
    
    self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:bar1,flex,bar2, nil];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)refreshToIndex: (NSInteger)index {
    self.currentIndex = index;
    PhotoViewController *currentPage = [PhotoViewController photoViewControllerForIndex:index andImage:[self imageForIndex:index]];
    if (currentPage != nil) {
        [self.pagerController setViewControllers:@[currentPage]
                                       direction:UIPageViewControllerNavigationDirectionForward
                                        animated:NO
                                      completion:NULL];
    }
}

- (UIImage *)imageForIndex:(NSInteger)index {
    if (index < 0 || index >= self.appDelegate.album.assets.count) {
        return nil;
    }
    ALAsset *asset = self.appDelegate.album.assets[index];
    CGImageRef imageRef = [asset.defaultRepresentation fullResolutionImage];
    return [UIImage imageWithCGImage:imageRef scale:asset.defaultRepresentation.scale orientation:(UIImageOrientation)asset.defaultRepresentation.orientation];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pvc
      viewControllerBeforeViewController:(PhotoViewController *)vc {
    NSUInteger index = vc.index + 1;
    return [PhotoViewController photoViewControllerForIndex:index andImage:[self imageForIndex:index]];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pvc
       viewControllerAfterViewController:(PhotoViewController *)vc {
    NSUInteger index = vc.index - 1;
    return [PhotoViewController photoViewControllerForIndex:index andImage:[self imageForIndex:index]];
}

- (void)pageViewController:(UIPageViewController *)pageViewController willTransitionToViewControllers:(NSArray *)pendingViewControllers {
    self.potentialNextIndex = ((PhotoViewController *)pendingViewControllers.lastObject).index;
}

- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray *)previousViewControllers transitionCompleted:(BOOL)completed {
    if (!completed) {
        return;
    }
    self.currentIndex = self.potentialNextIndex;
}

- (void)doTrash {
    self.deleteIndex = self.currentIndex;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Delete Picture"
                                                    message:@"Would you like to delete the picture?"
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:nil];
    [alert addButtonWithTitle:@"Delete"];
    [alert show];
}

- (void)doShare {
    ALAsset *assetToShare = self.appDelegate.album.assets[self.currentIndex];
    UIImage *image = [UIImage imageWithCGImage:[[assetToShare defaultRepresentation] fullResolutionImage] scale:assetToShare.defaultRepresentation.scale orientation:(UIImageOrientation)assetToShare.defaultRepresentation.orientation];
    UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:@[image] applicationActivities:nil];
    [self presentViewController:activityController animated:YES completion:nil];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    // Deletion accepted.
    if (buttonIndex == 1) {
        NSAssert(self.deleteIndex >= 0, @"index for deletion was not set");
        if (self.appDelegate.album.assets.count > 1) {
            NSInteger newIndex = self.currentIndex < self.appDelegate.album.assets.count - 1 ? self.currentIndex : self.currentIndex - 1;
            __weak LoImageViewController *weakSelf = self;
            [self.appDelegate.album deleteAssetAtIndex:self.deleteIndex withCompletionBlock:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf refreshToIndex: newIndex];
                });
            }];
        } else {
            // We're about to empty the album. Exit after.
            [self.appDelegate.album deleteAssetAtIndex:self.deleteIndex withCompletionBlock:nil];
            [self.navigationController popViewControllerAnimated:YES];
        }
    }
}

- (void)toggleToolbarVisibility {
    if (self.navigationController.navigationBarHidden) {
        [self animateToolbarVisibility: true];
    } else {
        [self animateToolbarVisibility: false];
    }

}

- (void)animateToolbarVisibility: (bool)visible {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.navigationController setNavigationBarHidden:!visible animated:YES];
        [UIView animateWithDuration:0.25 animations:^{
            self.container.backgroundColor = visible ? [UIColor whiteColor] : [UIColor blackColor];
		}];
	});
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"containedPager"]) {
        self.pagerController = (UIPageViewController *)segue.destinationViewController;
    }
}
@end
