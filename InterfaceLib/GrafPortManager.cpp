//
// GrafPortManager.cpp
// Classix
//
// Copyright (C) 2013 Félix Cloutier
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

#include <sstream>
#include <iomanip>
#include "GrafPortManager.h"

namespace
{
	using namespace InterfaceLib;
	
	UGrafPort* AllocateGrafPort(Common::IAllocator& allocator, uint32_t width, uint32_t height, const std::string& allocationName)
	{
		std::stringstream ss;
		ss << "GrafPort <" << width << "x" << height << ">";
		if (allocationName.size() > 0)
		{
			ss << ": " << allocationName;
		}
		
		return allocator.Allocate<UGrafPort>(ss.str());
	}
	
	// we allocate at once all the memory that we need for all the parts of a CGrafPort
	struct ColorGrafPortEverythingElse
	{
		ColorGrafPortEverythingElse(Common::IAllocator& allocator, uint16_t colorTableSize)
		{
			memset(this, 0, sizeof *this);
			pixMapPointer = allocator.ToIntPtr(&pixMap);
			colorTablePointer = allocator.ToIntPtr(&colorTable);
			pixMap.pmTable = allocator.ToIntPtr(&colorTablePointer);
			colorTable.count = colorTableSize;
		}
		
		static ColorGrafPortEverythingElse& Allocate(Common::IAllocator& allocator, uint16_t colorTableSize, const std::string& allocationName = "Color Graf Port Support")
		{
			size_t totalSize = sizeof(ColorGrafPortEverythingElse) + sizeof(ColorSpec) * colorTableSize;
			uint8_t* bytes = allocator.Allocate(allocationName, totalSize);
			return *new (bytes) ColorGrafPortEverythingElse(allocator, colorTableSize);
		}
		
		ColorGrafPortEverythingElse(const ColorGrafPortEverythingElse&) = delete;
		ColorGrafPortEverythingElse(ColorGrafPortEverythingElse&&) = delete;
		
		Common::UInt32 pixMapPointer;
		Common::UInt32 colorTablePointer;
		PixMap pixMap;
		ColorTable colorTable;
	};
}

namespace InterfaceLib
{
	struct GrafPortData
	{
		InterfaceLib::UGrafPort* port;
		IOSurfaceRef surface;
	};
	
	GrafPortManager::GrafPortManager(Common::IAllocator& allocator)
	: allocator(allocator)
	{ }
	
	InterfaceLib::GrafPort& GrafPortManager::AllocateGrayGrafPort(const InterfaceLib::Rect& bounds, const std::string& allocationName)
	{
		UGrafPort* port = AllocateGrafPort(allocator, bounds.right - bounds.left, bounds.bottom - bounds.top, allocationName);
		InitializeGrayGrafPort(*port, bounds);
		return port->gray;
	}
	
	InterfaceLib::CGrafPort& GrafPortManager::AllocateColorGrafPort(const InterfaceLib::Rect& bounds, const std::string& allocationName)
	{
		UGrafPort* port = AllocateGrafPort(allocator, bounds.right - bounds.left, bounds.bottom - bounds.top, allocationName);
		InitializeColorGrafPort(*port, bounds);
		return port->color;
	}
	
	void GrafPortManager::InitializeGrayGrafPort(UGrafPort& uPort, const InterfaceLib::Rect& bounds)
	{
		GrafPort& port = uPort.gray;
		port.portBits.bounds = bounds;
		port.portRect = bounds;
		port.procs = 0;
		// TODO complete initialization
		
		uint32_t address = allocator.ToIntPtr(&port);
		GrafPortData& portData = ports[address];
		portData.port = &uPort;
		portData.surface = nullptr; // TODO this should create a new IOSurface
		
		if (ports.size() == 1)
		{
			currentPort = &portData;
		}
	}
	
	void GrafPortManager::InitializeColorGrafPort(InterfaceLib::UGrafPort &uPort, const InterfaceLib::Rect& bounds)
	{
		std::stringstream ss;
		ss << "GrafPort Support Fields";
		if (const Common::AllocationDetails* details = allocator.GetDetails(&uPort))
		{
			ss << " for \"" << details->GetAllocationName() << "\" (0x";
			ss << std::hex << std::setw(8) << allocator.ToIntPtr(&uPort) << ")";
		}
		
		ColorGrafPortEverythingElse& support = ColorGrafPortEverythingElse::Allocate(allocator, 0, ss.str());
		support.pixMap.bounds = bounds;
		support.pixMap.vRes = 72;
		support.pixMap.hRes = 72;
		CGrafPort& port = uPort.color;
		port.portPixMap = allocator.ToIntPtr(&support.pixMapPointer);
		// TODO complete initialization
		
		uint32_t address = allocator.ToIntPtr(&port);
		GrafPortData& portData = ports[address];
		portData.port = &uPort;
		portData.surface = nullptr; // TODO this should create a new IOSurface
		
		if (ports.size() == 1)
		{
			currentPort = &portData;
		}
	}
	
	void GrafPortManager::SetCurrentPort(InterfaceLib::GrafPort &port)
	{
		uint32_t address = allocator.ToIntPtr(&port);
		auto iter = ports.find(address);
		assert(iter != ports.end() && "Unregistered graphics port");
		currentPort = &iter->second;
	}
	
	UGrafPort& GrafPortManager::GetCurrentPort()
	{
		assert(currentPort != nullptr && "No graf port set");
		return *currentPort->port;
	}
	
	IOSurfaceRef GrafPortManager::SurfaceOfGrafPort(InterfaceLib::UGrafPort& port)
	{
		return nullptr;
	}
	
	void GrafPortManager::DestroyGrafPort(UGrafPort& port)
	{
		// TODO destroy IOSurface
		uint32_t address = allocator.ToIntPtr(&port);
		ports.erase(address);
	}
	
	GrafPortManager::~GrafPortManager()
	{
		
	}
}
