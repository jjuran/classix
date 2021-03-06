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

#include <ApplicationServices/ApplicationServices.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>

#include <list>
#include <stack>
#include <unordered_map>
#include "CommonDefinitions.h"
#include "CFOwningRef.h"
#include "Todo.h"

#import "CXILApplication.h"
#import "CXILWindowDelegate.h"

#define IPC_PARAM(name, type)	type name; do { if (!channel->Read(name)) [self terminate:self]; } while (false)

using namespace Common;
using namespace InterfaceLib;

NSString* NSMenuWillSendActionNotification = @"NSMenuWillSendActionNotification";
NSString* NSMenuDidCompleteInteractionNotification = @"NSMenuDidCompleteInteractionNotification";
NSString* NSMenuWillSendActionNotification_MenuItem = @"MenuItem";

#pragma mark -
#pragma mark C++ Utilities
namespace
{
	inline BOOL CXILIsFDValid(int fd)
	{
		return fcntl(fd, F_GETFL) != -1 || errno != EBADF;
	}
	
	NSTimeInterval CXILTimeStamp()
	{
		mach_timebase_info_data_t info;
		mach_timebase_info(&info);
		uint64_t absTime = mach_absolute_time();
		absTime *= info.numer;
		absTime /= info.denom;
		return absTime / 1000000000.;
	}
	
	uint32_t CXILClassicTimeStamp()
	{
		return static_cast<uint32_t>(CXILTimeStamp() / 60);
	}
	
	uint16_t CXILEventRecordModifierFlags(NSUInteger modifierFlags)
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
		
		TODO("CXILModifierFlags does not handle active state or right shift, command and control keys");
		return modifiers;
	}
	
	void PerformSelectorUnsafe(id object, SEL selector)
	{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[object performSelector:selector];
#pragma clang diagnostic pop
	}
	
	void PerformSelectorUnsafe(id object, SEL selector, id argument)
	{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[object performSelector:selector withObject:argument];
#pragma clang diagnostic pop
	}
	
	struct CGRect32
	{
		float x, y;
		float width, height;
		
		operator CGRect()
		{
			return CGRectMake(x, y, width, height);
		}
	};
	
	bool ReadExact(int fd, void* into, size_t size)
	{
		size_t dataRead = 0;
		while (dataRead < size)
		{
			ssize_t count = ::read(fd, into, size - dataRead);
			if (count < 1)
				return false;
			dataRead += count;
		}
		return true;
	}
	
	class BackendChannel
	{
		int read, write;
		
	public:
		BackendChannel(int read, int write) : read(read), write(write) {}
		
		template<typename T>
		bool Read(T& into)
		{
			return ReadExact(read, &into, sizeof into);
		}
		
		template<typename T>
		bool Write(const T& from)
		{
			::write(write, &from, sizeof from);
			return true;
		}
	};
	
	template<>
	bool BackendChannel::Read(MacRegionMax& region)
	{
		if (!Read(region.rgnSize))
			return false;
		
		if (!Read(region.rgnBBox))
			return false;
		
		size_t rest = region.rgnSize - 10;
		if (!ReadExact(read, &region.rgnData, rest))
			return false;
		
		memset(&region.rgnData[rest], 0, sizeof region.rgnData - rest);
		return true;
	}
	
	template<>
	bool BackendChannel::Read(std::string& into)
	{
		uint32_t length;
		if (!Read(length))
			return false;
		
		std::unique_ptr<char> buffer(new char[length]);
		if (!ReadExact(read, buffer.get(), length))
			return false;
		
		into = std::string(buffer.get(), length);
		return true;
	}
}

#pragma mark -
#pragma mark Objective-C
@implementation CXILApplication
{
	BackendChannel* channel;
	dispatch_source_t ipcSource;
	
	std::unordered_multimap<uint32_t, CGRect> dirtyRects;
	std::list<EventRecord> eventQueue;
	EventMask currentlyWaitingOn;
	NSTimer* waitLimit;
	
	NSRect screenBounds;
	NSWindow* menuGate;
	NSMenu* baseMenu;
	CXILWindowDelegate* windowDelegate;
	
	NSMutableArray* eventHandlers;
	
	NSRect dragBounds;
	NSPoint cornerCursorDistance;
	NSWindow* draggedWindow;
	
	BOOL isCursorVisible;
}

#define IPC_INDEX(x) [(size_t)IPCMessage::x]

