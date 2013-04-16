//
// CXILApplication.m
// Classix
//
// Copyright (C) 2012 Félix Cloutier
//
// This file is part of Classix.
//
// Classix is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// Classix is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
// A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// Classix. If not, see http://www.gnu.org/licenses/.
//

#include <list>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include "CommonDefinitions.h"

#import "CXILApplication.h"
#import "CXILWindowDelegate.h"

#define IPC_PARAM(name, type)	type name; [self readInto:&name size:sizeof name]

using namespace Common;
using namespace InterfaceLib;

static inline BOOL CXILIsFDValid(int fd)
{
	return fcntl(fd, F_GETFL) != -1 || errno != EBADF;
}

static uint32_t CXILEventTimeStamp()
{
	mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    uint64_t absTime = mach_absolute_time();
    absTime *= info.numer;
    absTime /= info.denom;
    return static_cast<uint32_t>(absTime / (1000000000. / 60.));
}

static InterfaceLib::Point CXILGlobalNSPointToPoint(NSPoint pt)
{
	uint32_t screenHeight = NSScreen.mainScreen.frame.size.height;
	InterfaceLib::Point outPoint;
	outPoint.h = pt.x;
	outPoint.v = screenHeight / 2 - pt.y;
	return outPoint;
}

static uint16_t CXILEventRecordModifierFlags(NSUInteger modifierFlags)
{
	uint16_t modifiers = 0;
	if ((modifierFlags & NSCommandKeyMask) == NSCommandKeyMask)
		modifiers |= static_cast<uint16_t>(EventModifierFlags::cmdKey);
	
	if ((modifierFlags & NSShiftKeyMask) == NSShiftKeyMask)
		modifiers |= static_cast<uint16_t>(EventModifierFlags::shiftKey);
	
	if ((modifierFlags & NSAlphaShiftKeyMask) == NSAlphaShiftKeyMask)
		modifiers |= static_cast<uint16_t>(EventModifierFlags::alphaLock);
	
	if ((modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask)
		modifiers |= static_cast<uint16_t>(EventModifierFlags::optionKey);
	
	if ((modifierFlags & NSControlKeyMask) == NSControlKeyMask)
		modifiers |= static_cast<uint16_t>(EventModifierFlags::controlKey);
	
	// TODO active state?
	// TODO right shift, command, control?
	return modifiers;
}

@interface CXILApplication (GoryDetails)

-(BOOL)suggestEventRecord:(const EventRecord&)record;
-(NSRect)classicRectToXRect:(InterfaceLib::Rect)rect;

@end

@implementation CXILApplication
{
	int writeHandle;
	int readHandle;
	dispatch_source_t ipcSource;
	
	std::list<EventRecord> eventQueue;
	uint16_t mouseButtonState;
	EventMask currentlyWaitingOn;
	
	NSRect screenBounds;
	CXILWindowDelegate* windowDelegate;
}

#define IPC_INDEX(x) [(unsigned)IPCMessage::x]

SEL ipcSelectors[] = {
	IPC_INDEX(Beep) = @selector(beep),
	IPC_INDEX(PeekNextEvent) = @selector(peekNextEvent),
	IPC_INDEX(DequeueNextEvent) = @selector(discardNextEvent),
	IPC_INDEX(CreateWindow) = @selector(createWindow),
	IPC_INDEX(RefreshWindow) = @selector(refreshWindow),
};

const size_t ipcSelectorCount = sizeof ipcSelectors / sizeof(SEL);

#pragma mark -
-(id)init
{
	if (!(self = [super init]))
		return nil;
	
	NSArray* arguments = NSProcessInfo.processInfo.arguments;
	if (arguments.count != 3)
	{
		NSLog(@"InterfaceLibHead is not meant to be run directly. Please let InterfaceLib launch it.");
		NSLog(@"Bad arguments passed to main().");
		return nil;
	}
	
	readHandle = [arguments[1] intValue];
	writeHandle = [arguments[2] intValue];
	
	if (readHandle == 0 || writeHandle == 0 || !CXILIsFDValid(readHandle) || !CXILIsFDValid(writeHandle))
	{
		NSLog(@"InterfaceLibHead is not meant to be run directly. Please let InterfaceLib launch it.");
		NSLog(@"Either the read or write pipe is invalid.");
		return nil;
	}
	
	ipcSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, readHandle, 0, dispatch_get_main_queue());
	dispatch_source_set_event_handler(ipcSource, ^{ [self processIPCMessage]; });
	dispatch_resume(ipcSource);
	
	windowDelegate = [[CXILWindowDelegate alloc] init];
	screenBounds = NSScreen.mainScreen.frame;
	
	NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
	[center addObserver:self selector:@selector(receiveNotification:) name:nil object:nil];
	
	return self;
}

