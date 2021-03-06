//
//  PLCameraStreamingViewController.m
//  PLCameraStreamingKit
//
//  Created on 01/10/2015.
//  Copyright (c) Pili Engineering, Qiniu Inc. All rights reserved.
//

#import "PLCameraStreamingViewController.h"
#import "Reachability.h"
#import <PLCameraStreamingKit/PLCameraStreamingKit.h>

const char *stateNames[] = {
    "Unknow",
    "Connecting",
    "Connected",
    "Disconnecting",
    "Disconnected",
    "Error"
};

const char *networkStatus[] = {
    "Not Reachable",
    "Reachable via WiFi",
    "Reachable via CELL"
};

@interface PLCameraStreamingViewController ()
<
PLCameraStreamingSessionDelegate,
PLStreamingSendingBufferDelegate
>

@property (nonatomic, strong) PLCameraStreamingSession  *session;
@property (nonatomic, strong) Reachability *internetReachability;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;

@end

@implementation PLCameraStreamingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.sessionQueue = dispatch_queue_create("pili.queue.streaming", DISPATCH_QUEUE_SERIAL);
    
    // 网络状态监控
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];
    self.internetReachability = [Reachability reachabilityForInternetConnection];
    [self.internetReachability startNotifier];
    
    // PLCameraStreamingKit 使用开始
    //
    // streamJSON 是从服务端拿回的
    //
    // 从服务端拿回的 streamJSON 结构如下：
    //    @{@"id": @"stream_id",
    //      @"title": @"stream_title",
    //      @"hub": @"hub_name",
    //      @"publishKey": @"publish_key",
    //      @"publishSecurity": @"dynamic", // or static
    //      @"disabled": @(NO),
    //      @"profiles": @[@"480p", @"720p"],    // or empty Array []
    //      @"hosts": @{
    //              ...
    //      }
    NSDictionary *streamJSON;
    PLStream *stream = [PLStream streamWithJSON:streamJSON];
    
    void (^permissionBlock)(void) = ^{
        dispatch_async(self.sessionQueue, ^{
            // 视频编码配置
            PLVideoStreamingConfiguration *videoConfiguration = [PLVideoStreamingConfiguration configurationWithUserDefineDimension:CGSizeMake(320, 480)
                                                                                                                       videoQuality:kPLVideoStreamingQualityLow2];
            // 音频编码配置
            PLAudioStreamingConfiguration *audioConfiguration = [PLAudioStreamingConfiguration defaultConfiguration];
            
            // 推流 session
            self.session = [[PLCameraStreamingSession alloc] initWithVideoConfiguration:videoConfiguration
                                                                     audioConfiguration:audioConfiguration
                                                                                 stream:stream
                                                                       videoOrientation:AVCaptureVideoOrientationPortrait];
            self.session.delegate = self;
            self.session.bufferDelegate = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.session.previewView = self.view;
                UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
                tap.numberOfTapsRequired = 2;
                [self.view addGestureRecognizer:tap];
            });
        });
    };
    
    void (^noAccessBlock)(void) = ^{
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No Access", nil)
                                                            message:NSLocalizedString(@"!", nil)
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                                  otherButtonTitles:nil];
        [alertView show];
    };
    
    switch ([PLCameraStreamingSession cameraAuthorizationStatus]) {
        case PLAuthorizationStatusAuthorized:
            permissionBlock();
            break;
        case PLAuthorizationStatusNotDetermined: {
            [PLCameraStreamingSession requestCameraAccessWithCompletionHandler:^(BOOL granted) {
                granted ? permissionBlock() : noAccessBlock();
            }];
        }
            break;
        default:
            noAccessBlock();
            break;
    }
}

- (void)tap:(id)sender {
    NSString *quality = self.session.videoConfiguration.videoQuality;
    
    [self.session beginUpdateConfiguration];
    
    if ([quality isEqualToString:kPLVideoStreamingQualityLow1]) {
        quality = kPLVideoStreamingQualityLow2;
    } else if ([quality isEqualToString:kPLVideoStreamingQualityLow2]) {
        quality = kPLVideoStreamingQualityLow3;
    } else if ([quality isEqualToString:kPLVideoStreamingQualityLow3]) {
        quality = kPLVideoStreamingQualityMedium1;
    } else if ([quality isEqualToString:kPLVideoStreamingQualityMedium1]) {
        quality = kPLVideoStreamingQualityMedium2;
    } else if ([quality isEqualToString:kPLVideoStreamingQualityMedium2]) {
        quality = kPLVideoStreamingQualityMedium3;
    } else if ([quality isEqualToString:kPLVideoStreamingQualityMedium3]) {
        quality = kPLVideoStreamingQualityHigh1;
    } else if ([quality isEqualToString:kPLVideoStreamingQualityHigh1]) {
        quality = kPLVideoStreamingQualityHigh2;
    } else if ([quality isEqualToString:kPLVideoStreamingQualityHigh2]) {
        quality = kPLVideoStreamingQualityHigh3;
    } else if ([quality isEqualToString:kPLVideoStreamingQualityHigh3]) {
        quality = kPLVideoStreamingQualityLow1;
    }
    
    self.session.videoConfiguration.videoQuality = quality;
    NSLog(@"%@", quality);
    [self.session endUpdateConfiguration];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
    
    dispatch_sync(self.sessionQueue, ^{
        [self.session destroy];
    });
    self.session = nil;
    self.sessionQueue = nil;
}

