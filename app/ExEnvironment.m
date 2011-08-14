#import "ExEnvironment.h"
#import "ViCharsetDetector.h"
#import "ViError.h"
#import "ViCommon.h"
#include "logging.h"

@implementation ExEnvironment

@synthesize window;

#pragma mark -
#pragma mark Pipe Filtering

- (void)filterFinish
{
	if (![filterTask isRunning])
		DEBUG(@"task %@ is no longer running", filterTask);
	else {
		DEBUG(@"wait until exit of task %@", filterTask);
		[filterTask waitUntilExit];
	}
	int status = [filterTask terminationStatus];
	DEBUG(@"status = %d", status);

	[filterStream close];

	if (filterFailed)
		status = -1;

	/* Try to auto-detect the encoding. */
	NSStringEncoding encoding = [[ViCharsetDetector defaultDetector] encodingForData:filterOutput];
	if (encoding == 0)
		/* Try UTF-8 if auto-detecting fails. */
		encoding = NSUTF8StringEncoding;
	NSString *outputText = [[NSString alloc] initWithData:filterOutput encoding:encoding];
	if (outputText == nil) {
		/* If all else fails, use iso-8859-1. */
		encoding = NSISOLatin1StringEncoding;
		outputText = [[NSString alloc] initWithData:filterOutput encoding:encoding];
	}

	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[filterTarget methodSignatureForSelector:filterSelector]];
	[invocation setSelector:filterSelector];
	[invocation setArgument:&status atIndex:2];
	[invocation setArgument:&outputText atIndex:3];
	[invocation setArgument:&filterContextInfo atIndex:4];
	[invocation invokeWithTarget:filterTarget];

	filterTask = nil;
	filterOutput = nil;
	filterTarget = nil;
	filterContextInfo = nil;
}

- (void)filterSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	[sheet orderOut:self];

	if (returnCode == -1) {
		DEBUG(@"terminating filter task %@", filterTask);
		[filterTask terminate];
	}

	[filterIndicator stopAnimation:self];
	[self filterFinish];
}

- (IBAction)filterCancel:(id)sender
{
	[NSApp endSheet:filterSheet returnCode:-1];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event
{
	DEBUG(@"got event %lu on stream %@", event, stream);

	const void *ptr;
	NSUInteger len;

	switch (event) {
	case NSStreamEventNone:
	case NSStreamEventOpenCompleted:
	default:
		break;
	case NSStreamEventHasBytesAvailable:
		[filterStream getBuffer:&ptr length:&len];
		DEBUG(@"got %lu bytes", len);
		if (len > 0) {
			[filterOutput appendBytes:ptr length:len];
		}
		break;
	case NSStreamEventHasSpaceAvailable:
		/* All output data flushed. */
		[filterStream shutdownWrite];
		[[[filterTask standardInput] fileHandleForWriting] closeFile];
		break;
	case NSStreamEventErrorOccurred:
		INFO(@"error on stream %@: %@", stream, [stream streamError]);
		if ([window attachedSheet] != nil)
			[NSApp endSheet:filterSheet returnCode:-1];
		filterFailed = 1;
		break;
	case NSStreamEventEndEncountered:
		DEBUG(@"EOF on stream %@", stream);
		if ([window attachedSheet] != nil)
			[NSApp endSheet:filterSheet returnCode:0];
		filterDone = YES;
		break;
	case ViStreamEventWriteEndEncountered:
		DEBUG(@"EOF on write stream %@; we keep reading", stream);
		break;
	}
}

- (void)filterText:(NSString *)inputText
       throughTask:(NSTask *)task
            target:(id)target
          selector:(SEL)selector
       contextInfo:(id)contextInfo
      displayTitle:(NSString *)displayTitle
{
	filterTask = task;

	NSPipe *shellOutput = [NSPipe pipe];
	NSPipe *shellInput = [NSPipe pipe];

	[filterTask setStandardInput:shellInput];
	[filterTask setStandardOutput:shellOutput];
	//[filterTask setStandardError:shellOutput];

	DEBUG(@"launching task %@", filterTask);
	[filterTask launch];

	// setup a new runloop mode
	// schedule read and write in this mode
	// schedule a timer to track how long the task takes to complete
	// if not finished within x seconds, show a modal sheet, re-adding the runloop sources to the modal sheet runloop(?)
	// accept cancel button from sheet -> terminate task and cancel filter

	filterStream = [[ViBufferedStream alloc] initWithTask:filterTask];
	[filterStream setDelegate:self];

	filterOutput = [NSMutableData dataWithCapacity:[inputText length]];
	[filterStream writeData:[inputText dataUsingEncoding:NSUTF8StringEncoding]];

	filterDone = NO;
	filterFailed = NO;

	filterTarget = target;
	filterSelector = selector;
	filterContextInfo = contextInfo;

	/* schedule the read and write sources in the new runloop mode */
	[filterStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

	NSDate *limitDate = [NSDate dateWithTimeIntervalSinceNow:2.0];
	int done = 0;

	for (;;) {
		DEBUG(@"running until %@", limitDate);
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:limitDate];
		if ([limitDate timeIntervalSinceNow] <= 0) {
			DEBUG(@"limit date %@ reached", limitDate);
			break;
		}

		if (filterFailed) {
			DEBUG(@"%s", "filter I/O failed");
			[filterTask terminate];
			done = -1;
			break;
		}

		if (filterDone) {
			done = 1;
			break;
		}
	}

	if (done) {
		[self filterFinish];
	} else {
		[NSApp beginSheet:filterSheet
                   modalForWindow:window
                    modalDelegate:self
                   didEndSelector:@selector(filterSheetDidEnd:returnCode:contextInfo:)
                      contextInfo:NULL];
		[filterLabel setStringValue:displayTitle];
		[filterLabel setFont:[NSFont userFixedPitchFontOfSize:12.0]];
		[filterIndicator startAnimation:self];
	}
}

@end

