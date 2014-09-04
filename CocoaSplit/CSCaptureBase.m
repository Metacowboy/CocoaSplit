//
//  CaptureBase.m
//  CocoaSplit
//
//  Created by Zakk on 7/21/14.
//  Copyright (c) 2014 Zakk. All rights reserved
//

#import "CSCaptureBase.h"
#import "SourceCache.h"
#import <objc/runtime.h>

@implementation CSCaptureBase

@synthesize activeVideoDevice = _activeVideoDevice;

+(NSString *) label
{
    return NSStringFromClass(self);
}


-(instancetype) init
{
    if (self = [super init])
    {
        self.needsSourceSelection = YES;
        self.allowDedup = YES;
    }
    
    return self;
}


-(void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.activeVideoDevice.uniqueID forKey:@"active_uniqueID"];
    [aCoder encodeBool:self.allowDedup forKey:@"allowDedup"];
}


-(id) initWithCoder:(NSCoder *)aDecoder
{
    if (self = [self init])
    {
     
        self.allowDedup = [aDecoder decodeBoolForKey:@"allowDedup"];
        self.savedUniqueID = [aDecoder decodeObjectForKey:@"active_uniqueID"];
        [self setDeviceForUniqueID:self.savedUniqueID];
    }
    
    return self;
}

-(NSViewController *)configurationView
{
    
    NSViewController *configViewController;
    
    NSString *controllerName = [NSString stringWithFormat:@"%@ViewController", self.className];
    
    
    Class viewClass = NSClassFromString(controllerName);
    
    if (viewClass)
    {
        
        configViewController = [[viewClass alloc] initWithNibName:controllerName bundle:[NSBundle bundleForClass:self.class]];
        
        if (configViewController)
        {
            
            //Should probably make a base class for view controllers and put captureObj there
            //but for now be gross.
            [configViewController setValue:self forKey:@"captureObj"];
        }
    }
    return configViewController;
    
}


-(void)setDeviceForUniqueID:(NSString *)uniqueID
{
    CSAbstractCaptureDevice *dummydev = [[CSAbstractCaptureDevice alloc] init];
    
    dummydev.uniqueID = uniqueID;
    
    NSArray *currentAvailableDevices;
    
    currentAvailableDevices = self.availableVideoDevices;
    
    
    NSUInteger sidx;
    sidx = [currentAvailableDevices indexOfObject:dummydev];
    
    if (sidx == NSNotFound)
    {
        self.activeVideoDevice = nil;
    } else {
        
        self.activeVideoDevice = [currentAvailableDevices objectAtIndex:sidx];
    }
}

-(CIImage *) currentImage
{
    return nil;
}


-(CVImageBufferRef) getCurrentFrame
{
    return NULL;
}




-(int)render_height
{
    NSNumber *ret = [self.inputSource valueForKeyPath:@"display_height"];
    return [ret intValue];
}

-(int)render_width
{
    
    NSNumber *ret = [self.inputSource valueForKeyPath:@"display_width"];
    return [ret intValue];
}

/*
-(id) awakeAfterUsingCoder:(NSCoder *)aDecoder
{
    SourceCache *sharedCache = [SourceCache sharedCache];
    
    return [sharedCache cacheSource:self uniqueID:self.activeVideoDevice.uniqueID];
}
*/

-(id) copyWithZone:(NSZone *)zone
{
  
    
    id newCopy = [[self.class alloc] init];
    
    
    
    //This is gross I'm sorry
    
    unsigned int propCount;
    objc_property_t *myProperties = class_copyPropertyList(self.class, &propCount);
    for (unsigned int i = 0; i < propCount; i++)
    {
        objc_property_t prop = myProperties[i];
        const char *propName = property_getName(prop);
        
        NSString *pName = [[NSString alloc] initWithBytes:propName length:strlen(propName) encoding:NSUTF8StringEncoding];
        id propertyValue = [self valueForKey:pName];
        [newCopy setValue:propertyValue forKey:pName];
    }
    
    
    return newCopy;
    
}

-(void) setValue:(id)value forUndefinedKey:(NSString *)key
{
    //hack so we don't throw exceptions during the above function
    return;
}


@end