static SEL ipcSelectors[] = {
	IPC_INDEX(Beep) = @selector(beep),
	IPC_INDEX(SetCursorVisibility) = @selector(setCursorVisibility),
	IPC_INDEX(PeekNextEvent) = @selector(peekNextEvent),
	IPC_INDEX(DequeueNextEvent) = @selector(discardNextEvent),
	IPC_INDEX(DiscardEventsUntil) = @selector(discardEventsUntil),
	IPC_INDEX(IsMouseDown) = @selector(tellIsMouseDown),
	IPC_INDEX(CreateWindow) = @selector(createWindow),
	IPC_INDEX(CreateDialog) = @selector(createDialog),
	IPC_INDEX(CreateControl) = @selector(createControl),
	IPC_INDEX(CloseWindow) = @selector(closeWindow),
	IPC_INDEX(RequestUpdate) = @selector(requestUpdate),
	IPC_INDEX(DragWindow) = @selector(dragWindow),
	IPC_INDEX(FindFrontWindow) = @selector(findFrontWindow),
	IPC_INDEX(FindWindowByCoordinates) = @selector(findWindow),
	IPC_INDEX(SetDirtyRect) = @selector(setDirtyRect),
	IPC_INDEX(RefreshWindows) = @selector(refreshWindows),
	IPC_INDEX(ClearMenus) = @selector(clearMenus),
	IPC_INDEX(InsertMenu) = @selector(insertMenu),
	IPC_INDEX(InsertMenuItem) = @selector(insertMenuItem),
	IPC_INDEX(CheckItem) = @selector(checkMenuItem),
	IPC_INDEX(MenuSelect) = @selector(menuSelect),
	IPC_INDEX(MenuKey) = @selector(menuKey),
};

const size_t ipcSelectorCount = sizeof ipcSelectors / sizeof(SEL);

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
	
	int readHandle = [arguments[1] intValue];
	int writeHandle = [arguments[2] intValue];
	
	if (readHandle == 0 || writeHandle == 0 || !CXILIsFDValid(readHandle) || !CXILIsFDValid(writeHandle))
	{
		NSLog(@"InterfaceLibHead is not meant to be run directly. Please let InterfaceLib launch it.");
		NSLog(@"Either the read or write pipe is invalid.");
		return nil;
	}
	
	ipcSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, readHandle, 0, dispatch_get_main_queue());
	dispatch_source_set_event_handler(ipcSource, ^{ [self processIPCMessage]; });
	dispatch_resume(ipcSource);
	
	channel = new BackendChannel(readHandle, writeHandle);
	
	screenBounds = NSScreen.mainScreen.frame;
	
	NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
	[center addObserver:self selector:@selector(receiveNotification:) name:nil object:nil];
	
	CGFloat menubarThickness = NSStatusBar.systemStatusBar.thickness;
	NSRect menuGateRect = NSMakeRect(0, screenBounds.size.height - menubarThickness, screenBounds.size.width, menubarThickness);
	menuGate = [[NSPanel alloc] initWithContentRect:menuGateRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	menuGate.level = NSStatusWindowLevel;
	menuGate.oneShot = YES;
	menuGate.canHide = NO;
	menuGate.ignoresMouseEvents = NO;
	menuGate.alphaValue = 0;
	
	windowDelegate = [[CXILWindowDelegate alloc] initWithMenuGate:menuGate];
	
	// reference cycle, but that's not really a problem because NSApplication is global and everlasting anyways
	eventHandlers = [NSMutableArray arrayWithObject:self];
	
	isCursorVisible = YES;
	
	return self;
}

-(void)finishLaunching
{
	[super finishLaunching];
	baseMenu = [self.mainMenu copy];
	[menuGate makeKeyAndOrderFront:self];
}

-(void)sendEvent:(NSEvent *)theEvent
{
	NSUInteger index = eventHandlers.count;
	CXILEventHandlerActionResult handlingResult = kCXILEventHandlerNormalResolution;
	do
	{
		index--;
		id<CXILEventHandler> handler = eventHandlers[index];
		handlingResult = [handler handleEvent:theEvent];
		if (handlingResult & kCXILEventHandlerRemoveHandler)
			[eventHandlers removeObjectAtIndex:index];
	}
	while ((handlingResult & kCXILEventHandlerDidNotHandleEvent) && index > 0);
	
	NSAssert(!(handlingResult & kCXILEventHandlerDidNotHandleEvent), @"Event %@ was not handled", theEvent);
}