-(void)sendEvent:(NSEvent *)theEvent
{
	NSPoint globalCoordinates = [NSEvent mouseLocation];
	EventRecord eventRecord = {
		.when = Common::UInt32(theEvent.timestamp * 60), // Mac OS Classic considers there are 60 ticks per second
		.where = CXILGlobalNSPointToPoint(globalCoordinates),
	};
	
	uint16_t modifiers = mouseButtonState | CXILEventRecordModifierFlags(theEvent.modifierFlags);
	uint32_t message = 0;
	
	switch (theEvent.type)
	{
		case NSRightMouseDown:
			modifiers |= static_cast<uint16_t>(EventModifierFlags::controlKey);
		case NSLeftMouseDown:
			eventRecord.what = Common::UInt16(static_cast<uint16_t>(EventCode::mouseDown));
			mouseButtonState = static_cast<uint16_t>(EventModifierFlags::mouseButtonState);
			break;
			
		case NSRightMouseUp:
			modifiers |= static_cast<uint16_t>(EventModifierFlags::controlKey);
		case NSLeftMouseUp:
			eventRecord.what = Common::UInt16(static_cast<uint16_t>(EventCode::mouseUp));
			mouseButtonState = 0;
			break;
			
		case NSKeyDown:
			message = ((theEvent.keyCode & 0xff) << 8);
			message |= [theEvent.characters cStringUsingEncoding:NSMacOSRomanStringEncoding][0];
			eventRecord.what =
				Common::UInt16(static_cast<uint16_t>(theEvent.isARepeat ? EventCode::autoKey : EventCode::keyDown));
			break;
			
		case NSKeyUp:
			message = ((theEvent.keyCode & 0xff) << 8);
			message |= [theEvent.characters cStringUsingEncoding:NSMacOSRomanStringEncoding][0];
			eventRecord.what = Common::UInt16(static_cast<uint16_t>(EventCode::keyUp));
			break;
			
		default:
			// unrecognized event, skip it
			[super sendEvent:theEvent];
			return;
			
		// TODO updateEvent, diskEvent, activateEvent, osEvent, highLevelEvent
	}
	
	eventRecord.message = message;
	eventRecord.modifiers = Common::UInt16(modifiers);
	eventQueue.push_back(eventRecord);
	[self suggestEventRecord:eventRecord];
	
	// let non-keyboard events get to Cocoa
	const NSUInteger eventMask = NSKeyUpMask | NSKeyDownMask;
	if (((1 << theEvent.type) & eventMask) == 0)
	{
		[super sendEvent:theEvent];
	}
}

-(void)receiveNotification:(NSNotification *)notification
{
	if ([notification.name isEqualToString:NSWindowDidBecomeKeyNotification] ||
		[notification.name isEqualToString:NSWindowDidResignKeyNotification])
	{
		uint16_t modifiers = mouseButtonState | CXILEventRecordModifierFlags([NSEvent modifierFlags]);
		if ([notification.name isEqualToString:NSWindowDidBecomeKeyNotification])
			modifiers |= static_cast<uint16_t>(EventModifierFlags::activeFlag);
		
		EventRecord focusRecord = {
			.what = Common::UInt16(static_cast<uint16_t>(EventCode::activateEvent)),
			.when = Common::UInt32(CXILEventTimeStamp()),
			.where = CXILGlobalNSPointToPoint([NSEvent mouseLocation]),
			.modifiers = Common::UInt16(modifiers),
			.message = Common::UInt32([windowDelegate keyOfWindow:notification.object])
		};
		
		eventQueue.push_back(focusRecord);
		[self suggestEventRecord:focusRecord];
	}
}

