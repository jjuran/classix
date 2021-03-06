//
// CXVirtualMachine.mm
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

#import "CXVirtualMachine.h"
#import "CXRegister.h"

#include <dlfcn.h>
#include <unordered_set>
#include <algorithm>

#include "MachineState.h"
#include "FragmentManager.h"
#include "NativeAllocator.h"
#include "Interpreter.h"
#include "Managers.h"

#include "FancyDisassembler.h"
#include "CXObjcDisassemblyWriter.h"
#include "NativeCall.h"
#include "CXReverseAllocationDetails.h"
#include "InstructionDecoder.h"
#include "StackPreparator.h"

#include "PEFLibraryResolver.h"
#include "DummyLibraryResolver.h"
#include "BundleLibraryResolver.h"
#include "DlfcnLibraryResolver.h"

NSNumber* CXVirtualMachineGPRKey = @(CXRegisterGPR);
NSNumber* CXVirtualMachineFPRKey = @(CXRegisterFPR);
NSNumber* CXVirtualMachineSPRKey = @(CXRegisterSPR);
NSNumber* CXVirtualMachineCRKey = @(CXRegisterCR);

NSString* CXErrorDomain = @"Classix Error Domain";
NSString* CXErrorFilePath = @"File URL";

NSString* CXVirtualMachineBreakpointChangeTypeKey = @"breakpointChange";
NSString* CXVirtualMachineBreakpointAddressKey = @"breakpointAddress";
NSString* CXVirtualMachineAddedBreakpoint = @"added breakpoint";
NSString* CXVirtualMachineRemovedBreakpoint = @"removed breakpoint";

struct ClassixCoreVM
{
	Common::NativeAllocator allocator;
	OSEnvironment::NativeThreadManager threads;
	OSEnvironment::Managers managers;
	PPCVM::MachineState state;
	CFM::FragmentManager cfm;
	CFM::PEFLibraryResolver pefResolver;
	CFM::DummyLibraryResolver dummyResolver;
	ClassixCore::DlfcnLibraryResolver dlfcnResolver;
	ClassixCore::BundleLibraryResolver bundleResolver;
	PPCVM::Execution::Interpreter interp;
	Common::AutoAllocation stack;
	
	ClassixCoreVM()
	: managers(allocator, threads)
	, dummyResolver(allocator)
	, pefResolver(allocator, cfm)
	, dlfcnResolver(allocator, managers)
	, interp(allocator, state)
	, bundleResolver(allocator, managers)
	, stack(allocator.AllocateAuto(CXReverseAllocationDetails("Stack", Common::StackPreparator::DefaultStackSize), Common::StackPreparator::DefaultStackSize))
	{
		dlfcnResolver.RegisterLibrary("StdCLib");
		dlfcnResolver.RegisterLibrary("MathLib");
		dlfcnResolver.RegisterLibrary("ThreadsLib");
		bundleResolver.AllowLibrary("InterfaceLib");
		cfm.LibraryResolvers.push_back(&pefResolver);
		cfm.LibraryResolvers.push_back(&bundleResolver);
		cfm.LibraryResolvers.push_back(&dlfcnResolver);
		cfm.LibraryResolvers.push_back(&dummyResolver);
	}
	
	bool LoadContainer(const std::string& path)
	{
		using namespace PEF;
		
		if (cfm.LoadContainer(path))
		{
			CFM::SymbolResolver* resolver = cfm.GetSymbolResolver(path);
			std::vector<CFM::ResolvedSymbol> entryPoints = resolver->GetEntryPoints();
			for (const CFM::ResolvedSymbol& symbol : entryPoints)
			{
				if (symbol.Universe == CFM::SymbolUniverse::PowerPC)
					return true;
			}
		}
		return false;
	}
	