-(void)receiveNotification:(NSNotification *)notification
{
	NSUInteger index = eventHandlers.count;
	CXILEventHandlerActionResult handlingResult = kCXILEventHandlerNormalResolution;
	do
	{
		index--;
		id<CXILEventHandler> handler = eventHandlers[index];
		handlingResult = [handler handleNotification:notification];
		if (handlingResult & kCXILEventHandlerRemoveHandler)
			[eventHandlers removeObjectAtIndex:index];
	}
	while ((handlingResult & kCXILEventHandlerDidNotHandleEvent) && index > 0);
	
	NSAssert(!(handlingResult & kCXILEventHandlerDidNotHandleEvent), @"Notification %@ was not handled", notification);
}

-(void)orderFrontStandardAboutPanel:(id)sender
{
	// not implemented
}

-(void)dealloc
{
	if (ipcSource != nullptr)
		dispatch_suspend(ipcSource);
}

#pragma mark -
#pragma mark Event Handling
-(void)ignore:(id)object {}

-(CXILEventHandlerActionResult)handleEvent:(NSEvent *)theEvent
{
	NSPoint globalCoordinates = [NSEvent mouseLocation];
	EventRecord eventRecord = {
		.when = Common::UInt32(static_cast<uint32_t>(theEvent.timestamp * 60)), // Mac OS Classic considers there are 60 ticks per second
		.where = [self xPointToClassicPoint:globalCoordinates],
	};
	
	uint16_t mouseButtonState = ([NSEvent pressedMouseButtons] & 1) == 1
		? static_cast<uint16_t>(EventModifierFlags::mouseButtonState)
		: 0;
	
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
			return kCXILEventHandlerNormalResolution;
			
			TODO("handleEvent: does not trigger updateEvent, diskEvent, activateEvent, osEvent or highLevelEvent");
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
	
	return kCXILEventHandlerNormalResolution;
}

-(CXILEventHandlerActionResult)handleNotification:(NSNotification *)notification
{
	uint16_t mouseButtonState = ([NSEvent pressedMouseButtons] & 1) == 1
		? static_cast<uint16_t>(EventModifierFlags::mouseButtonState)
		: 0;
	
	if ([notification.name isEqualToString:NSWindowDidBecomeKeyNotification] ||
		[notification.name isEqualToString:NSWindowDidResignKeyNotification])
	{
		uint16_t modifiers = mouseButtonState | CXILEventRecordModifierFlags([NSEvent modifierFlags]);
		if ([notification.name isEqualToString:NSWindowDidBecomeKeyNotification])
			modifiers |= static_cast<uint16_t>(EventModifierFlags::activeFlag);
		
		EventRecord focusRecord = {
			.what = Common::UInt16(static_cast<uint16_t>(EventCode::activateEvent)),
			.when = Common::UInt32(CXILClassicTimeStamp()),
			.where = [self xPointToClassicPoint:[NSEvent mouseLocation]],
			.modifiers = Common::UInt16(modifiers),
			.message = Common::UInt32([windowDelegate keyOfWindow:notification.object])
		};
		
		eventQueue.push_back(focusRecord);
		[self suggestEventRecord:focusRecord];
	}
	else if ([notification.name isEqualToString:NSMenuDidCompleteInteractionNotification])
	{
		[self pickMenuItem:nil];
	}
	return kCXILEventHandlerNormalResolution;
}

-(void)registerRemovalAction:(CXILEventHandlerRemovedAction)action
{
	[NSException raise:@"NotImplementedException" format:@"CXILApplication doesn't support removal actions"];
}

#pragma mark -
#pragma mark RPCs

-(void)sendDone:(SEL)cmd
{
	char done[] = {'D', 'O', 'N', 'E'};
	channel->Write(done);
}

-(void)expectDone
{
	char done[4];
	if (!channel->Read(done))
		[self terminate:self];
	
	if (memcmp(done, "DONE", sizeof done) != 0)
	{
		NSLog(@"*** Expected a DONE, got %.4s", done);
		abort();
	}
}

