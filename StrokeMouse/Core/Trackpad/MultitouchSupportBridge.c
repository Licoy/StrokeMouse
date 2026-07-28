#include "MultitouchSupportBridge.h"
#include "MultitouchSupportPrivateABI.h"

#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static const char *const SMDefaultFrameworkPath =
    "/System/Library/PrivateFrameworks/"
    "MultitouchSupport.framework/MultitouchSupport";
enum {
    SMMaximumContactCount = 64,
};

typedef struct {
    void *framework;
    SMPrivateMTDeviceCreateDefault createDefault;
    SMPrivateMTDeviceRelease release;
    SMPrivateMTRegisterCallback registerCallback;
    SMPrivateMTUnregisterCallback unregisterCallback;
    SMPrivateMTDeviceStart start;
    SMPrivateMTDeviceStop stop;
    SMPrivateMTDeviceIsRunning isRunning;
    SMPrivateMTGetDimensions getDimensions;
} SMLoader;

struct SMTrackpadBridge {
    SMLoader loader;
    SMPrivateMTDeviceRef device;
    pthread_mutex_t lifecycleLock;
    pthread_mutex_t callbackLock;
    pthread_cond_t callbacksDrained;
    bool started;
    bool acceptingCallbacks;
    size_t callbacksInFlight;
    SMTrackpadFrameCallback frameCallback;
    SMTrackpadFailureCallback failureCallback;
    void *callbackContext;
};

static void SMPrivateFrameCallback(
    SMPrivateMTDeviceRef device,
    SMPrivateMTTouch *touches,
    size_t touchCount,
    double timestamp,
    size_t frame,
    void *refcon
);

static void SMClearError(SMTrackpadBridgeError *error) {
    if (error == NULL) {
        return;
    }
    error->code = SMTrackpadBridgeErrorCodeNone;
    error->status = 0;
    error->detail = NULL;
}

static bool SMFail(
    SMTrackpadBridgeError *error,
    SMTrackpadBridgeErrorCode code,
    int32_t status,
    const char *detail
) {
    if (error != NULL) {
        error->code = code;
        error->status = status;
        error->detail = detail;
    }
    return false;
}

static bool SMLoadSymbol(
    void *framework,
    const char *name,
    void *destination,
    size_t destinationSize,
    SMTrackpadBridgeError *error
) {
    void *symbol = dlsym(framework, name);
    if (symbol == NULL) {
        return SMFail(
            error,
            SMTrackpadBridgeErrorCodeMissingSymbol,
            0,
            name
        );
    }
    if (destinationSize != sizeof(symbol)) {
        return SMFail(
            error,
            SMTrackpadBridgeErrorCodeResourceUnavailable,
            0,
            "function-pointer-size"
        );
    }
    memcpy(destination, &symbol, sizeof(symbol));
    return true;
}

#define SM_LOAD(loader, field, symbol, error) \
    SMLoadSymbol( \
        (loader)->framework, symbol, &(loader)->field, \
        sizeof((loader)->field), error \
    )

static bool SMLoad(
    SMLoader *loader,
    const char *frameworkPath,
    SMTrackpadBridgeError *error
) {
    memset(loader, 0, sizeof(*loader));
    SMClearError(error);
    const char *path = frameworkPath != NULL
        ? frameworkPath
        : SMDefaultFrameworkPath;
    loader->framework = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (loader->framework == NULL) {
        return SMFail(
            error,
            SMTrackpadBridgeErrorCodeFrameworkUnavailable,
            0,
            NULL
        );
    }

    return SM_LOAD(loader, createDefault, "MTDeviceCreateDefault", error)
        && SM_LOAD(loader, release, "MTDeviceRelease", error)
        && SM_LOAD(
            loader,
            registerCallback,
            "MTRegisterContactFrameCallbackWithRefcon",
            error
        )
        && SM_LOAD(
            loader,
            unregisterCallback,
            "MTUnregisterContactFrameCallback",
            error
        )
        && SM_LOAD(loader, start, "MTDeviceStart", error)
        && SM_LOAD(loader, stop, "MTDeviceStop", error)
        && SM_LOAD(loader, isRunning, "MTDeviceIsRunning", error)
        && SM_LOAD(
            loader,
            getDimensions,
            "MTDeviceGetSensorSurfaceDimensions",
            error
        );
}

bool SMTrackpadBridgeProbe(
    const char *frameworkPath,
    SMTrackpadBridgeError *error
) {
    SMLoader loader;
    return SMLoad(&loader, frameworkPath, error);
}

