#include "atomic_counter.h"
#include <stdatomic.h>
#include <stdlib.h>

struct khc_counters {
    _Atomic(int64_t) current_slot;
    int64_t capacity;
    _Atomic(int64_t) slots[];
};

void *khc_counters_create(int64_t capacity) {
    if (capacity <= 0) {
        return NULL;
    }
    size_t size = sizeof(struct khc_counters) + (size_t)capacity * sizeof(_Atomic(int64_t));
    struct khc_counters *c = (struct khc_counters *)calloc(1, size);
    if (c == NULL) {
        return NULL;
    }
    c->capacity = capacity;
    atomic_store_explicit(&c->current_slot, 0, memory_order_relaxed);
    return c;
}

void khc_counters_destroy(void *handle) {
    free(handle);
}

int64_t khc_counters_increment_current(void *handle) {
    struct khc_counters *c = (struct khc_counters *)handle;
    int64_t slot = atomic_load_explicit(&c->current_slot, memory_order_relaxed);
    return atomic_fetch_add_explicit(&c->slots[slot], 1, memory_order_relaxed) + 1;
}

int64_t khc_counters_load(const void *handle, int64_t slot) {
    const struct khc_counters *c = (const struct khc_counters *)handle;
    if (slot < 0 || slot >= c->capacity) {
        return 0;
    }
    return atomic_load_explicit(&c->slots[slot], memory_order_relaxed);
}

void khc_counters_set_current_slot(void *handle, int64_t slot) {
    struct khc_counters *c = (struct khc_counters *)handle;
    if (slot < 0 || slot >= c->capacity) {
        slot = 0;
    }
    atomic_store_explicit(&c->current_slot, slot, memory_order_relaxed);
}

int64_t khc_counters_current_slot(const void *handle) {
    const struct khc_counters *c = (const struct khc_counters *)handle;
    return atomic_load_explicit(&c->current_slot, memory_order_relaxed);
}

int64_t khc_counters_capacity(const void *handle) {
    const struct khc_counters *c = (const struct khc_counters *)handle;
    return c->capacity;
}