-(void)processIPCMessage
{
	unsigned messageType;
	if (!channel->Read(messageType))
		[self terminate:self];
	
	NSAssert(messageType < ipcSelectorCount, @"Message type %u is undefined", messageType);
	SEL selector = ipcSelectors[messageType];
	NSAssert(selector != nullptr, @"Message type %u has no implementation", messageType);
	
	// There's a presumed bug with Clang++ ( http://llvm.org/bugs/show_bug.cgi?id=15922 ) where selectors
	// obtained from a C++ global initializer can apparently become invalid in Release config. Normally, there's just
	// one selector for one method name, but it seems that some selectors aren't unified correclty
	if (![self respondsToSelector:selector])
	{
		selector = sel_getUid(sel_getName(selector));
	}
	
	// this operation is safe, because the selector accepts no argument and returns no object
	// since no leak is possible, we shut up the compiler
	PerformSelectorUnsafe(self, selector);
}

-(void)peekNextEvent
{
	IPC_PARAM(desiredEvent, uint16_t);
	IPC_PARAM(ticksTimeout, uint32_t);
	IPC_PARAM(mouseMoveRegion, MacRegionMax);
	[self expectDone];
	
	TODO("Mouse move events aren't tracked in mouseMoveRegion");
	
	currentlyWaitingOn = static_cast<EventMask>(desiredEvent);
	
	// if we have one such event, send it to the client
	for (const EventRecord& event : eventQueue)
	{
		if ([self suggestEventRecord:event])
		{
			return;
		}
	}
	
	// With a 0 timeout, return immediately
	if (ticksTimeout == 0)
	{
		// enqueue an update event for the new window
		uint16_t mouseButtonState = ([NSEvent pressedMouseButtons] & 1) == 1
			? static_cast<uint16_t>(EventModifierFlags::mouseButtonState)
			: 0;
		uint16_t modifiers = mouseButtonState | CXILEventRecordModifierFlags([NSEvent modifierFlags]);
		
		// no event found, return an empty event
		EventRecord record = {
			.what = Common::UInt16(static_cast<uint16_t>(EventCode::nullEvent)),
			.when = Common::UInt32(CXILClassicTimeStamp()),
			.where = [self xPointToClassicPoint:[NSEvent mouseLocation]],
			.modifiers = Common::UInt16(modifiers),
			.message = Common::UInt32(0),
		};
		
		channel->Write(record);
		[self sendDone:_cmd];
		
		currentlyWaitingOn = EventMask::noEvent;
	}
	else
	{
		// otherwise, wait for one such event
		NSTimeInterval timeout = ticksTimeout / 60.;
		waitLimit = [NSTimer scheduledTimerWithTimeInterval:timeout target:self selector:@selector(stopWaitingOnEvent) userInfo:nil repeats:NO];
	}
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
	
	[self sendDone:_cmd];
}

-(void)discardEventsUntil
{
	IPC_PARAM(discardMask, uint16_t);
	IPC_PARAM(stopMask, uint16_t);
	[self expectDone];

	auto iter = eventQueue.begin();
	while (iter != eventQueue.end())
	{
		if (((1 << iter->what) & stopMask) != 0)
		{
			break;
		}
		else if (((1 << iter->what) & discardMask) != 0)
		{
			iter = eventQueue.erase(iter);
		}
		else
		{
			iter++;
		}
	}
	
	[self sendDone:_cmd];
}

-(void)tellIsMouseDown
{
	[self expectDone];
	// This is probably paranoid, but I'd rather use bool than BOOL here because this has to be C++-compatible.
	bool isMouseDown = [NSEvent pressedMouseButtons] & 1;
	channel->Write(isMouseDown);
	[self sendDone:_cmd];
}

-(void)beep
{
	[self expectDone];
	NSBeep();
	[self sendDone:_cmd];
}

-(void)setCursorVisibility
{
	IPC_PARAM(visible, bool);
	[self expectDone];
	
	if (visible)
	{
		if (!isCursorVisible)
		{
			[NSCursor unhide];
			isCursorVisible = YES;
		}
	}
	else
	{
		if (isCursorVisible)
		{
			[NSCursor hide];
			isCursorVisible = NO;
		}
	}
	
	[self sendDone:_cmd];
}