	bool IsCodeAddress(uint32_t address)
	{
		for (auto iter = cfm.begin(); iter != cfm.end(); iter++)
		{
			if (const CFM::PEFSymbolResolver* resolver = dynamic_cast<const CFM::PEFSymbolResolver*>(iter->second))
			{
				const PEF::Container& container = resolver->GetContainer();
				for (const PEF::InstantiableSection& section : container)
				{
					if (section.IsExecutable())
					{
						uint32_t sectionBase = allocator.ToIntPtr(section.Data);
						uint32_t sectionEnd = sectionBase + section.Size();
						if (address >= sectionBase && address < sectionEnd)
							return true;
					}
				}
			}
		}
		return false;
	}
	
	void PrepareState(const Common::StackPreparator::StackInfo& info)
	{
		state.r0 = 0;
		state.r1 = allocator.ToIntPtr(info.sp - 8);
		state.r3 = state.r27 = info.argc;
		state.r4 = state.r28 = allocator.ToIntPtr(info.argv);
		state.r5 = state.r29 = allocator.ToIntPtr(info.envp);
	}
};

@interface CXVirtualMachine (Private)

-(void)refreshRegisters:(const PPCVM::MachineState*)oldState;

@end

@implementation CXVirtualMachine

@synthesize allRegisters = registers;
@synthesize pc;
@synthesize lastError;
@synthesize breakpointsChanged;
@synthesize breakpoints;

-(void)setLastError:(NSString *)aLastError
{
	NSString* copy = [aLastError copy];
	[self willChangeValueForKey:@"lastError"];
	[lastError release];
	lastError = copy;
	[self didChangeValueForKey:@"lastError"];
}

-(NSArray*)gpr
{
	return [registers objectForKey:CXVirtualMachineGPRKey];
}

-(NSArray*)fpr
{
	return [registers objectForKey:CXVirtualMachineFPRKey];
}

-(NSArray*)spr
{
	return [registers objectForKey:CXVirtualMachineSPRKey];
}

-(NSArray*)cr
{
	return [registers objectForKey:CXVirtualMachineCRKey];
}

-(id)init
{
	if (!(self = [super init]))
		return nil;
	
	breakpoints = [[NSMutableSet alloc] init];
	changedRegisters = [[NSMutableSet alloc] initWithCapacity:75];
	breakpointsChanged = [[CXEvent alloc] initWithOwner:self];
	
	return self;
}

-(BOOL)loadClassicExecutable:(NSString *)executablePath error:(NSError **)error
{
	delete vm;
	vm = new ClassixCoreVM;
	NSMutableArray* gpr = [NSMutableArray arrayWithCapacity:32];
	NSMutableArray* fpr = [NSMutableArray arrayWithCapacity:32];
	NSMutableArray* cr = [NSMutableArray arrayWithCapacity:8];
	NSMutableArray* spr = [NSMutableArray array];
	
	for (int i = 0; i < 32; i++)
	{
		CXRegister* r = [CXRegister GPRNumber:i location:&vm->state.gpr[i]];
		CXRegister* fr = [CXRegister FPRNumber:i location:&vm->state.fpr[i]];
		[gpr addObject:r];
		[fpr addObject:fr];
	}
	
	for (int i = 0; i < 8; i++)
	{
		CXRegister* reg = [CXRegister CRNumber:i location:&vm->state.cr[i]];
		[cr addObject:reg];
	}
	
	[spr addObject:[CXRegister SPRName:@"xer" location:&vm->state.xer]];
	[spr addObject:[CXRegister SPRName:@"lr" location:&vm->state.lr]];
	[spr addObject:[CXRegister SPRName:@"ctr" location:&vm->state.ctr]];
	
	registers = [@{
		CXVirtualMachineGPRKey: gpr,
		CXVirtualMachineFPRKey: fpr,
		CXVirtualMachineSPRKey: spr,
		CXVirtualMachineCRKey: cr
	} retain];
	
	std::string path = [executablePath UTF8String];
	
	if (!vm->LoadContainer(path))
	{
		if (error != nullptr)
			*error = [NSError errorWithDomain:CXErrorDomain code:CXErrorCodeFileNotLoadable userInfo:@{CXErrorFilePath: executablePath}];
		return NO;
	}
	
	return YES;
}

