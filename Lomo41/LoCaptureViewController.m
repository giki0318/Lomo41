#import "LoCaptureViewController.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <AVFoundation/AVFoundation.h>
#import "ALAssetsLibrary+PhotoAlbumFunctionality.h"
#import "Lo41ShotProcessor.h"
#import "LoAlbumProxy.h"
#import "LoAppDelegate.h"
#import "LoCameraPreviewView.h"
#import "LoShotSet.h"
#import "LoUICollectionViewController.h"
#import "MotionOrientation.h"

static void * SessionRunningCameraPermissionContext = &SessionRunningCameraPermissionContext;

@interface LoCaptureViewController ()
@property (weak, nonatomic) IBOutlet UIView *shootView;
@property (weak, nonatomic) IBOutlet UIButton *shootButton;
@property (weak, nonatomic) IBOutlet UIButton *cameraToggleButton;
@property (weak, nonatomic) IBOutlet LoCameraPreviewView *previewView;
@property (weak, nonatomic) IBOutlet UIView *paneOne;
@property (weak, nonatomic) IBOutlet UIView *paneTwo;
@property (weak, nonatomic) IBOutlet UIView *paneThree;
@property (weak, nonatomic) IBOutlet UIView *paneFour;
@property (nonatomic) AVCaptureSession *captureSession;
@property (nonatomic) AVCaptureDevice *videoDevice;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureStillImageOutput *stillImageOutput;
@property (nonatomic) LoShotSet *currentShots;
@property (nonatomic) id runtimeErrorHandlingObserver;
@property (nonatomic, readonly, getter = isSessionRunningAndHasCameraPermission) BOOL sessionRunningAndHasCameraPermission;
@property (nonatomic) BOOL hasCameraPermission;
@property (nonatomic) NSTimer *timer;
@property (nonatomic) NSInteger shotCount;
@property (weak, nonatomic) LoAppDelegate *appDelegate;
- (IBAction)doShoot:(id)sender;
- (IBAction)toggleCamera:(id)sender;
@end