-(void)createWindow
{
	IPC_PARAM(key, uint32_t);
	IPC_PARAM(surfaceId, IOSurfaceID);
	IPC_PARAM(windowRect, InterfaceLib::Rect);
	IPC_PARAM(visible, BOOL);
	IPC_PARAM(title, std::string);
	IPC_PARAM(createBehind, uint32_t);
	[self expectDone];
	
	NSString* nsTitle = [NSString stringWithCString:title.c_str() encoding:NSMacOSRomanStringEncoding];
	NSRect frame = [self classicRectToXRect:windowRect];
	
	IOSurfaceRef surface = IOSurfaceLookup(surfaceId);
	[windowDelegate createWindow:key withRect:frame surface:surface title:nsTitle visible:visible behind:createBehind];
	IOSurfaceDecrementUseCount(surface);
	
	[self enqueueUpdateEvent:key];
	
	[self sendDone:_cmd];
}

-(void)createDialog
{
	IPC_PARAM(key, uint32_t);
	IPC_PARAM(windowRect, InterfaceLib::Rect);
	IPC_PARAM(visible, bool);
	IPC_PARAM(title, std::string);
	[self expectDone];
	
	NSString* nsTitle = [NSString stringWithCString:title.c_str() encoding:NSMacOSRomanStringEncoding];
	NSRect frame = [self classicRectToXRect:windowRect];
	
	[windowDelegate createDialog:key withRect:frame title:nsTitle visible:visible];
	
	[self sendDone:_cmd];
}

-(void)createControl
{
	IPC_PARAM(key, uint32_t);
	IPC_PARAM(type, InterfaceLib::Control::Type);
	IPC_PARAM(enabled, bool);
	IPC_PARAM(bounds, InterfaceLib::Rect);
	IPC_PARAM(label, std::string);
	[self expectDone];
	
	NSWindow* window = [windowDelegate windowForKey:key];
	
	NSString* nsLabel = [NSString stringWithCString:label.c_str() encoding:NSMacOSRomanStringEncoding];
	NSRect windowBounds = [window.contentView bounds];
	NSRect frame = [self classicRectToXRect:bounds reference:windowBounds];

	id control;
	switch (type)
	{
		case Control::Button:
			control = [[NSButton alloc] initWithFrame:frame];
			[control setTitle:nsLabel];
			break;
			
		case Control::CheckBox:
			control = [[NSButton alloc] initWithFrame:frame];
			[control setButtonType:NSSwitchButton];
			[control setTitle:nsLabel];
			break;
			
		case Control::RadioButton:
			control = [[NSButton alloc] initWithFrame:frame];
			[control setButtonType:NSRadioButton];
			[control setTitle:nsLabel];
			break;
			
		case Control::EditText:
			control = [[NSTextField alloc] initWithFrame:frame];
			[control setBezeled:YES];
			[control setDrawsBackground:YES];
			[control setEditable:YES];
			[control setSelectable:YES];
			[control setStringValue:nsLabel];
			break;
			
		case Control::StaticText:
			control = [[NSTextField alloc] initWithFrame:frame];
			[control setBezeled:NO];
			[control setDrawsBackground:NO];
			[control setEditable:NO];
			[control setSelectable:YES];
			[control setStringValue:nsLabel];
			break;
			
		default:
			assert(false && "Not implemented");
	}
	
	[window.contentView addSubview:control];
	
	[self sendDone:_cmd];
}

-(void)requestUpdate
{
	IPC_PARAM(key, uint32_t);
	[self expectDone];
	[self enqueueUpdateEvent:key];
	[self sendDone:_cmd];
}

-(void)findFrontWindow
{
	[self expectDone];
	
	uint32_t key = [windowDelegate keyOfFrontWindow];
	channel->Write(key);
	[self sendDone:_cmd];
}

-(void)findWindow
{
	IPC_PARAM(point, InterfaceLib::Point);
	[self expectDone];
	
	InterfaceLib::WindowPartCode code;
	NSPoint nsPoint = [self classicPointToXPoint:point];
	uint32_t key = [windowDelegate findWindowUnderPoint:nsPoint area:reinterpret_cast<int16_t*>(&code)];
	
	channel->Write(code);
	channel->Write(key);
	[self sendDone:_cmd];
}

-(void)setDirtyRect
{
	IPC_PARAM(key, uint32_t);
	IPC_PARAM(dirtyRect, CGRect32);
	[self expectDone];
	
	dirtyRects.insert(std::make_pair(key, dirtyRect));
	
	[self sendDone:_cmd];
}

-(void)refreshWindows
{
	[self expectDone];
	
	for (const auto& pair : dirtyRects)
		[windowDelegate setDirtyRect:pair.second inWindow:pair.first];
	
	dirtyRects.clear();
	
	[self sendDone:_cmd];
}

