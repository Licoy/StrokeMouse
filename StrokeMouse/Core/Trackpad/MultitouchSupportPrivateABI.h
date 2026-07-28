#ifndef MultitouchSupportPrivateABI_h
#define MultitouchSupportPrivateABI_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef void *SMPrivateMTDeviceRef;

typedef struct {
    float x;
    float y;
} SMPrivateMTPoint;

typedef struct {
    SMPrivateMTPoint position;
    SMPrivateMTPoint velocity;
} SMPrivateMTVector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    uint32_t state;
    int32_t fingerID;
    int32_t handID;
    SMPrivateMTVector normalizedVector;
    float zTotal;
    int32_t reserved9;
    float angle;
    float majorAxis;
    float minorAxis;
    SMPrivateMTVector absoluteVector;
    int32_t reserved14;
    int32_t reserved15;
    float zDensity;
} SMPrivateMTTouch;

typedef void (*SMPrivateMTFrameCallback)(
    SMPrivateMTDeviceRef device,
    SMPrivateMTTouch *touches,
    size_t touchCount,
    double timestamp,
    size_t frame,
    void *refcon
);

typedef SMPrivateMTDeviceRef (*SMPrivateMTDeviceCreateDefault)(void);
typedef void (*SMPrivateMTDeviceRelease)(SMPrivateMTDeviceRef device);
typedef void (*SMPrivateMTRegisterCallback)(
    SMPrivateMTDeviceRef device,
    SMPrivateMTFrameCallback callback,
    void *refcon
);
typedef void (*SMPrivateMTUnregisterCallback)(
    SMPrivateMTDeviceRef device,
    SMPrivateMTFrameCallback callback
);
typedef void (*SMPrivateMTDeviceStart)(
    SMPrivateMTDeviceRef device,
    int32_t mode
);
typedef void (*SMPrivateMTDeviceStop)(SMPrivateMTDeviceRef device);
typedef bool (*SMPrivateMTDeviceIsRunning)(SMPrivateMTDeviceRef device);
typedef int32_t (*SMPrivateMTGetDimensions)(
    SMPrivateMTDeviceRef device,
    int32_t *width,
    int32_t *height
);

_Static_assert(sizeof(SMPrivateMTTouch) == 96,
               "Unexpected MultitouchSupport contact ABI");
_Static_assert(offsetof(SMPrivateMTTouch, normalizedVector) == 32,
               "Unexpected normalized-vector ABI offset");

#endif
