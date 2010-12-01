//
//  RKRequestQueue.m
//  RestKit
//
//  Created by Blake Watters on 12/1/10.
//  Copyright 2010 Two Toasters. All rights reserved.
//

#import "RKRequestQueue.h"
#import "RKResponse.h"
#import "RKNotifications.h"

static RKRequestQueue* gSharedQueue = nil;

static const NSTimeInterval kFlushDelay = 0.3;
static const NSTimeInterval kTimeout = 300.0;
static const NSInteger kMaxConcurrentLoads = 5;

@implementation RKRequestQueue

@synthesize suspended = _suspended;

+ (RKRequestQueue*)sharedQueue {
	if (!gSharedQueue) {
		gSharedQueue = [[RKRequestQueue alloc] init];
	}
	return gSharedQueue;
}

+ (void)setSharedQueue:(RKRequestQueue*)requestQueue {
	if (gSharedQueue != requestQueue) {
		[gSharedQueue release];
		gSharedQueue = [requestQueue retain];
	}
}

- (id)init {
	if (self = [super init]) {
		_requests = [[NSMutableArray alloc] init];
		_suspended = NO;
		_totalLoading = 0;
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(responseDidLoad:) 
													 name:kRKResponseReceivedNotification 
												   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(responseDidLoad:) 
													 name:kRKRequestFailedWithErrorNotification 
												   object:nil];		
	}
	
	return self;
}

- (void)dealloc {
	[_queueTimer invalidate];
	[_requests release];
	_requests = nil;
	[super dealloc];
}

- (void)loadNextInQueueDelayed {
	if (!_queueTimer) {
		_queueTimer = [NSTimer scheduledTimerWithTimeInterval:kFlushDelay 
													   target:self
													 selector:@selector(loadNextInQueue) 
													 userInfo:nil 
													  repeats:NO];
	}
}

- (void)dispatchRequest:(RKRequest*)request {
	[request performSelector:@selector(fireAsynchronousRequest)];
}

- (void)loadNextInQueue {
	_queueTimer = nil;
	
	for (int i = 0;
		 i < kMaxConcurrentLoads && _totalLoading < kMaxConcurrentLoads
		 && _requests.count;
		 ++i) {
		RKRequest* request = [[_requests objectAtIndex:0] retain];
		[_requests removeObjectAtIndex:0];		
		[self dispatchRequest:request];
		[request release];
	}
	
	if (_requests.count && !_suspended) {
		[self loadNextInQueueDelayed];
	}
}

- (void)setSuspended:(BOOL)isSuspended {
	_suspended = isSuspended;
	
	if (!_suspended) {
		[self loadNextInQueue];
	} else if (_queueTimer) {
		[_queueTimer invalidate];
		_queueTimer = nil;
	}
}

- (void)sendRequest:(RKRequest*)request {
	if (_suspended || _totalLoading == kMaxConcurrentLoads) {
		[_requests addObject:request];
	} else {
		++_totalLoading;
		[self dispatchRequest:request];
	}
}

- (void)cancelRequest:(RKRequest*)request {
	[request cancel];
}

- (void)cancelRequestsWithDelegate:(NSObject<RKRequestDelegate>*)delegate {
	for (RKRequest* request in _requests) {
		if (request.delegate && request.delegate == delegate) {
			[request cancel];
		}
	}
}

- (void)cancelAllRequests {
	for (RKRequest* request in [[[_requests copy] autorelease] objectEnumerator]) {
		[request cancel];
	}
}

/**
 * Invoked via observation when a request has loaded a response. Remove
 * the completed request from the queue and continue processing
 */
- (void)responseDidLoad:(NSNotification*)notification {
	_totalLoading--;
	[self loadNextInQueue];
}

@end
