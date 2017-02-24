//
//  ViewController.m
//  SpeechToTextDemo
//
//  Created by Vladislav Makarenko on 2/24/17.
//  Copyright © 2017 itWorksinUA. All rights reserved.
//

#import "ViewController.h"
@import Speech;
@import AVFoundation;

typedef NS_ENUM(NSUInteger, LATSpeechManagerError) {
    LATSpeechManagerErrorUnsupportedLocale,
    LATSpeechManagerErrorSpeechRecognitionDenied,
    LATSpeechManagerErrorManagerIsBusy,
};

@interface ViewController () <SFSpeechRecognitionTaskDelegate, AVSpeechSynthesizerDelegate>

@property (weak, nonatomic) IBOutlet UITextView *speechView;
@property (weak, nonatomic) IBOutlet UIButton *recordingButton;
@property (weak, nonatomic) IBOutlet UILabel *commandLabel;

@property (nonatomic, strong) SFSpeechRecognizer *recognizer;
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong) SFSpeechAudioBufferRecognitionRequest *request;
@property (nonatomic, strong) SFSpeechRecognitionTask *currentTask;

@property (nonatomic, strong) AVSpeechSynthesizer *synth;

@property (nonatomic, assign) BOOL taskIsRunning;
@property (nonatomic, copy) NSString *buffer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self requestAuthorization];
    [self setup];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)recordingTapped:(id)sender {
    if (self.taskIsRunning) {
        [self.recordingButton setTitle:@"Start recording" forState:UIControlStateNormal];
        [self cancelProccess];
        self.taskIsRunning = NO;
    } else {
        [self.recordingButton setTitle:@"Stop recording" forState:UIControlStateNormal];
        [self startProccess];
        self.taskIsRunning = YES;
    }
}

- (void)startProccess {
    [self startRecognizeWithSuccess:^(BOOL success) {
        if (!success) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self changeTopTextToInprogress:YES];
        });
    }];
}

- (void)cancelProccess {
    [self stopRecognize];
    
    [self setInitialState];
}

- (void)setInitialState {
    [self changeTopTextToInprogress:NO];
}

- (void)changeTopTextToInprogress:(BOOL)inProgress {
    self.commandLabel.text = (inProgress) ? @"Say something" : @"Playing";
}

- (void)setup {
    self.synth = [[AVSpeechSynthesizer alloc] init];
    self.synth.delegate = self;
    NSLocale *englishLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en-US"];
    self.recognizer = [[SFSpeechRecognizer alloc] initWithLocale:englishLocale];
    if (!self.recognizer) {
        [self showError:[self errorByType:(LATSpeechManagerErrorUnsupportedLocale)]];
    } else {
        self.recognizer.defaultTaskHint = SFSpeechRecognitionTaskHintDictation;
        
        self.request = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
        self.request.interactionIdentifier = @"com.itworksfromua.SpeechTotextDemoRequestIdentifier";
        
        self.audioEngine = [[AVAudioEngine alloc] init];
        AVAudioInputNode *node = self.audioEngine.inputNode;
        AVAudioFormat *recordingFormat = [node outputFormatForBus:0];
        [node installTapOnBus:0
                   bufferSize:1024
                       format:recordingFormat
                        block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
                            [self.request appendAudioPCMBuffer:buffer];
                        }];
    }
}

- (void)startRecognizeWithSuccess:(void(^)(BOOL success))success {
    BOOL isRunning = [self isTaskInProgress];
    (isRunning) ? [self showError:[self errorByType:LATSpeechManagerErrorManagerIsBusy]] : [self performRecognition];
    
    if (success != nil) {
        success(!isRunning);
    }
}

- (void)stopRecognize {
    if ([self isTaskInProgress]) {
        [self.currentTask finish];
        [self.audioEngine stop];
    }
}

- (void)performRecognition {
    [self.audioEngine prepare];
    NSError *error = nil;
    if ([self.audioEngine startAndReturnError:&error]) {
        self.currentTask = [self.recognizer recognitionTaskWithRequest:self.request
                                                              delegate:self];
    } else {
        [self showError:error];
    }
}

- (void)handleAuthorizationStatus:(SFSpeechRecognizerAuthorizationStatus)status {
    switch (status) {
        case SFSpeechRecognizerAuthorizationStatusNotDetermined:
            [self requestAuthorization];
            break;
        case SFSpeechRecognizerAuthorizationStatusDenied:
            [self showError:[self errorByType:LATSpeechManagerErrorSpeechRecognitionDenied]];
            break;
        case SFSpeechRecognizerAuthorizationStatusRestricted:
            break;
        case SFSpeechRecognizerAuthorizationStatusAuthorized: {
            //Everything ok
            break;
        }
    }
}

- (void)requestAuthorization {
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        [self handleAuthorizationStatus:status];
    }];
}

- (BOOL)isTaskInProgress {
    return (self.currentTask.state == SFSpeechRecognitionTaskStateRunning);
}

- (void)showError:(NSError*)error {
    self.commandLabel.text = error.localizedDescription;
    [self.recordingButton setEnabled:NO];
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:NSStringFromClass([self class]) code:code userInfo:@{ NSLocalizedDescriptionKey: description }];
}

- (NSError *)errorByType:(LATSpeechManagerError)errorType {
    switch (errorType) {
        case LATSpeechManagerErrorUnsupportedLocale:
            return [self errorWithCode:-999 description:@"Current locale is not supported"];
        case LATSpeechManagerErrorSpeechRecognitionDenied:
            return [self errorWithCode:100 description:@"Speech recognition denied by user"];
        case LATSpeechManagerErrorManagerIsBusy:
            return [self errorWithCode:500 description:@"Manager in recognizing progress now"];
    }
}

- (void)setContainedText:(NSString *)aText {
    self.speechView.text = aText;
    AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:aText];
//    utterance.pitchMultiplier = 2;
    [self.synth speakUtterance:utterance];
    [self.recordingButton setEnabled:NO];
}

#pragma mark AVSpeechSynthesizerDelegate

- (void) speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    self.commandLabel.text = @"Press the button";
    [self.recordingButton setEnabled:YES];
}

#pragma mark SFSpeechRecognitionTaskDelegate

- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishRecognition:(SFSpeechRecognitionResult *)recognitionResult {
    self.buffer = recognitionResult.bestTranscription.formattedString;
}

- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishSuccessfully:(BOOL)successfully {
    if (!successfully) {
        //  Error: SessionId=com.siri.cortex.ace.speech.session.event.SpeechSessionId@439e90ed, Message=Timeout waiting for command after 30000 ms
        //  Error: SessionId=com.siri.cortex.ace.speech.session.event.SpeechSessionId@714a717a, Message=Empty recognition
        [self showError:task.error];
        [self.recordingButton setEnabled:YES];
    } else {
        [self setContainedText:[self.buffer copy]];
    }
}

@end