-(void)setArgv:(NSArray *)args envp:(NSDictionary *)env
{
	Common::StackPreparator stackPrep;
	for (NSString* string in args)
		stackPrep.AddArgument(string.UTF8String);
	
	for (NSString* key in env)
	{
		NSString* value = [env objectForKey:key];
		stackPrep.AddEnvironmentVariable(key.UTF8String, value.UTF8String);
	}
	
	Common::AutoAllocation& stack = vm->stack;
	auto result = stackPrep.WriteStack(static_cast<char*>(*stack), stack.GetVirtualAddress(), Common::StackPreparator::DefaultStackSize);
	
	for (auto& pair : vm->cfm)
	{
		CFM::SymbolResolver* resolver = pair.second;
		auto entryPoints = resolver->GetEntryPoints();
		for (auto& entryPoint : entryPoints)
		{
			if (entryPoint.Name == CFM::SymbolResolver::InitSymbolName)
			{
				PEF::TransitionVector* vector = reinterpret_cast<PEF::TransitionVector*>(entryPoint.Address);
				vm->PrepareState(result);
				vm->state.r2 = vector->TableOfContents;
				
				auto marker = vm->managers.ThreadManager().CreateExecutionMarker();
				vm->state.lr = vm->allocator.ToIntPtr(vm->interp.GetEndAddress());
				vm->interp.Execute(vm->allocator.ToPointer<Common::UInt32>(vector->EntryPoint));
			}
		}
	}
	
	vm->PrepareState(result);
	
	NSArray* gpr = self.gpr;
	NSArray* initialRegisters = @[
		[gpr objectAtIndex:0],
		[gpr objectAtIndex:1],
		[gpr objectAtIndex:3],
		[gpr objectAtIndex:4],
		[gpr objectAtIndex:5],
	];
	
	[changedRegisters removeAllObjects];
	[changedRegisters addObjectsFromArray:initialRegisters];
}

-(void)transitionByAddress:(uint32_t)address
{
	const PEF::TransitionVector* transition = vm->allocator.ToPointer<PEF::TransitionVector>(address);
	vm->state.r2 = transition->TableOfContents;
	pc = transition->EntryPoint;
}

-(NSValue*)fragmentManager
{
	CFM::FragmentManager* cfm = &vm->cfm;
	return [NSValue value:&cfm withObjCType:@encode(typeof cfm)];
}

-(NSValue*)allocator
{
	Common::Allocator* allocator = &vm->allocator;
	return [NSValue value:&allocator withObjCType:@encode(typeof allocator)];
}

-(NSString*)symbolNameOfAddress:(unsigned int)address
{
	using namespace PPCVM::Execution;
	Common::Allocator& allocator = vm->allocator;
	try
	{
		const NativeCall* pointer = allocator.ToPointer<NativeCall>(address);
		if (pointer->Tag == NativeTag)
		{
			Dl_info info;
			const void* symbolAddress = reinterpret_cast<const void*>(pointer->Callback);
			if (dladdr(symbolAddress, &info))
			{
				return [NSString stringWithCString:info.dli_sname encoding:NSUTF8StringEncoding];
			}
		}
		else if (std::shared_ptr<const Common::AllocationDetails> details = allocator.GetDetails(address))
		{
			uint32_t offset = allocator.GetAllocationOffset(address);
			std::string reason = details->GetAllocationDetails(offset);
			return [NSString stringWithCString:reason.c_str() encoding:NSUTF8StringEncoding];
		}
	}
	catch (Common::PPCRuntimeException& ex)
	{ }
	return nil;
}

-(NSString*)explainAddress:(unsigned)address
{
	if (std::shared_ptr<const Common::AllocationDetails> details = vm->allocator.GetDetails(address))
	{
		uint32_t offset = vm->allocator.GetAllocationOffset(address);
		std::string description = details->GetAllocationDetails(offset);
		return [NSString stringWithCString:description.c_str() encoding:NSUTF8StringEncoding];
	}
	return nil;
}