@implementation LoCaptureViewController

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType
                      preferringPosition:(AVCaptureDevicePosition)position {
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
	AVCaptureDevice *captureDevice = [devices firstObject];
	for (AVCaptureDevice *device in devices) {
		if ([device position] == position) {
			captureDevice = device;
			break;
		}
	}
	return captureDevice;
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device {
	if ([device hasFlash] && [device isFlashModeSupported:flashMode]) {
		NSError *error = nil;
		if ([device lockForConfiguration:&error]) {
			[device setFlashMode:flashMode];
			[device unlockForConfiguration];
		} else {
			NSLog(@"%@", error);
		}
	}
}

+ (void)setFocusMode:(AVCaptureFocusMode)focusMode forDevice:(AVCaptureDevice *)device {
    NSError *error = nil;
    if ([device isFocusModeSupported:focusMode]) {
        if ([device lockForConfiguration:&error]) {
            CGPoint autofocusPoint = CGPointMake(0.5f, 0.5f);
            [device setFocusPointOfInterest:autofocusPoint];
            [device setFocusMode:focusMode];
            [device unlockForConfiguration];
        } else {
            NSLog(@"%@", error);
        }
    }
}

+ (void)setExposureMode:(AVCaptureExposureMode)exposureMode forDevice:(AVCaptureDevice *)device {
    NSError *error = nil;
    if ([device isExposureModeSupported:exposureMode]) {
        if ([device lockForConfiguration:&error]) {
            CGPoint exposurePoint = CGPointMake(0.5f, 0.5f);
            [device setExposurePointOfInterest:exposurePoint];
            [device setExposureMode:exposureMode];
            [device unlockForConfiguration];
        } else {
            NSLog(@"%@", error);
        }
    }
}

+ (void)setTorchMode:(AVCaptureTorchMode)torchMode forDevice:(AVCaptureDevice *)device {
	if ([device hasTorch] && [device isTorchModeSupported:torchMode]) {
		NSError *error = nil;
		if ([device lockForConfiguration:&error]) {
			[device setTorchMode:torchMode];
			[device unlockForConfiguration];
		} else {
			NSLog(@"%@", error);
		}
	}
}

+ (NSSet *)keyPathsForValuesAffectingSessionRunningAndHasCameraPermission {
	return [NSSet setWithObjects:@"captureSession.running", @"hasCameraPermission", nil];
}

- (BOOL)isCurrentlyShooting {
    NSAssert(self.shotCount <= 4, @"Shot count was > 4");
    return (self.shotCount > 0);
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

- (BOOL)isSessionRunningAndHasCameraPermission {
	return self.captureSession.isRunning && self.hasCameraPermission;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.appDelegate = [[UIApplication sharedApplication] delegate];
    NSAssert(self.appDelegate.album != nil, @"album should have been set on AppDelegate");
    self.cameraToggleButton.layer.cornerRadius = 5;
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    self.currentShots = nil;
	[self checkCameraPermissions];
	dispatch_async(self.appDelegate.serialQueue, ^{
        [MotionOrientation initialize];
		NSError *error = nil;
		self.videoDevice = [LoCaptureViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
        [LoCaptureViewController setFocusMode:AVCaptureFocusModeContinuousAutoFocus forDevice:self.videoDevice];
        [LoCaptureViewController setExposureMode:AVCaptureExposureModeContinuousAutoExposure forDevice:self.videoDevice];
        [LoCaptureViewController setFlashMode:AVCaptureFlashModeOff forDevice:self.videoDevice];
		AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:self.videoDevice error:&error];
		if (error) {
			NSLog(@"%@", error);
		}
		if ([self.captureSession canAddInput:videoDeviceInput]) {
			[self.captureSession addInput:videoDeviceInput];
			self.videoDeviceInput = videoDeviceInput;
		}
		AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
		if ([self.captureSession canAddOutput:stillImageOutput]) {
			[stillImageOutput setOutputSettings:@{AVVideoCodecKey:AVVideoCodecJPEG}];
			[self.captureSession addOutput:stillImageOutput];
			self.stillImageOutput = stillImageOutput;
		}
        self.previewView.session = self.captureSession;
        if ([self.videoDevice respondsToSelector:@selector(isLowLightBoostSupported)]) {
            if ([self.videoDevice lockForConfiguration:nil]) {
                if (self.videoDevice.isLowLightBoostSupported) {
                    self.videoDevice.automaticallyEnablesLowLightBoostWhenAvailable = YES;
                }
                [self.videoDevice unlockForConfiguration];
            }
        }
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
	dispatch_async(self.appDelegate.serialQueue, ^{
		[self addObserver:self forKeyPath:@"sessionRunningAndHasCameraPermission" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:SessionRunningCameraPermissionContext];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[self.videoDeviceInput device]];
		self.runtimeErrorHandlingObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:[self captureSession] queue:nil usingBlock:^(NSNotification *note) {
			dispatch_async(self.appDelegate.serialQueue, ^{
				// Manually restarting the session since it must have been stopped due to an error.
				[self.captureSession startRunning];
			});
		}];
        [LoCaptureViewController setFocusMode: AVCaptureFocusModeContinuousAutoFocus forDevice:self.videoDevice];
		[self.captureSession startRunning];
	});
    self.shotCount = 0;
    [self.paneOne.layer setOpacity: 1.0];
    [self.paneTwo.layer setOpacity: 1.0];
    [self.paneThree.layer setOpacity: 1.0];
    [self.paneFour.layer setOpacity: 1.0];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.timer) {
        [self.timer invalidate];
        self.timer = nil;
    }
    dispatch_async(self.appDelegate.serialQueue, ^{
        self.currentShots = nil;
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
	dispatch_async(self.appDelegate.serialQueue, ^{
		[self.captureSession stopRunning];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[[self videoDeviceInput] device]];
		[[NSNotificationCenter defaultCenter] removeObserver:self.runtimeErrorHandlingObserver];
		[self removeObserver:self forKeyPath:@"sessionRunningAndHasCameraPermission" context:SessionRunningCameraPermissionContext];
	});
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (BOOL)hasRunningSessionAndCameraPermission {
	return self.captureSession.isRunning && self.hasCameraPermission;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
	if (context == SessionRunningCameraPermissionContext) {
        BOOL hasPermission = [change[NSKeyValueChangeNewKey] boolValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (hasPermission) {
                self.shootButton.enabled = YES;
            } else {
                self.shootButton.enabled = NO;
            }
        });
    }
}

- (void)subjectAreaDidChange:(NSNotification *)notification {
	CGPoint devicePoint = CGPointMake(.5, .5);
	[self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange {
	dispatch_async(self.appDelegate.serialQueue, ^{
		AVCaptureDevice *device = [self.videoDeviceInput device];
		NSError *error = nil;
		if ([device lockForConfiguration:&error]) {
			if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:focusMode]) {
				[device setFocusMode:focusMode];
				[device setFocusPointOfInterest:point];
			}
			if ([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:exposureMode]) {
				[device setExposureMode:exposureMode];
				[device setExposurePointOfInterest:point];
			}
			[device setSubjectAreaChangeMonitoringEnabled:monitorSubjectAreaChange];
			[device unlockForConfiguration];
		} else {
			NSLog(@"%@", error);
		}
	});
}

- (IBAction)toggleCamera:(id)sender {
    // Using shootButton as proxy for cameraToggleButton's disabled state.
    // This prevents button flicker due to state.
    if (!self.shootButton.enabled) {
        return;
    }
	self.shootButton.enabled = NO;
    if (self.cameraToggleButton.selected) {
        [self setToggleButtonSelected:NO];
    } else {
        [self setToggleButtonSelected:YES];
    }
	dispatch_async(self.appDelegate.serialQueue, ^{
		AVCaptureDevice *currentVideoDevice = [self.videoDeviceInput device];
		AVCaptureDevicePosition preferredPosition = AVCaptureDevicePositionUnspecified;
		AVCaptureDevicePosition currentPosition = [currentVideoDevice position];
		
		switch (currentPosition) {
			case AVCaptureDevicePositionUnspecified:
				preferredPosition = AVCaptureDevicePositionBack;
				break;
			case AVCaptureDevicePositionBack:
				preferredPosition = AVCaptureDevicePositionFront;
				break;
			case AVCaptureDevicePositionFront:
				preferredPosition = AVCaptureDevicePositionBack;
				break;
		}
		
		AVCaptureDevice *videoDevice = [LoCaptureViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:preferredPosition];
		AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
		
		[self.captureSession beginConfiguration];
		
		[self.captureSession removeInput:[self videoDeviceInput]];
		if ([self.captureSession canAddInput:videoDeviceInput]) {
			[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];
			
			[self.captureSession addInput:videoDeviceInput];
			[self setVideoDeviceInput:videoDeviceInput];
		} else {
			[self.captureSession addInput:[self videoDeviceInput]];
		}
		
		[self.captureSession commitConfiguration];
		
		dispatch_async(dispatch_get_main_queue(), ^{
            self.shootButton.enabled = YES;
		});
	});
}

- (void)setToggleButtonSelected:(BOOL)value {
    self.cameraToggleButton.selected = value;
    if (value) {
        self.cameraToggleButton.backgroundColor = self.appDelegate.window.tintColor;
    } else {
        self.cameraToggleButton.backgroundColor = [UIColor clearColor];
    }
}

- (IBAction)doShoot:(id)sender {
    if (![self isCurrentlyShooting]) {
        [LoCaptureViewController setFocusMode:AVCaptureFocusModeLocked forDevice:self.videoDevice];
        [LoCaptureViewController setExposureMode:AVCaptureExposureModeLocked forDevice:self.videoDevice];
        self.currentShots = [[LoShotSet alloc] initForSize:4];
        self.shootButton.enabled = NO;
        self.currentShots.cameraType = self.cameraToggleButton.selected ? FRONT_FACING : BACK_FACING;
        [self shootOnce];
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(shootOnce) userInfo:nil repeats:YES];
    }
}

- (void)shootOnce {
    self.shotCount++;
    bool final = false;
    __block bool failed = NO;
    if (self.shotCount >= 4) {
        [self.timer invalidate];
        self.timer = nil;
        final = true;
    }
    [self runCaptureAnimation];
    switch (self.shotCount) {
        case 1:
            self.currentShots.orientation = [MotionOrientation sharedInstance].deviceOrientation;
            [self.paneOne.layer setOpacity: 0.2];
            break;
        case 2:
            [self.paneTwo.layer setOpacity: 0.2];
            break;
        case 3:
            [self.paneThree.layer setOpacity: 0.2];
            break;
        case 4:
            [self.paneFour.layer setOpacity: 0.2];
            break;
        default:
            break;
    }
    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:[self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        if (failed) {
            return;
        }
        if (imageDataSampleBuffer) {
            CFRetain(imageDataSampleBuffer);
        } else {
            // The view may have swapped.
            failed = YES;
            return;
        }
        dispatch_async(self.appDelegate.serialQueue, ^{
            if (imageDataSampleBuffer) {
                NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                [self.currentShots addShot:[[UIImage alloc] initWithData:imageData]];
                CFRelease(imageDataSampleBuffer);
            }
            if (final) {
                [LoCaptureViewController setFocusMode: AVCaptureFocusModeContinuousAutoFocus forDevice:self.videoDevice];
                [LoCaptureViewController setExposureMode: AVCaptureExposureModeContinuousAutoExposure forDevice:self.videoDevice];
                [self processShotSet];
            }
        });
    }];
}