-(void)closeWindow
{
	IPC_PARAM(key, uint32_t);
	[self expectDone];
	
	[windowDelegate destroyWindow:key];
	[self sendDone:_cmd];
}

-(void)dragWindow
{
	IPC_PARAM(windowKey, uint32_t);
	IPC_PARAM(classicDragBounds, InterfaceLib::Rect);
	[self expectDone];
	
	dragBounds = [self classicRectToXRect:classicDragBounds];
	
	id handler = [windowDelegate startDragWindow:windowKey mouseLocation:NSEvent.mouseLocation dragBounds:dragBounds];
	[handler registerRemovalAction:^(id) { [self sendDone:_cmd]; }];
	
	[eventHandlers addObject:handler];
}

-(void)clearMenus
{
	[self expectDone];
	self.mainMenu = [baseMenu copy];
	[self sendDone:_cmd];
}

-(void)insertMenu
{
	IPC_PARAM(menuId, uint16_t);
	IPC_PARAM(title, std::string);
	[self expectDone];
	
	if (title == "\x14") // '' in Mac OS Roman
	{
		NSMenuItem* classixMenu = [self.mainMenu itemAtIndex:0];
		classixMenu.tag = menuId;
	}
	else
	{
		NSString* nsTitle = [[NSString alloc] initWithCString:title.c_str() encoding:NSMacOSRomanStringEncoding];
		NSMenu* menu = [[NSMenu alloc] initWithTitle:nsTitle];
		menu.autoenablesItems = NO;
		
		NSMenuItem* wrappingItem = [[NSMenuItem alloc] initWithTitle:nsTitle action:nullptr keyEquivalent:@""];
		wrappingItem.submenu = menu;
		wrappingItem.tag = menuId;
		[self.mainMenu addItem:wrappingItem];
	}
	
	[self sendDone:_cmd];
}

-(void)insertMenuItem
{
	IPC_PARAM(menuId, uint16_t);
	IPC_PARAM(title, std::string);
	IPC_PARAM(keyEquivalent, char);
	IPC_PARAM(enabled, bool);
	[self expectDone];
	
	NSMenuItem* item;
	if (title == "-")
	{
		item = [NSMenuItem separatorItem];
	}
	else
	{
		char keyEquivalentString[2] = {keyEquivalent, 0};
		NSString* nsKeyEquivalent = [NSString stringWithCString:keyEquivalentString encoding:NSMacOSRomanStringEncoding];
		NSString* nsTitle = [NSString stringWithCString:title.c_str() encoding:NSMacOSRomanStringEncoding];
		item = [[NSMenuItem alloc] initWithTitle:nsTitle action:@selector(pickMenuItem:) keyEquivalent:nsKeyEquivalent.lowercaseString];
	}
	
	NSMenuItem* parentItem = [self.mainMenu itemWithTag:menuId];
	NSMenu* parent = parentItem.submenu;
	if ([self.mainMenu indexOfItem:parentItem] == 0)
	{
		// if it's the Apple menu, insert before the first element of the application menu instead of at the end of
		// the menu
		NSMenuItem* insertBefore = [parent itemWithTag:-1];
		NSUInteger index = [parent indexOfItem:insertBefore];
		[parent insertItem:item atIndex:index];
	}
	else
	{
		[parent addItem:item];
	}
	
	[self sendDone:_cmd];
}

-(void)checkMenuItem
{
	IPC_PARAM(menuIndex, uint16_t);
	IPC_PARAM(itemIndex, uint16_t);
	IPC_PARAM(checked, bool);
	[self expectDone];
	
	NSMenu* menu = [self.mainMenu itemWithTag:menuIndex].submenu;
	NSMenuItem* item = [menu itemAtIndex:itemIndex];
	item.state = checked ? NSOnState : NSOffState;
	[self sendDone:_cmd];
}

-(void)menuSelect
{
	IPC_PARAM(point, InterfaceLib::Point);
	[self expectDone];
	
	menuGate.ignoresMouseEvents = YES;
	// CGEvents are strange and (0,0) is the top left corner
	NSPoint nsPoint = NSMakePoint(point.h, point.v);
	
	CFOwningRef<CGEventRef> clickEvent = CGEventCreateMouseEvent(nullptr, kCGEventLeftMouseDown, nsPoint, kCGMouseButtonLeft);
	CGEventPost(kCGHIDEventTap, clickEvent);
	
	// don't reply yet: wait until menu interaction finishes
}