-(NSString*)stringAtAddress:(unsigned int)address
{
	try
	{
		const char* atAddress = vm->allocator.ToPointer<const char>(address);
		uint32_t offset = vm->allocator.GetAllocationOffset(address);
		uint32_t limit = vm->allocator.GetDetails(address)->Size() - offset;
		size_t length = strnlen(atAddress, limit);
		
		// check that the first few couple characters are printable
		bool valid = true;
		for (size_t i = 0; i < std::min(length, size_t(8)); i++)
		{
			if (atAddress[i] < 0x20)
			{
				valid = false;
				break;
			}
		}
		
		if (valid)
		{
			// initWithBytesNoCopy takes a non-const pointer because it is allowed to free the buffer in some circumstances;
			// but in our case no such thing will happen, so it is safe to use a const_cast
			char* mutableString = const_cast<char*>(atAddress);
			NSString* result = [[NSString alloc] initWithBytesNoCopy:mutableString length:length encoding:NSMacOSRomanStringEncoding freeWhenDone:NO];
			return [result autorelease];
		}
	}
	catch (Common::PPCRuntimeException&)
	{ }
	return nil;
}

-(NSNumber*)wordAtAddress:(unsigned int)address
{
	try
	{
		const Common::UInt32* atAddress = vm->allocator.ToPointer<const Common::UInt32>(address);
		return @(atAddress->Get());
	}
	catch (Common::PPCRuntimeException&)
	{
		return nil;
	}
}

-(NSNumber*)floatAtAddress:(unsigned int)address
{
	try
	{
		const Common::Real32* atAddress = vm->allocator.ToPointer<const Common::Real32>(address);
		return @(atAddress->Get());
	}
	catch (Common::PPCRuntimeException&)
	{
		return nil;
	}
}

-(NSNumber*)doubleAtAddress:(unsigned int)address
{
	try
	{
		const Common::Real64* atAddress = vm->allocator.ToPointer<const Common::Real64>(address);
		return @(atAddress->Get());
	}
	catch (Common::PPCRuntimeException&)
	{
		return nil;
	}
}

-(void)addBreakpoint:(uint32_t)address
{
	if (![self breakpointExists:address])
	{
		[breakpoints addObject:@(address)];
		NSDictionary* changes = @{
			CXVirtualMachineBreakpointChangeTypeKey: CXVirtualMachineAddedBreakpoint,
			CXVirtualMachineBreakpointAddressKey:@(address)
		};
		[breakpointsChanged triggerWithData:changes];
	}
}

-(void)removeBreakpoint:(uint32_t)address
{
	if ([self breakpointExists:address])
	{
		[breakpoints removeObject:@(address)];
		NSDictionary* changes = @{
			CXVirtualMachineBreakpointChangeTypeKey: CXVirtualMachineRemovedBreakpoint,
			CXVirtualMachineBreakpointAddressKey:@(address)
		};
		[breakpointsChanged triggerWithData:changes];
	}
}

-(BOOL)toggleBreakpoint:(uint32_t)address
{
	if ([self breakpointExists:address])
	{
		[self removeBreakpoint:address];
		return NO;
	}
	else
	{
		[self addBreakpoint:address];
		return YES;
	}
}

-(BOOL)breakpointExists:(uint32_t)address
{
	return [breakpoints containsObject:@(address)];
}

