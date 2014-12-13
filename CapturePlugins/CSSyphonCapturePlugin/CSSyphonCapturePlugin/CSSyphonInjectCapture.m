//
//  CSSyphonInjectCapture.m
//  CSSyphonCapturePlugin
//
//  Created by Zakk on 12/7/14.
//  Copyright (c) 2014 Zakk. All rights reserved.
//

#import "CSSyphonInjectCapture.h"

@implementation CSSyphonInjectCapture

@synthesize activeVideoDevice = _activeVideoDevice;


+(NSString *)label
{
    return @"SyphonInjectCapture";
}



//Superclass calls this when a syphon notification arrives

-(void)commonInit
{
    [super commonInit];
    [self changeApplicationList];
    
}
-(void)setActiveVideoDevice:(CSAbstractCaptureDevice *)activeVideoDevice
{
    
    _activeVideoDevice = activeVideoDevice;
    [self changeAvailableVideoDevices];

    NSString *appBundleName = activeVideoDevice.uniqueID;
    NSRunningApplication *injectApp;

    NSArray *matchingApps = [NSRunningApplication runningApplicationsWithBundleIdentifier:appBundleName];
    if (matchingApps && matchingApps.count > 0)
    {
        injectApp = matchingApps.firstObject;
    }
    
    if (injectApp)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self injectApp:injectApp];
        });
    }
}


-(void)changeApplicationList
{
    
    NSArray *applications = [[[NSWorkspace sharedWorkspace] runningApplications] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"activationPolicy = %@", @(NSApplicationActivationPolicyRegular)]];
    
    NSMutableArray *retArr = [[NSMutableArray alloc] init];
    
    for(NSRunningApplication *app in applications)
    {
        CSAbstractCaptureDevice *newDev;
        
        newDev = [[CSAbstractCaptureDevice alloc] initWithName:app.localizedName device:nil uniqueID:app.bundleIdentifier];
        
        [retArr addObject:newDev];
        
        if (!self.activeVideoDevice && [newDev.uniqueID isEqualToString:self.savedUniqueID])
        {
            self.activeVideoDevice = newDev;
        }

    }
    
    
    self.availableVideoDevices = (NSArray *)retArr;
    
}



-(void)changeAvailableVideoDevices
{
    
    
    NSLog(@"CHANGE AVAILABLE VIDEO DEVICES");
    if (!self.activeVideoDevice)
    {
        return;
    }
    
    if(_syphonServer)
    {
        return;
    }
    
    
    NSString *selectedAppName = self.activeVideoDevice.captureName;
    
    
    NSArray *servers = [[SyphonServerDirectory sharedDirectory] servers];
    id sserv;
    
    for(sserv in servers)
    {
        NSString *serverDesc = [sserv objectForKey:SyphonServerDescriptionNameKey];
        

        
        NSString *syphonAppName = [sserv objectForKey:SyphonServerDescriptionAppNameKey];
        
        if ([syphonAppName isEqualToString:selectedAppName])
        {
            NSLog(@"SYPHON APP NAME MATCH");
            self.activeVideoDevice.captureDevice = sserv;
            [self startSyphon];
            break;
        }
    }
}


-(void)setBufferDimensions:(int)x_offset y_offset:(int)y_offset width:(int)width height:(int)height
{
    if (!self.injectSB)
    {
        return;
    }
    
    [self.injectSB sendEvent:'SASI' id:'ofst' parameters:'xofs', @(x_offset), 'yofs', @(y_offset),0];
    [self.injectSB sendEvent:'SASI' id:'reso' parameters:'wdth', @(width), 'hght', @(height),0];
}


-(void)changeBuffer
{
    if (!self.injectSB)
    {
        return;
    }
    
    [self.injectSB sendEvent:'SASI' id:'chbf' parameters:0];
}


-(void)toggleFast
{
    if (!self.injectSB)
    {
        return;
    }
    
    [self.injectSB sendEvent:'SASI' id:'fast' parameters:0];
}



-(void)injectApp:(NSRunningApplication *)toInject
{
    
    
    NSLog(@"INJECTING %@", toInject);
    self.injectSB = [SBApplication applicationWithProcessIdentifier:toInject.processIdentifier];
    
    [self.injectSB setTimeout:10*60];
    
    [self.injectSB setSendMode:kAEWaitReply];
    [self.injectSB sendEvent:'ascr' id:'gdut' parameters:0];
    [self.injectSB setSendMode:kAENoReply];
    [self.injectSB sendEvent:'SASI' id:'injc' parameters:0];
}


@end