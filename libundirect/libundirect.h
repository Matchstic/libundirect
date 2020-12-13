#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// readds a direct method back to the class, requiring the pointer to it
void m_libundirect_rebind(BOOL classMethod, void* directPtr, NSString* className, SEL selector, const char* format);

// find a direct method by searching for unique memory bytes
void* m_libundirect_find(NSString* imageName, unsigned char* bytesToSearch, size_t byteCount, unsigned char startByte);

// selectors that failed to be added
NSArray* m_libundirect_failedSelectors();

#ifdef __cplusplus
}
#endif
