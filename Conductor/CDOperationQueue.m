//
//  CDOperationQueue.m
//  Conductor
//
//  Created by Andrew Smith on 10/21/11.
//  Copyright (c) 2011 Posterous. All rights reserved.
//

#import "CDOperationQueue.h"

@interface CDOperationQueue (Private)
- (void)operationDidFinish:(CDOperation *)operation;
@end

@implementation CDOperationQueue

@synthesize name;

- (void)dealloc {
    [queue release];
    [name release];
    [operations release];
    
    [super dealloc];
}

//- (id)init {
//    self = [super init];
//    if (self) {
//        
//    }
//    return self;
//}

- (void)addOperation:(NSOperation *)operation {
    [self addOperation:operation atPriority:operation.queuePriority];
}

- (void)addOperation:(NSOperation *)operation 
          atPriority:(NSOperationQueuePriority)priority {
    
    if ([operation isKindOfClass:[CDOperation class]]) {
        
        // Add operation to operations dict
        CDOperation *op = (CDOperation *)operation;
        [self.operations setObject:op forKey:op.identifier];
        
        // KVO operation is finished
        [op addObserver:self
             forKeyPath:@"isFinished" 
                options:NSKeyValueObservingOptionNew 
                context:NULL];
    }
    
    // Add operation to queue and start
    [self.queue addOperation:operation];
}

- (void)operationDidFinish:(CDOperation *)operation {
    // Cleanup after operation is finished
    [operation removeObserver:self forKeyPath:@"isFinished"];    
    [self.operations removeObjectForKey:operation.identifier];
}

- (CDOperation *)getOperationWithIdentifier:(id)identifier {
    CDOperation *op = [self.operations objectForKey:identifier];
    return op;
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath 
                      ofObject:(id)object 
                        change:(NSDictionary *)change 
                       context:(void *)context {
    
    if ([keyPath isEqualToString:@"isFinished"] && [object isKindOfClass:[CDOperation class]]) {
        CDOperation *op = (CDOperation *)object;
        [self operationDidFinish:op];
    }
}

#pragma mark - Priority

- (void)updateOperationWithIdentifier:(id)identifier 
                           toPriority:(NSOperationQueuePriority)priority {
    CDOperation *op = [self getOperationWithIdentifier:identifier];
    [op setQueuePriority:priority];
}

#pragma mark - Accessors

- (NSOperationQueue *)queue {
    if (queue) return [[queue retain] autorelease];
    queue = [[NSOperationQueue alloc] init];
    return [[queue retain] autorelease];
}

- (NSMutableDictionary *)operations {
    if (operations) return [[operations retain] autorelease];
    operations = [[NSMutableDictionary alloc] init];
    return [[operations retain] autorelease];
}

- (BOOL)isRunning {
    return (self.queue.operationCount > 0);
}

@end