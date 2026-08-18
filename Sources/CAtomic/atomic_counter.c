#include "atomic_counter.h"
#include <stdlib.h>

void *khc_counters_create(int64_t capacity) { return NULL; }
void khc_counters_destroy(void *handle) { (void)handle; }
int64_t khc_counters_increment_current(void *handle) { (void)handle; return 0; }
int64_t khc_counters_load(const void *handle, int64_t slot) { (void)handle; (void)slot; return 0; }
void khc_counters_set_current_slot(void *handle, int64_t slot) { (void)handle; (void)slot; }
int64_t khc_counters_current_slot(const void *handle) { (void)handle; return 0; }
int64_t khc_counters_capacity(const void *handle) { (void)handle; return 0; }