-(NSArray*)stackTrace
{
	using Common::UInt32;
	
	NSMutableArray* stackFrames = [NSMutableArray array];
	// first frame: here
	[stackFrames addObject:@(pc)];
	
	// this relies on the fact that the stack is allocated on a 4-byte boundary
	uint32_t stackWord = vm->state.r1 & ~0b11;
	const UInt32* stackGuard = static_cast<UInt32*>(*vm->stack) + Common::StackPreparator::DefaultStackSize / sizeof (UInt32);
	uint32_t stackEnd = vm->allocator.ToIntPtr(stackGuard);
	uint32_t stackWordCount = (stackEnd - stackWord) / sizeof (UInt32);
	
	const UInt32* stackPointer;
	
	try { stackPointer = vm->allocator.ToArray<const UInt32>(stackWord, stackWordCount); }
	catch (Common::AccessViolationException&) { return nil; }
	
	for (; stackPointer != stackGuard; stackPointer++)
	{
		uint32_t hopefullyBranchAndLinkAddress = *stackPointer - 4;
		if (vm->IsCodeAddress(hopefullyBranchAndLinkAddress))
		{
			const UInt32* hopefullyBranchAndLink = vm->allocator.ToPointer<const UInt32>(hopefullyBranchAndLinkAddress);
			PPCVM::Instruction inst = hopefullyBranchAndLink->Get();
			int opcd = inst.OPCD;
			int subop = inst.SUBOP10;
			bool isBranch = opcd == 16 || opcd == 18 || (opcd == 19 && (subop == 16 || subop == 528));
			bool isLink = inst.LK;
			if (isBranch && isLink)
			{
				// alright, that makes "enough sense" to be added
				uint32_t address = stackPointer->Get();
				[stackFrames addObject:@(address)];
			}
		}
	}
	
	return stackFrames;
}

-(IBAction)run:(id)sender
{
	std::unordered_set<const void*> cppBreakpoints;
	for (NSNumber* number in breakpoints)
	{
		const void* address = vm->allocator.ToPointer<const void>(number.unsignedIntValue);
		cppBreakpoints.insert(address);
	}
	
	const Common::UInt32* eip = vm->allocator.ToPointer<Common::UInt32>(pc);
	PPCVM::MachineState oldState = vm->state;
	
	try
	{
		auto marker = vm->managers.ThreadManager().CreateExecutionMarker();
		eip = vm->interp.ExecuteUntil(eip, cppBreakpoints);
		self.pc = vm->allocator.ToIntPtr(eip);
		self.lastError = nil;
	}
	catch (PPCVM::Execution::InterpreterException& ex)
	{
		self.pc = ex.GetPC();
		self.lastError = [NSString stringWithCString:ex.what() encoding:NSUTF8StringEncoding];
	}
	
	[self refreshRegisters:&oldState];
}

-(IBAction)stepOver:(id)sender
{
	Common::UInt32 word = *vm->allocator.ToPointer<Common::UInt32>(pc);
	PPCVM::Instruction inst = word.Get();
	if (inst.OPCD == 18 && inst.LK == 1)
	{
		uint32_t sp = vm->state.r1;
		uint32_t desiredPC = pc + 4;
		do
		{
			[self runTo:desiredPC];
		} while (vm->state.r1 != sp);
	}
	else [self stepInto:sender];
}

-(IBAction)stepInto:(id)sender
{
	using namespace PPCVM::Execution;
	
	PPCVM::MachineState oldState = vm->state;
	const Common::UInt32* eip = vm->allocator.ToPointer<Common::UInt32>(pc);
	try
	{
		auto marker = vm->managers.ThreadManager().CreateExecutionMarker();
		eip = vm->interp.ExecuteOne(eip);
		self.pc = vm->allocator.ToIntPtr(eip);
		self.lastError = nil;
	}
	catch (PPCVM::Execution::InterpreterException& ex)
	{
		self.pc = ex.GetPC();
		self.lastError = [NSString stringWithCString:ex.what() encoding:NSUTF8StringEncoding];
	}
	
	[self refreshRegisters:&oldState];
	
	// don't stop inside a native call
	const NativeCall* nativeCall = reinterpret_cast<const NativeCall*>(eip);
	if (nativeCall->Tag == NativeTag)
		[self stepOver:sender];
}

