//
//  HTSAsyncLayer.m
//  HTSLiveRoomSDK
//
//  Created by 李应鹏 on 2017/10/23.
//

#import "HTSAsyncLayer.h"
#import "HTSAsyncTransaction.h"
#import "HTSAsyncDefine.h"
#import "HTSAsyncTransactionContainer.h"
#import <libkern/OSAtomic.h>

@implementation HTSAsyncLayerDisplayTask
@end

@implementation HTSAsyncLayer

#pragma mark - Override

+ (id)defaultValueForKey:(NSString *)key {
    if ([key isEqualToString:@"displaysAsynchronously"]) {
        return @(YES);
    } else {
        return [super defaultValueForKey:key];
    }
}

- (instancetype)init {
    self = [super init];
    static CGFloat scale; //global
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        scale = [UIScreen mainScreen].scale;
    });
    self.contentsScale = scale;
    _displaysAsynchronously = YES;
    return self;
}

- (void)dealloc {
    [self increase];
}

- (void)setNeedsDisplay {
    [self _cancelAsyncDisplay];
    [super setNeedsDisplay];
}

- (void)display {
    super.contents = super.contents;
    [self _displayAsync:_displaysAsynchronously];
}

#pragma mark - Private

- (void)_displayAsync:(BOOL)async {
    __strong id<HTSAsyncLayerDelegate> delegate = self.delegate;
    HTSAsyncLayerDisplayTask *task = [delegate newAsyncDisplayTask];
    if (!task.display) {
        if (task.willDisplay) task.willDisplay(self);
        self.contents = nil;
        if (task.didDisplay) task.didDisplay(self, YES);
        return;
    }
    
    hts_async_transaction_operation_completion_block_t completionBlock = ^(id<NSObject> value, BOOL canceled) {
        HTSDisplayAssertMainThread();
        if (!canceled) {
            UIImage *image = (UIImage *)value;
            self.contents = (id)image.CGImage;
            if (task.didDisplay) task.didDisplay(self, YES);
        }
    };
    
    int32_t value = self.value;
    BOOL (^isCancelled)(void) = ^BOOL() {
        return value != self.value;
    };
    CGRect bounds = self.bounds;
    hts_async_transaction_operation_block_t displayBlock = ^id {
        if (isCancelled()) {
            UIGraphicsEndImageContext();
            dispatch_async(dispatch_get_main_queue(), ^{
                if (task.didDisplay) task.didDisplay(self, NO);
            });
            return nil;
        }
        BOOL opaque = self.opaque;
        UIGraphicsBeginImageContextWithOptions(bounds.size, opaque, self.contentsScale);
        CGContextRef context = UIGraphicsGetCurrentContext();
        task.display(context, bounds, isCancelled);
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return image;
    };
    
    if (async) {
        if (task.willDisplay) task.willDisplay(self);
        self.isAsyncContainer = YES;
        CALayer *containerLayer = self.parentTransactionContainer;
        HTSAsyncTransaction *transaction = containerLayer.asyncTransaction;
        [transaction addOperationWithBlock:displayBlock completion:completionBlock];
    } else {
        if (task.willDisplay) task.willDisplay(self);
        UIImage *image = (UIImage *)displayBlock();
        self.contents = (id)image.CGImage;
        if (task.didDisplay) task.didDisplay(self, NO);
    }
}

- (void)_cancelAsyncDisplay {
    [self increase];
}

- (int32_t)increase {
    return OSAtomicIncrement32(&_value);
}

@end

