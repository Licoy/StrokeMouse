#ifndef MultitouchSupportBridge_h
#define MultitouchSupportBridge_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t SMTrackpadBridgeErrorCode;
enum {
    SMTrackpadBridgeErrorCodeNone = 0,
    SMTrackpadBridgeErrorCodeFrameworkUnavailable = 1,
    SMTrackpadBridgeErrorCodeMissingSymbol = 2,
    SMTrackpadBridgeErrorCodeDeviceUnavailable = 3,
    SMTrackpadBridgeErrorCodeInvalidDimensions = 4,
    SMTrackpadBridgeErrorCodeStartFailed = 5,
    SMTrackpadBridgeErrorCodeInvalidFrame = 6,
    SMTrackpadBridgeErrorCodeResourceUnavailable = 7,
};

typedef struct {
    SMTrackpadBridgeErrorCode code;
    int32_t status;
    const char *detail;
} SMTrackpadBridgeError;

typedef int32_t SMTrackpadContactPhase;
enum {
    SMTrackpadContactPhaseBegan = 0,
    SMTrackpadContactPhaseMoved = 1,
    SMTrackpadContactPhaseResting = 2,
    SMTrackpadContactPhaseEnded = 3,
    SMTrackpadContactPhaseCancelled = 4,
};

typedef struct {
    int64_t identifier;
    SMTrackpadContactPhase phase;
    double x;
    double y;
} SMTrackpadContact;

typedef struct SMTrackpadBridge SMTrackpadBridge;

typedef void (*SMTrackpadFrameCallback)(
    void *context,
    double timestamp,
    const SMTrackpadContact *contacts,
    size_t contactCount
);

typedef void (*SMTrackpadFailureCallback)(
    void *context,
    SMTrackpadBridgeErrorCode code
);

/// Verifies that the framework can be opened and every required symbol resolves.
/// The framework is deliberately left loaded for the process lifetime.
bool SMTrackpadBridgeProbe(
    const char *frameworkPath,
    SMTrackpadBridgeError *error
);

/// Creates the default device and validates its sensor dimensions.
SMTrackpadBridge *SMTrackpadBridgeCreate(
    const char *frameworkPath,
    SMTrackpadBridgeError *error
);

/// Registers the refcon callback, starts the device, and verifies running state.
bool SMTrackpadBridgeStart(
    SMTrackpadBridge *bridge,
    SMTrackpadFrameCallback frameCallback,
    SMTrackpadFailureCallback failureCallback,
    void *context,
    SMTrackpadBridgeError *error
);

/// Stops delivery, unregisters the callback, and waits for callbacks in flight.
void SMTrackpadBridgeStop(SMTrackpadBridge *bridge);
bool SMTrackpadBridgeIsRunning(SMTrackpadBridge *bridge);

/// Stops and releases the device. The dlopen handle remains loaded intentionally.
void SMTrackpadBridgeDestroy(SMTrackpadBridge *bridge);

#ifdef __cplusplus
}
#endif

#endif