-(void)runTo:(uint32_t)location
{
	std::unordered_set<const void*> until = {vm->allocator.ToPointer<const void>(location)};
	const Common::UInt32* eip = vm->allocator.ToPointer<Common::UInt32>(pc);
	PPCVM::MachineState oldState = vm->state;
	try
	{
		auto marker = vm->managers.ThreadManager().CreateExecutionMarker();
		eip = vm->interp.ExecuteUntil(eip, until);
		self.pc = vm->allocator.ToIntPtr(eip);
		self.lastError = nil;
	}
	catch (PPCVM::Execution::InterpreterException& ex)
	{
		self.pc = ex.GetPC();
		self.lastError = [NSString stringWithCString:ex.what() encoding:NSUTF8StringEncoding];
	}
	
	[self refreshRegisters:&oldState];
}

-(void)dealloc
{
	delete vm;
	[registers release];
	[breakpoints release];
	[changedRegisters release];
	[breakpointsChanged release];
	[super dealloc];
}

#pragma mark -
#pragma mark NSOutlineView stuff
-(BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
	return [outlineView parentForItem:item] == nil;
}

-(NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (item == nil) return registers.count;
	if ([item respondsToSelector:@selector(count)]) return [item count];
	return 0;
}

-(BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [self outlineView:outlineView numberOfChildrenOfItem:item] != 0;
}

-(id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	if (item == nil)
		return [registers objectForKey:@(index)];
	
	return [item objectAtIndex:index];
}

-(void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	if ([changedRegisters containsObject:item])
	{
		[cell setTextColor:NSColor.redColor];
	}
	else
	{
		[cell setTextColor:NSColor.blackColor];
	}
}

-(id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	if ([outlineView parentForItem:item] == nil)
	{
		if ([tableColumn.identifier isEqualToString:@"Register"])
		{
			static NSString* headers[] = {@"GPR", @"FPR", @"CR", @"SPR"};
			int index = [[[registers allKeysForObject:item] objectAtIndex:0] intValue];
			return headers[index];
		}
		return nil;
	}
	
	NSString* identifier = tableColumn.identifier;
	if ([identifier isEqualToString:@"Register"])
		return [item name];
	else if ([identifier isEqualToString:@"Value"])
		return [item value];
	
	return nil;
}

-(void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	if ([item isKindOfClass:CXRegister.class])
	{
		NSNumber* value = object;
		CXRegister* regObject = item;
		regObject.value = value;
	}
}

#pragma mark -
#pragma mark Private
-(void)refreshRegisters:(const PPCVM::MachineState *)oldState
{
	[changedRegisters removeAllObjects];
	// notify observers for value changes
	for (int i = 0; i < 8; i++)
	{
		if (oldState->cr[i] != vm->state.cr[i])
		{
			CXRegister* cr = [self.cr objectAtIndex:i];
			cr.value = @(vm->state.cr[i]);
			[changedRegisters addObject:cr];
		}
	}
	
	for (int i = 0; i < 32; i++)
	{
		if (oldState->gpr[i] != vm->state.gpr[i])
		{
			CXRegister* gpr = [self.gpr objectAtIndex:i];
			gpr.value = @(vm->state.gpr[i]);
			[changedRegisters addObject:gpr];
		}
		
		if (oldState->fpr[i] != vm->state.fpr[i])
		{
			CXRegister* fpr = [self.fpr objectAtIndex:i];
			fpr.value = @(vm->state.fpr[i]);
			[changedRegisters addObject:fpr];
		}
	}
	
	if (oldState->xer != vm->state.xer)
	{
		CXRegister* xer = [self.spr objectAtIndex:CXVirtualMachineSPRXERIndex];
		xer.value = @(vm->state.xer);
		[changedRegisters addObject:xer];
	}
	
	if (oldState->ctr != vm->state.ctr)
	{
		CXRegister* ctr = [self.spr objectAtIndex:CXVirtualMachineSPRCTRIndex];
		ctr.value = @(vm->state.ctr);
		[changedRegisters addObject:ctr];
	}
	
	if (oldState->lr != vm->state.lr)
	{
		CXRegister* lr = [self.spr objectAtIndex:CXVirtualMachineSPRLRIndex];
		lr.value = @(vm->state.lr);
		[changedRegisters addObject:lr];
	}
}

@end