-(void)menuKey
{
	IPC_PARAM(charCode, char);
	[self expectDone];
	
	char charString[] = {charCode, 0};
	
	NSPoint location = NSEvent.mouseLocation;
	NSTimeInterval now = CXILTimeStamp();
	NSInteger frontWindow = [self mainWindow].windowNumber;
	NSString* characters = [NSString stringWithCString:charString encoding:NSMacOSRomanStringEncoding];
	unsigned short keyCode = 0;
	
	TODO("menuKey would need the keyCode behind the char");
	
	menuGate.ignoresMouseEvents = YES;
	
	// ouch
	NSEvent* keyEvent = [NSEvent keyEventWithType:NSKeyDown location:location modifierFlags:NSCommandKeyMask timestamp:now windowNumber:frontWindow context:nullptr characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:keyCode];
	[self.mainMenu performKeyEquivalent:keyEvent];
	
	[self sendDone:_cmd];
}

#pragma mark -
#pragma mark Gory details

-(BOOL)suggestEventRecord:(const EventRecord &)record
{
	int eventCodeMask = 1 << record.what;
	if ((eventCodeMask & static_cast<int>(currentlyWaitingOn)) != 0)
	{
		channel->Write(record);
		[self sendDone:_cmd];
		
		currentlyWaitingOn = EventMask::noEvent;
		[waitLimit invalidate];
		waitLimit = nil;
		return YES;
	}
	return NO;
}

-(NSRect)classicRectToXRect:(InterfaceLib::Rect)rect reference:(NSRect)referenceRect
{
	CGFloat x = referenceRect.origin.x + rect.left;
	CGFloat y = referenceRect.origin.y + referenceRect.size.height - rect.bottom;
	CGFloat width = rect.right - rect.left;
	CGFloat height = rect.bottom - rect.top;
	return NSMakeRect(x, y, width, height);
}

-(NSRect)classicRectToXRect:(InterfaceLib::Rect)rect
{
	return [self classicRectToXRect:rect reference:screenBounds];
}

-(NSPoint)classicPointToXPoint:(InterfaceLib::Point)point
{
	CGFloat x = point.h;
	CGFloat y = screenBounds.size.height - point.v;
	return NSMakePoint(x, y);
}

-(InterfaceLib::Point)xPointToClassicPoint:(NSPoint)pt
{
	InterfaceLib::Point outPoint;
	outPoint.h = static_cast<int16_t>(pt.x);
	outPoint.v = static_cast<int16_t>(screenBounds.size.height - pt.y);
	return outPoint;
}

-(void)stopWaitingOnEvent
{
	currentlyWaitingOn = EventMask::noEvent;
	waitLimit = nil;
	
	EventRecord noEvent;
	memset(&noEvent, 0, sizeof noEvent);
	channel->Write(noEvent);
	[self sendDone:_cmd];
}

-(void)pickMenuItem:(NSMenuItem*)sender
{
	if (menuGate.ignoresMouseEvents)
	{
		NSMenuItem* parent = sender.parentItem;
		uint16_t menuIndex = static_cast<uint16_t>(parent.tag);
		uint16_t itemIndex = static_cast<uint16_t>([parent.submenu indexOfItem:sender]);
		channel->Write(menuIndex);
		channel->Write(itemIndex);
		[self sendDone:_cmd];
	
		menuGate.ignoresMouseEvents = NO;
	}
}

-(void)enqueueUpdateEvent:(uint32_t)windowKey
{
	// enqueue an update event for the new window
	uint16_t mouseButtonState = ([NSEvent pressedMouseButtons] & 1) == 1
		? static_cast<uint16_t>(EventModifierFlags::mouseButtonState)
		: 0;
	uint16_t modifiers = mouseButtonState | CXILEventRecordModifierFlags([NSEvent modifierFlags]);
	
	EventRecord record = {
		.what = Common::UInt16(static_cast<uint16_t>(EventCode::updateEvent)),
		.when = Common::UInt32(CXILClassicTimeStamp()),
		.where = [self xPointToClassicPoint:[NSEvent mouseLocation]],
		.modifiers = Common::UInt16(modifiers),
		.message = Common::UInt32(windowKey)
	};
	eventQueue.push_back(record);
}

@end