SMTrackpadBridge *SMTrackpadBridgeCreate(
    const char *frameworkPath,
    SMTrackpadBridgeError *error
) {
    SMTrackpadBridge *bridge = calloc(1, sizeof(*bridge));
    if (bridge == NULL) {
        SMFail(
            error,
            SMTrackpadBridgeErrorCodeResourceUnavailable,
            0,
            "bridge-allocation"
        );
        return NULL;
    }
    if (!SMLoad(&bridge->loader, frameworkPath, error)) {
        free(bridge);
        return NULL;
    }

    bridge->device = bridge->loader.createDefault();
    if (bridge->device == NULL) {
        SMFail(error, SMTrackpadBridgeErrorCodeDeviceUnavailable, 0, NULL);
        free(bridge);
        return NULL;
    }

    int32_t width = 0;
    int32_t height = 0;
    int32_t status = bridge->loader.getDimensions(
        bridge->device,
        &width,
        &height
    );
    if (status != 0 || width <= 0 || height <= 0
        || width > 1000000 || height > 1000000) {
        bridge->loader.release(bridge->device);
        SMFail(
            error,
            SMTrackpadBridgeErrorCodeInvalidDimensions,
            status,
            NULL
        );
        free(bridge);
        return NULL;
    }

    int syncStatus = pthread_mutex_init(&bridge->lifecycleLock, NULL);
    if (syncStatus != 0) {
        bridge->loader.release(bridge->device);
        SMFail(
            error,
            SMTrackpadBridgeErrorCodeResourceUnavailable,
            syncStatus,
            "synchronization"
        );
        free(bridge);
        return NULL;
    }
    syncStatus = pthread_mutex_init(&bridge->callbackLock, NULL);
    if (syncStatus != 0) {
        pthread_mutex_destroy(&bridge->lifecycleLock);
        bridge->loader.release(bridge->device);
        SMFail(
            error,
            SMTrackpadBridgeErrorCodeResourceUnavailable,
            syncStatus,
            "synchronization"
        );
        free(bridge);
        return NULL;
    }
    syncStatus = pthread_cond_init(&bridge->callbacksDrained, NULL);
    if (syncStatus != 0) {
        pthread_mutex_destroy(&bridge->callbackLock);
        pthread_mutex_destroy(&bridge->lifecycleLock);
        bridge->loader.release(bridge->device);
        SMFail(
            error,
            SMTrackpadBridgeErrorCodeResourceUnavailable,
            syncStatus,
            "synchronization"
        );
        free(bridge);
        return NULL;
    }
    return bridge;
}

static void SMDeactivateCallbacks(SMTrackpadBridge *bridge) {
    pthread_mutex_lock(&bridge->callbackLock);
    bridge->acceptingCallbacks = false;
    while (bridge->callbacksInFlight > 0) {
        pthread_cond_wait(
            &bridge->callbacksDrained,
            &bridge->callbackLock
        );
    }
    bridge->frameCallback = NULL;
    bridge->failureCallback = NULL;
    bridge->callbackContext = NULL;
    pthread_mutex_unlock(&bridge->callbackLock);
}

bool SMTrackpadBridgeStart(
    SMTrackpadBridge *bridge,
    SMTrackpadFrameCallback frameCallback,
    SMTrackpadFailureCallback failureCallback,
    void *context,
    SMTrackpadBridgeError *error
) {
    SMClearError(error);
    if (bridge == NULL || frameCallback == NULL || context == NULL) {
        return SMFail(
            error,
            SMTrackpadBridgeErrorCodeStartFailed,
            0,
            "invalid-start-arguments"
        );
    }

    pthread_mutex_lock(&bridge->lifecycleLock);
    if (bridge->started) {
        pthread_mutex_unlock(&bridge->lifecycleLock);
        return true;
    }
    pthread_mutex_lock(&bridge->callbackLock);
    bridge->frameCallback = frameCallback;
    bridge->failureCallback = failureCallback;
    bridge->callbackContext = context;
    bridge->acceptingCallbacks = true;
    pthread_mutex_unlock(&bridge->callbackLock);

    bridge->loader.registerCallback(
        bridge->device,
        SMPrivateFrameCallback,
        bridge
    );
    bridge->loader.start(bridge->device, 0);
    if (!bridge->loader.isRunning(bridge->device)) {
        bridge->loader.unregisterCallback(
            bridge->device,
            SMPrivateFrameCallback
        );
        SMDeactivateCallbacks(bridge);
        pthread_mutex_unlock(&bridge->lifecycleLock);
        return SMFail(
            error,
            SMTrackpadBridgeErrorCodeStartFailed,
            0,
            NULL
        );
    }
    bridge->started = true;
    pthread_mutex_unlock(&bridge->lifecycleLock);
    return true;
}

void SMTrackpadBridgeStop(SMTrackpadBridge *bridge) {
    if (bridge == NULL) {
        return;
    }
    pthread_mutex_lock(&bridge->lifecycleLock);
    if (bridge->started) {
        pthread_mutex_lock(&bridge->callbackLock);
        bridge->acceptingCallbacks = false;
        pthread_mutex_unlock(&bridge->callbackLock);
        bridge->loader.stop(bridge->device);
        bridge->loader.unregisterCallback(
            bridge->device,
            SMPrivateFrameCallback
        );
        bridge->started = false;
    }
    SMDeactivateCallbacks(bridge);
    pthread_mutex_unlock(&bridge->lifecycleLock);
}

