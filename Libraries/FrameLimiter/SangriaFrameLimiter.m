//
//  SangriaFrameLimiter.m
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

// A frame rate cap for Wine processes, loaded with DYLD_INSERT_LIBRARIES.
//
// DXMT, D3DMetal and DXVK (through MoltenVK) all get every frame's drawable
// from -[CAMetalLayer nextDrawable]. Waiting there, before handing the
// drawable back, holds the game's render loop to the cap on every backend,
// and the frames it doesn't render are heat the GPU doesn't make.
//
// SANGRIA_MAX_FPS sets the cap. Absent, zero or unparsable, nothing is hooked.

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>
#import <os/lock.h>

static uint64_t gInterval;          // Minimum time between drawables, in mach ticks.
static id (*gOriginal)(id, SEL);    // The real -nextDrawable.
static const void *gDeadlineKey = &gDeadlineKey;
static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;

static uint64_t ticksForSeconds(double seconds) {
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    return (uint64_t)(seconds * 1e9 * info.denom / info.numer);
}

// Paces each layer separately: a game's swapchain and a launcher's window
// in the same process must not share one budget.
static id limitedNextDrawable(id layer, SEL cmd) {
    uint64_t now = mach_absolute_time();
    os_unfair_lock_lock(&gLock);
    NSNumber *stored = objc_getAssociatedObject(layer, gDeadlineKey);
    uint64_t deadline = stored ? stored.unsignedLongLongValue : now;
    // After a stall (loading, a hitch) start over instead of letting the
    // game race through a burst of "owed" frames.
    if (deadline + gInterval < now) {
        deadline = now;
    }
    uint64_t next = deadline + gInterval;
    objc_setAssociatedObject(layer, gDeadlineKey, @(next), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    os_unfair_lock_unlock(&gLock);

    if (deadline > now) {
        mach_wait_until(deadline);
    }
    return gOriginal(layer, cmd);
}

__attribute__((constructor))
static void installFrameLimiter(void) {
    const char *value = getenv("SANGRIA_MAX_FPS");
    if (value == NULL) {
        return;
    }
    double fps = atof(value);
    if (fps < 1 || fps > 1000) {
        return;
    }
    Method method = class_getInstanceMethod([CAMetalLayer class], @selector(nextDrawable));
    if (method == NULL) {
        return;
    }
    gInterval = ticksForSeconds(1.0 / fps);
    gOriginal = (id (*)(id, SEL))method_setImplementation(method, (IMP)limitedNextDrawable);
}