-(void)dealloc
{
	if (ipcSource != nullptr)
		dispatch_suspend(ipcSource);
}

#pragma mark -
#pragma mark RPCs
-(void)readInto:(void *)into size:(size_t)size
{
	size_t count = read(readHandle, into, size);
	if (count < size)
	{
		// broken pipe: the parent process probably quit
		[self terminate:self];
	}
}

-(void)writeFrom:(const void *)from size:(size_t)size
{
	size_t count = write(writeHandle, from, size);
	if (count < size)
	{
		// broken pipe: the parent process probably quit
		[self terminate:self];
	}
}

-(void)sendDone
{
	[self writeFrom:"DONE" size:4];
}

-(void)expectDone
{
	char done[4];
	[self readInto:done size:sizeof done];
	if (memcmp(done, "DONE", sizeof done) != 0)
	{
		NSLog(@"*** Expected a DONE, got %.4s", done);
		abort();
	}
}

-(void)processIPCMessage
{
	unsigned messageType;
	[self readInto:&messageType size:sizeof messageType];
	
	NSAssert(messageType < ipcSelectorCount, @"Message type %u is undefined", messageType);
	
	// this operation is safe, because the selector accepts no argument and returns no object
	// since no leak is possible, we shut up the compiler
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	[self performSelector:ipcSelectors[messageType]];
#pragma clang diagnostic pop
}

-(void)peekNextEvent
{
	IPC_PARAM(desiredEvent, uint16_t);
	[self expectDone];
	
	currentlyWaitingOn = static_cast<EventMask>(desiredEvent);
	
	// if we have one such event, send it to the client
	for (const EventRecord& event : eventQueue)
	{
		if ([self suggestEventRecord:event])
		{
			return;
		}
	}
	
	// otherwise, wait for one such event
}

-(void)discardNextEvent
{
	IPC_PARAM(desiredEvent, uint16_t);
	[self expectDone];
	
	for (auto iter = eventQueue.begin(); iter != eventQueue.end(); iter++)
	{
		if (((1 << iter->what) & desiredEvent) != 0)
		{
			eventQueue.erase(iter);
			break;
		}
	}
	
	[self sendDone];
}

-(void)beep
{
	[self expectDone];
	NSBeep();
	[self sendDone];
}

-(void)createWindow
{
	IPC_PARAM(key, uint32_t);
	IPC_PARAM(surfaceId, IOSurfaceID);
	IPC_PARAM(windowRect, InterfaceLib::Rect);
	IPC_PARAM(visible, BOOL);
	IPC_PARAM(title, InterfaceLib::ShortString);
	IPC_PARAM(createBehind, uint32_t);
	[self expectDone];
	
	NSString* nsTitle = [NSString stringWithCString:title encoding:NSMacOSRomanStringEncoding];
	NSRect frame = [self classicRectToXRect:windowRect];
	
	IOSurfaceRef surface = IOSurfaceLookup(surfaceId);
	[windowDelegate createWindow:key withRect:frame surface:surface title:nsTitle visible:visible behind:createBehind];
	IOSurfaceDecrementUseCount(surface);
	[self sendDone];
}

-(void)refreshWindow
{
	IPC_PARAM(key, uint32_t);
	[self expectDone];
	
	[windowDelegate refreshWindow:key];
	
	[self sendDone];
}

#pragma mark -
#pragma mark Gory details

-(BOOL)suggestEventRecord:(const EventRecord &)record
{
	uint16_t eventCodeMask = 1 << record.what;
	if ((eventCodeMask & static_cast<uint16_t>(currentlyWaitingOn)) != 0)
	{
		[self writeFrom:&record size:sizeof record];
		[self sendDone];
		currentlyWaitingOn = EventMask::noEvent;
		return YES;
	}
	return NO;
}

-(NSRect)classicRectToXRect:(InterfaceLib::Rect)rect
{
	CGFloat x = rect.left + screenBounds.size.width / 2;
	CGFloat y = -rect.bottom + screenBounds.size.height / 2;
	CGFloat width = rect.right - rect.left;
	CGFloat height = rect.bottom - rect.top;
	return NSMakeRect(x, y, width, height);
}

@end