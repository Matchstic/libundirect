#import "libundirect.h"
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>

#define libundirect_EXPORT __attribute__((visibility ("default")))

NSString* _m_libundirect_getSelectorString(BOOL classMethod, NSString* className, SEL selector)
{
    NSString* prefix;

    if(classMethod)
    {
        prefix = @"+";
    }
    else
    {
        prefix = @"-";
    }

    return [NSString stringWithFormat:@"%@[%@ %@]", prefix, className, NSStringFromSelector(selector)];
}

NSMutableArray* failedSelectors;

void _m_libundirect_addToFailedSelectors(NSString* selectorString)
{
    static dispatch_once_t onceToken;
    dispatch_once (&onceToken, ^{
        failedSelectors = [NSMutableArray new];
    });

    [failedSelectors addObject:selectorString];
}

libundirect_EXPORT void m_libundirect_rebind(BOOL classMethod, void* directPtr, NSString* className, SEL selector, const char* format)
{
    NSString* selectorString = _m_libundirect_getSelectorString(classMethod, className, selector);

    NSLog(@"[m_libundirect_rebind] about to apply %@ with %s to %p", selectorString, format, directPtr);

    // check whether the direct pointer is actually a valid function pointer
    Dl_info info;
    int rc = dladdr(directPtr, &info);

    if(rc == 0)
    {
        NSLog(@"[m_libundirect_rebind] failed, not a valid function pointer");
        _m_libundirect_addToFailedSelectors(selectorString);
        return;
    }

    Class classToUse = NSClassFromString(className);

    if(!classToUse)
    {
        NSLog(@"[m_libundirect_rebind] failed, class %@ not found", className);
        _m_libundirect_addToFailedSelectors(selectorString);
        return;
    }

    // use metaclass if class method and check whether method already exists
    if(classMethod)
    {
        classToUse = object_getClass(classToUse);
        if([classToUse respondsToSelector:selector])
        {
            NSLog(@"[m_libundirect_rebind] failed, method already exists, likely already undirected");
            return;
        }
    }
    else
    {
        if([classToUse instancesRespondToSelector:selector])
        {
            NSLog(@"[m_libundirect_rebind] failed, method already exists, likely already undirected");
            return;
        }
    }

    class_addMethod(
        classToUse, 
        selector,
        (IMP)directPtr, 
        format
    );

    NSLog(@"[m_libundirect_rebind] %@ applied", selectorString);
}

void* _m_libundirect_find_in_region(vm_address_t startAddr, vm_offset_t regionLength, unsigned char* bytesToSearch, size_t byteCount)
{
    if(byteCount < 1)
    {
        return NULL;
    }

    unsigned char firstByte = bytesToSearch[0];

    vm_address_t curAddr = startAddr;

    while(curAddr < startAddr + regionLength)
    {
        size_t searchSize = (startAddr - curAddr) + regionLength;
        void* foundPtr = memchr((void*)curAddr,firstByte,searchSize);

        if(foundPtr == NULL)
        {
            NSLog(@"[_m_libundirect_find_in_region] foundPtr == NULL return");
            break;
        }

        vm_address_t foundAddr = (vm_address_t)foundPtr;

        size_t remainingBytes = regionLength - (foundAddr - startAddr);

        if(remainingBytes >= byteCount)
        {
            int memcmpRes = memcmp(foundPtr, bytesToSearch, byteCount);

            if(memcmpRes == 0)
            {
                NSLog(@"[_m_libundirect_find_in_region] foundPtr = %p", foundPtr);
                return foundPtr;
            }
        }
        else
        {
            break;
        }

        curAddr = foundAddr + 1;
    }

    return NULL;
}

void* _m_libundirect_seek_back(vm_address_t startAddr, unsigned char toByte, unsigned int maxSearch)
{
    vm_address_t curAddr = startAddr;

    while((startAddr - curAddr) < maxSearch)
    {
        void* curPtr = (void*)curAddr;
        unsigned char curChar = *(unsigned char*)curPtr;

        if(curChar == toByte)
        {
            return curPtr;
        }

        curAddr = curAddr - 1;
    }

    return NULL;
}

libundirect_EXPORT void* m_libundirect_find(NSString* imageName, unsigned char* bytesToSearch, size_t byteCount, unsigned char startByte)
{
    intptr_t baseAddr;
    struct mach_header_64* header;
    for (uint32_t i = 0; i < _dyld_image_count(); i++)
    {
        const char *name = _dyld_get_image_name(i);
        NSString *path = [NSString stringWithFormat:@"%s", name];
        if([path containsString:imageName])
        {
            baseAddr = _dyld_get_image_vmaddr_slide(i);
            header = (struct mach_header_64*)_dyld_get_image_header(i);
        }
    }

    const struct segment_command_64* cmd;

    uintptr_t addr = (uintptr_t)(header + 1);
    uintptr_t endAddr = addr + header->sizeofcmds;

    for(int ci = 0; ci < header->ncmds && addr <= endAddr; ci++)
	{
		cmd = (typeof(cmd))addr;

		addr = addr + cmd->cmdsize;

		if(cmd->cmd != LC_SEGMENT_64 || strcmp(cmd->segname, "__TEXT"))
		{
			continue;
		}

		void* result = _m_libundirect_find_in_region(cmd->vmaddr + baseAddr, cmd->vmsize, bytesToSearch, byteCount);

        if(result != NULL)
        {
            if(startByte)
            {
                void* backResult = _m_libundirect_seek_back((vm_address_t)result, startByte, 64);
                if(backResult)
                {
                    return backResult;
                }
                else
                {
                    return result;
                }
            }
            else
            {
                return result;
            }
        }
	}

    return NULL;
}

libundirect_EXPORT NSArray* m_libundirect_failedSelectors()
{
    return [failedSelectors copy];
}
