//
//  CDOperationQueue.m
//  Conductor
//
//  Created by Andrew Smith on 10/21/11.
//  Copyright (c) 2011 Andrew B. Smith ( http://github.com/drewsmits ). All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy 
// of this software and associated documentation files (the "Software"), to deal 
// in the Software without restriction, including without limitation the rights 
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies 
// of the Software, and to permit persons to whom the Software is furnished to do so, 
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included 
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "CDOperationQueue.h"

static inline NSString *StringForCDOperationQueueState(CDOperationQueueState state) {
    switch (state) {
        case CDOperationQueueStateReady:
            return @"isReady";
            break;
        case CDOperationQueueStateExecuting:
            return @"isExecuting";
            break;
        case CDOperationQueueStateFinished:
            return @"isFinished";
            break;
        case CDOperationQueueStateSuspended:
            return @"isSuspended";
        default:
            return nil;
            break;
    }
}

@interface CDOperationQueue ()

@property (nonatomic, readwrite, strong) NSOperationQueue *queue;
@property (nonatomic, readwrite, strong) NSMutableDictionary *operations;
@property (nonatomic, assign) CDOperationQueueState state;

- (void)operationDidFinish:(CDOperation *)operation;

@end

@implementation CDOperationQueue

@synthesize queue,
            operations,
            progressWatcher,
            state = _state;

- (id)init {
    self = [super init];
    if (self) {
        self.queue      = [[NSOperationQueue alloc] init];        
        self.operations = [[NSMutableDictionary alloc] init];
        self.state      = CDOperationQueueStateReady;
    }
    return self;
}

+ (id)queueWithName:(NSString *)queueName {
    CDOperationQueue *q = [[self alloc] init];
    q.queue.name = queueName;
    return q;
}

- (void)queueDidFinish {
    
    if (self.progressWatcher) {
        [self.progressWatcher runCompletionBlock];
    };
    
    // Update finished state last to trigger KVO
    self.state = CDOperationQueueStateFinished;
}

#pragma mark - Operations API

- (void)addOperation:(NSOperation *)operation {
    [self addOperation:operation atPriority:operation.queuePriority];
}

- (void)addOperation:(NSOperation *)operation 
          atPriority:(NSOperationQueuePriority)priority {
        
    // Update queue State
    self.state = CDOperationQueueStateExecuting;
    
    // KVO if CDOperation class, otherwise skip the awesome.  Why wouldn't you
    // want the awesome though?  Consider subclassing CDOperation.
    if ([operation isKindOfClass:[CDOperation class]]) {
        
        // Add operation to operations dict
        CDOperation *op = (CDOperation *)operation;
        [self.operations setObject:op forKey:op.identifier];
        
        // KVO operation isFinished.  Allows cleanup after operation is
        // finished or canceled, as well as queue progress updates.
        [op addObserver:self
             forKeyPath:@"isFinished" 
                options:NSKeyValueObservingOptionNew 
                context:nil];
    }
    
    // set priority
    [operation setQueuePriority:priority];
    
    // Update progress watcher count
    if (self.progressWatcher) {
        [self.progressWatcher addToStartingOperationCount:1];
    }
    
    // Add operation to queue and start
    [self.queue addOperation:operation];
}

- (void)removeOperation:(CDOperation *)operation {
    if (![self.operations objectForKey:operation.identifier]) return;
    
    ConductorLogTrace(@"Removing operation %@ from queue %@", operation.identifier, self.name);
    
    [operation removeObserver:self forKeyPath:@"isFinished"];
    [self.operations removeObjectForKey:operation.identifier];
    
    if (self.progressWatcher) {
        [self.progressWatcher runProgressBlockWithCurrentOperationCount:self.operationCount];
    }
}

- (void)cancelAllOperations {
    // We don't want to KVO any operations anymore, because
    // we are cancelling.
    for (CDOperation *operation in self.queue.operations) {
        [self removeOperation:operation];
    }
    
    [self.queue cancelAllOperations];
        
    // Allow NSOperation queue to start operations and clear themselves out.
    // They will all be marked as canceled, and if you build your sublcass
    // correctly, they will exit properly.
    [self setSuspended:NO];
}

- (void)operationDidFinish:(CDOperation *)operation {
    [self removeOperation:operation];
    
    if (self.operationCount == 0) {
        [self queueDidFinish];
    }
    
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

- (BOOL)updatePriorityOfOperationWithIdentifier:(id)identifier 
                                  toNewPriority:(NSOperationQueuePriority)priority {
    CDOperation *op = [self getOperationWithIdentifier:identifier];
    
    // These tests are probably not necessry, just thrown in for extra safety
    if (op && ![op isExecuting] && ![op isCancelled] && ![op isFinished]) {
        [op setQueuePriority:priority];
        return YES;
    }
    
    return NO;
}

#pragma mark - Progress

- (void)addProgressWatcherWithProgressBlock:(CDOperationQueueProgressWatcherProgressBlock)progressBlock
                         andCompletionBlock:(CDOperationQueueProgressWatcherCompletionBlock)completionBlock {
    
    CDOperationQueueProgressWatcher *watcher = [CDOperationQueueProgressWatcher progressWatcherWithStartingOperationCount:self.operationCount
                                                                                                            progressBlock:progressBlock
                                                                                                       andCompletionBlock:completionBlock];
    self.progressWatcher = watcher;
}

- (void)removeProgressWatcher {
    self.progressWatcher = nil;
}

#pragma mark - State

- (void)setState:(CDOperationQueueState)state {
    // Ensures KVO complience for changes in NSOperation object state
    
    if (self.state == state) {
        return;
    }
    
    NSString *oldStateString = StringForCDOperationQueueState(self.state);
    NSString *newStateString = StringForCDOperationQueueState(state);
    
    [self willChangeValueForKey:newStateString];
    [self willChangeValueForKey:oldStateString];
    _state = state;
    [self didChangeValueForKey:oldStateString];
    [self didChangeValueForKey:newStateString];
}

- (BOOL)isReady {
    return (self.state == CDOperationQueueStateReady);
}

- (BOOL)isExecuting {
    return (self.state == CDOperationQueueStateExecuting);
}

- (BOOL)isFinished {
    return (self.state == CDOperationQueueStateFinished);
}

- (BOOL)isSuspended {
    return (self.state == CDOperationQueueStateSuspended);
}

#pragma mark - Accessors

- (void)setSuspended:(BOOL)suspend {
    [self.queue setSuspended:suspend];
    
    if (suspend) {
        ConductorLogTrace(@"Suspending queue \"%@\"", self.name);
        self.state = CDOperationQueueStateSuspended;
    } else if (self.queue.operationCount > 0) {
        ConductorLogTrace(@"Resuming queue \"%@\"", self.name);
        self.state = CDOperationQueueStateExecuting;
    } else {
        self.state = CDOperationQueueStateReady;
    }
}

- (NSString *)name {
    return self.queue ? self.queue.name : nil;
}

- (NSInteger)operationCount {
    return self.queue ? self.queue.operationCount : 0;
}

- (CDOperation *)getOperationWithIdentifier:(id)identifier {
    CDOperation *op = [self.operations objectForKey:identifier];
    return op;
}

@end
