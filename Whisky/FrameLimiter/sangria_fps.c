/*
 *  sangria_fps.c
 *  Whisky
 *
 *  This file is part of Whisky.
 *
 *  Whisky is free software: you can redistribute it and/or modify it under the terms
 *  of the GNU General Public License as published by the Free Software Foundation,
 *  either version 3 of the License, or (at your option) any later version.
 *
 *  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 *  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 *  See the GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along with Whisky.
 *  If not, see https://www.gnu.org/licenses/.
 */

/* Frame limiter for Wine processes, loaded with DYLD_INSERT_LIBRARIES and
 * built by the app target's "Build Frame Limiter" phase into Resources.
 *
 * Every graphics backend here (D3DMetal, DXMT, and MoltenVK under DXVK and
 * vkd3d) asks -[CAMetalLayer nextDrawable] for each frame's drawable, so
 * pacing that one call caps them all. SANGRIA_MAX_FPS sets the rate; unset or
 * 0 leaves the process untouched.
 *
 * Nothing is linked beyond libSystem and libobjc, and the hook goes in only
 * once QuartzCore is loaded, so wineserver and other non-graphics processes
 * never pull in a framework because of this. */
#include <mach-o/dyld.h>
#include <mach/mach_time.h>
#include <objc/runtime.h>
#include <os/lock.h>
#include <stdint.h>
#include <stdlib.h>

#define MAX_LAYERS 16

static uint64_t interval_ticks;
static IMP original_next_drawable;
static os_unfair_lock hook_lock = OS_UNFAIR_LOCK_INIT;

/* Next allowed frame time per layer. A game has one swapchain; a handful of
 * slots with round-robin reuse covers the rest without allocating. */
static struct {
    const void *layer;
    uint64_t deadline;
} slots[MAX_LAYERS];
static unsigned next_slot;
static os_unfair_lock slot_lock = OS_UNFAIR_LOCK_INIT;

static uint64_t claim_deadline(const void *layer) {
    uint64_t now = mach_absolute_time();
    os_unfair_lock_lock(&slot_lock);
    int found = -1;
    for (int i = 0; i < MAX_LAYERS; i++) {
        if (slots[i].layer == layer) {
            found = i;
            break;
        }
    }
    if (found < 0) {
        found = (int)(next_slot++ % MAX_LAYERS);
        slots[found].layer = layer;
        slots[found].deadline = now;
    }
    /* A frame that is already late starts a new schedule rather than banking
     * time to catch up with, which would burst frames. */
    uint64_t deadline = slots[found].deadline > now ? slots[found].deadline : now;
    slots[found].deadline = deadline + interval_ticks;
    os_unfair_lock_unlock(&slot_lock);
    return deadline;
}

static id paced_next_drawable(id self, SEL cmd) {
    /* Acquire-loaded to pair with the release store in try_hook: the original
       has to be visible to this thread before the hook that calls it is. */
    IMP original = __atomic_load_n(&original_next_drawable, __ATOMIC_ACQUIRE);
    if (!original) return nil;
    uint64_t deadline = claim_deadline((const void *)self);
    if (deadline > mach_absolute_time()) mach_wait_until(deadline);
    return ((id (*)(id, SEL))original)(self, cmd);
}

/* Runs for every image loaded, until CAMetalLayer exists to hook. */
static void try_hook(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    os_unfair_lock_lock(&hook_lock);
    if (!original_next_drawable) {
        Class layer = objc_getClass("CAMetalLayer");
        Method method = layer ? class_getInstanceMethod(layer, sel_registerName("nextDrawable")) : NULL;
        if (method) {
            /* Store the original *before* publishing the hook. The obvious
               spelling — assigning the return value of method_setImplementation
               — installs paced_next_drawable first and only then records what
               it must call, and any thread that draws a frame in that window
               calls through a NULL pointer. A render thread is exactly the
               thread that is doing that. */
            IMP previous = method_getImplementation(method);
            __atomic_store_n(&original_next_drawable, previous, __ATOMIC_RELEASE);
            method_setImplementation(method, (IMP)paced_next_drawable);
        }
    }
    os_unfair_lock_unlock(&hook_lock);
}

__attribute__((constructor)) static void sangria_fps_init(void) {
    const char *value = getenv("SANGRIA_MAX_FPS");
    long fps = value ? strtol(value, NULL, 10) : 0;
    if (fps <= 0 || fps > 1000) return;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    interval_ticks = (1000000000ull / (uint64_t)fps) * timebase.denom / timebase.numer;
    /* Called for every image already loaded and every one loaded later. */
    _dyld_register_func_for_add_image(try_hook);
}