#pragma mark - Notification Handler

- (void)reachabilityChanged:(NSNotification *)notif{
    Reachability *curReach = [notif object];
    NSParameterAssert([curReach isKindOfClass:[Reachability class]]);
    NetworkStatus status = [curReach currentReachabilityStatus];
    
    if (NotReachable == status) {
        // 对断网情况做处理
        [self stopSession];
    }
    
    NSLog(@"Networkt Status: %s", networkStatus[status]);
}

#pragma mark - <PLStreamingSendingBufferDelegate>

- (void)streamingSessionSendingBufferFillDidLowerThanLowThreshold:(id)session {
    if (self.session.isRunning) {
        NSString *oldVideoQuality = self.session.videoConfiguration.videoQuality;
        NSString *newVideoQuality = kPLVideoStreamingQualityLow3;
        
        if ([oldVideoQuality isEqualToString:kPLVideoStreamingQualityLow1]) {
            newVideoQuality = kPLVideoStreamingQualityLow2;
        } else if ([oldVideoQuality isEqualToString:kPLVideoStreamingQualityLow2]) {
            newVideoQuality = kPLVideoStreamingQualityLow3;
        }
        
        dispatch_sync(self.sessionQueue, ^{
            [self.session beginUpdateConfiguration];
            self.session.videoConfiguration.videoQuality = newVideoQuality;
            [self.session endUpdateConfiguration];
        });
    }
}

- (void)streamingSessionSendingBufferFillDidHigherThanHighThreshold:(id)session {
    if (self.session.isRunning) {
        NSString *oldVideoQuality = self.session.videoConfiguration.videoQuality;
        NSString *newVideoQuality = kPLVideoStreamingQualityLow1;
        
        if ([oldVideoQuality isEqualToString:kPLVideoStreamingQualityLow3]) {
            newVideoQuality = kPLVideoStreamingQualityLow2;
        } else if ([oldVideoQuality isEqualToString:kPLVideoStreamingQualityLow2]) {
            newVideoQuality = kPLVideoStreamingQualityLow1;
        }
        
        dispatch_sync(self.sessionQueue, ^{
            [self.session beginUpdateConfiguration];
            self.session.videoConfiguration.videoQuality = newVideoQuality;
            [self.session endUpdateConfiguration];
        });
    }
}

- (void)streamingSessionSendingBufferDidFull:(id)session {
    NSLog(@"Buffer is full");
}

- (void)streamingSession:(id)session sendingBufferDidDropItems:(NSArray *)items {
    NSLog(@"Frame dropped");
}

#pragma mark - <PLCameraStreamingSessionDelegate>

- (void)cameraStreamingSession:(PLCameraStreamingSession *)session streamStateDidChange:(PLStreamState)state {
    NSLog(@"Stream State: %s", stateNames[state]);
    
    // 除 PLStreamStateError 外的其余状态会回调在这个方法
    // 这个回调会确保在主线程，所以可以直接对 UI 做操作
    if (PLStreamStateConnected == state) {
        [self.actionButton setTitle:NSLocalizedString(@"Stop", nil) forState:UIControlStateNormal];
    } else if (PLStreamStateDisconnected == state) {
        [self.actionButton setTitle:NSLocalizedString(@"Start", nil) forState:UIControlStateNormal];
    }
}

- (void)cameraStreamingSession:(PLCameraStreamingSession *)session didDisconnectWithError:(NSError *)error {
    NSLog(@"Stream State: Error. %@", error);
    // PLStreamStateError 都会回调在这个方法
    // 尝试重连，注意这里需要你自己来处理重连尝试的次数以及重连的时间间隔
    [self.actionButton setTitle:NSLocalizedString(@"Reconnecting", nil) forState:UIControlStateNormal];
    [self startSession];
}

#pragma mark - Operation

- (void)stopSession {
    dispatch_async(self.sessionQueue, ^{
        [self.session stop];
    });
}

- (void)startSession {
    self.actionButton.enabled = NO;
    dispatch_async(self.sessionQueue, ^{
        [self.session startWithCompleted:^(BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.actionButton.enabled = YES;
            });
        }];
    });
}

#pragma mark - Action

- (IBAction)actionButtonPressed:(id)sender {
    if (PLStreamStateConnected == self.session.streamState) {
        [self stopSession];
    } else {
        [self startSession];
    }
}

- (IBAction)toggleCameraButtonPressed:(id)sender {
    dispatch_async(self.sessionQueue, ^{
        [self.session toggleCamera];
    });
}

- (IBAction)torchButtonPressed:(id)sender {
    dispatch_async(self.sessionQueue, ^{
        self.session.torchOn = !self.session.isTorchOn;
    });
}

- (IBAction)muteButtonPressed:(id)sender {
    dispatch_async(self.sessionQueue, ^{
        self.session.muted = !self.session.isMuted;
    });
}

- (IBAction)cancelButtonPressed:(id)sender {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
