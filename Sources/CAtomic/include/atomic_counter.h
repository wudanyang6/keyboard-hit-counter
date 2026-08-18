#ifndef ATOMIC_COUNTER_H
#define ATOMIC_COUNTER_H
#include <stdint.h>

void *khc_counters_create(int64_t capacity);
void khc_counters_destroy(void *handle);
int64_t khc_counters_increment_current(void *handle);
int64_t khc_counters_load(const void *handle, int64_t slot);
void khc_counters_set_current_slot(void *handle, int64_t slot);
int64_t khc_counters_current_slot(const void *handle);
int64_t khc_counters_capacity(const void *handle);

#endif