bool SMTrackpadBridgeIsRunning(SMTrackpadBridge *bridge) {
    if (bridge == NULL) {
        return false;
    }
    pthread_mutex_lock(&bridge->lifecycleLock);
    bool running = bridge->started;
    pthread_mutex_unlock(&bridge->lifecycleLock);
    return running;
}

void SMTrackpadBridgeDestroy(SMTrackpadBridge *bridge) {
    if (bridge == NULL) {
        return;
    }
    SMTrackpadBridgeStop(bridge);
    bridge->loader.release(bridge->device);
    pthread_cond_destroy(&bridge->callbacksDrained);
    pthread_mutex_destroy(&bridge->callbackLock);
    pthread_mutex_destroy(&bridge->lifecycleLock);
    free(bridge);
}

static bool SMCopyPhase(
    uint32_t state,
    SMTrackpadContactPhase *phase
) {
    switch (state) {
        case 3:
            *phase = SMTrackpadContactPhaseBegan;
            return true;
        case 4:
            *phase = SMTrackpadContactPhaseMoved;
            return true;
        case 5:
            *phase = SMTrackpadContactPhaseEnded;
            return true;
        case 0:
        case 1:
        case 2:
        case 6:
        case 7:
            // Non-contact in-range/hover/linger states are not fingers on the
            // surface. Filtering them prevents a normal grouped lift from
            // looking like an interruption.
            return false;
        default:
            return false;
    }
}

static bool SMFrameIsValid(
    SMPrivateMTTouch *touches,
    size_t touchCount,
    double timestamp
) {
    if (!isfinite(timestamp) || touchCount > SMMaximumContactCount
        || (touchCount > 0 && touches == NULL)) {
        return false;
    }
    for (size_t index = 0; index < touchCount; index += 1) {
        SMPrivateMTTouch touch = touches[index];
        double x = touch.normalizedVector.position.x;
        double y = touch.normalizedVector.position.y;
        if (touch.state > 7 || !isfinite(x) || !isfinite(y)
            || fabs(x) > 4 || fabs(y) > 4) {
            return false;
        }
        for (size_t prior = 0; prior < index; prior += 1) {
            if (touches[prior].pathIndex == touch.pathIndex) {
                return false;
            }
        }
    }
    return true;
}

static bool SMBeginCallback(
    SMTrackpadBridge *bridge,
    SMTrackpadFrameCallback *frameCallback,
    SMTrackpadFailureCallback *failureCallback,
    void **context
) {
    pthread_mutex_lock(&bridge->callbackLock);
    if (!bridge->acceptingCallbacks) {
        pthread_mutex_unlock(&bridge->callbackLock);
        return false;
    }
    bridge->callbacksInFlight += 1;
    *frameCallback = bridge->frameCallback;
    *failureCallback = bridge->failureCallback;
    *context = bridge->callbackContext;
    pthread_mutex_unlock(&bridge->callbackLock);
    return true;
}

static void SMEndCallback(SMTrackpadBridge *bridge) {
    pthread_mutex_lock(&bridge->callbackLock);
    bridge->callbacksInFlight -= 1;
    if (bridge->callbacksInFlight == 0) {
        pthread_cond_broadcast(&bridge->callbacksDrained);
    }
    pthread_mutex_unlock(&bridge->callbackLock);
}

static void SMPrivateFrameCallback(
    SMPrivateMTDeviceRef device,
    SMPrivateMTTouch *touches,
    size_t touchCount,
    double timestamp,
    size_t frame,
    void *refcon
) {
    (void)device;
    (void)frame;
    SMTrackpadBridge *bridge = refcon;
    SMTrackpadFrameCallback frameCallback = NULL;
    SMTrackpadFailureCallback failureCallback = NULL;
    void *context = NULL;
    if (bridge == NULL
        || !SMBeginCallback(
            bridge,
            &frameCallback,
            &failureCallback,
            &context
        )) {
        return;
    }

    if (!SMFrameIsValid(touches, touchCount, timestamp)) {
        if (failureCallback != NULL) {
            failureCallback(
                context,
                SMTrackpadBridgeErrorCodeInvalidFrame
            );
        }
        SMEndCallback(bridge);
        return;
    }

    SMTrackpadContact contacts[SMMaximumContactCount];
    size_t contactCount = 0;
    for (size_t index = 0; index < touchCount; index += 1) {
        SMPrivateMTTouch touch = touches[index];
        SMTrackpadContactPhase phase;
        if (!SMCopyPhase(touch.state, &phase)) {
            continue;
        }
        contacts[contactCount].identifier = touch.pathIndex;
        contacts[contactCount].phase = phase;
        contacts[contactCount].x = touch.normalizedVector.position.x;
        contacts[contactCount].y = touch.normalizedVector.position.y;
        contactCount += 1;
    }
    frameCallback(context, timestamp, contacts, contactCount);
    SMEndCallback(bridge);
}
