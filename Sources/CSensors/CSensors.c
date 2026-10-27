// Apple Silicon reports its temperatures through the HID event system rather than the SMC. These calls are
// private to IOKit but stable; Stats (MIT) and MenuMeters read the same sensors this way.
#include "CSensors.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

enum { kTemperatureEvent = 15, kAppleVendorPage = 0xff00, kTemperatureSensorUsage = 5 };

static IOHIDEventSystemClientRef client;
static CFArrayRef services;

static void connect(void) {
    client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return;
    int page = kAppleVendorPage, usage = kTemperatureSensorUsage;
    CFNumberRef values[2] = {
        CFNumberCreate(NULL, kCFNumberIntType, &page),
        CFNumberCreate(NULL, kCFNumberIntType, &usage),
    };
    CFStringRef keys[2] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    CFDictionaryRef matching = CFDictionaryCreate(NULL, (const void **)keys, (const void **)values, 2,
                                                  &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDEventSystemClientSetMatching(client, matching);
    CFRelease(matching);
    CFRelease(values[0]);
    CFRelease(values[1]);
    services = IOHIDEventSystemClientCopyServices(client);
}

double beanie_cpu_temperature(void) {
    if (!client) connect();
    if (!services) return -1;
    double dies = 0, all = 0;
    int dieCount = 0, allCount = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kTemperatureEvent, 0, 0);
        if (!event) continue;
        double value = IOHIDEventGetFloatValue(event, kTemperatureEvent << 16);
        CFRelease(event);
        if (value <= 0 || value > 130) continue;
        all += value;
        allCount++;
        // "tdie" sensors sit on the CPU dies; the rest are batteries, NAND, the GPU and such.
        CFStringRef name = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (name) {
            if (CFStringFind(name, CFSTR("tdie"), 0).location != kCFNotFound) {
                dies += value;
                dieCount++;
            }
            CFRelease(name);
        }
    }
    if (dieCount) return dies / dieCount;
    return allCount ? all / allCount : -1;
}