- (void)processShotSet {
    if (self.currentShots.count != 4) {
        self.currentShots = nil;
        self.shotCount = 0;
        return;
    }
    dispatch_async(self.appDelegate.serialQueue, ^{
        Lo41ShotProcessor* processor = [[Lo41ShotProcessor alloc] initWithShotSet:self.currentShots];
        [processor processIndividualShots];
        [processor groupShots];
        UIImage *finalGroupedImage = [processor getProcessedGroupImage];
        if (finalGroupedImage) {
            [self.appDelegate.album addImage:finalGroupedImage];
        }
        self.currentShots = nil;
        self.shotCount = 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.shootButton.enabled = YES;
            [self.paneOne.layer setOpacity: 1.0];
            [self.paneTwo.layer setOpacity: 1.0];
            [self.paneThree.layer setOpacity: 1.0];
            [self.paneFour.layer setOpacity: 1.0];
        });
    });
}

- (void)runCaptureAnimation {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.shootView.layer setOpacity:0.0];
		[UIView animateWithDuration:.25 animations:^{
            [self.shootView.layer setOpacity:1.0];
		}];
	});
}

- (void)checkCameraPermissions {
	NSString *mediaType = AVMediaTypeVideo;
	[AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
		self.hasCameraPermission = granted;
		if (!granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
				[[[UIAlertView alloc] initWithTitle:@"Permission Issue"
											message:@"Lomo41 needs permission to access your camera. Please grant it in system settings."
										   delegate:self
								  cancelButtonTitle:@"OK"
								  otherButtonTitles:nil] show];
			});
        }
	}];
}
@end
