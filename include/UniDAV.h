/* SPDX-License-Identifier: Apache-2.0 */
#ifndef UNIDAV_H
#define UNIDAV_H
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UNIDAV_VERSION_MAJOR 0
#define UNIDAV_VERSION_MINOR 1
#define UNIDAV_VERSION_PATCH 0
#define UNIDAV_VERSION "0.1.0"

#define UNIDAV_VERSION_AT_LEAST(ma, mi, pa) \
  ((UNIDAV_VERSION_MAJOR > (ma)) || \
   (UNIDAV_VERSION_MAJOR == (ma) && UNIDAV_VERSION_MINOR > (mi)) || \
   (UNIDAV_VERSION_MAJOR == (ma) && UNIDAV_VERSION_MINOR == (mi) && \
    UNIDAV_VERSION_PATCH >= (pa)))

/* Static version string; do not free. */
const char *unidav_version(void);
int unidav_status(void);
char *unidav_validate_json(const char *input);
char *unidav_normalize(const char *input);
char *unidav_project_json(const char *input);
char *unidav_validate_availability(const char *input);
char *unidav_merge_three_way(const char *base, const char *local, const char *remote);
char *unidav_patch_projection(const char *input, const char *patch_json);
char *unidav_to_jcard(const char *input);
char *unidav_from_jcard(const char *input);
char *unidav_to_jcal(const char *input);
char *unidav_from_jcal(const char *input);
char *unidav_to_jscontact(const char *input);
char *unidav_from_jscontact(const char *input);
char *unidav_expand_recurrence(const char *start_value, const char *rule,
                             const char *first_value, const char *last_value,
                             int max_occurrences);
char *unidav_timezone_offset(const char *vtimezone, const char *tzid,
                           const char *local_value);
char *unidav_expand_recurrence_local(const char *vtimezone, const char *start_value,
                                   const char *rule, const char *tzid,
                                   const char *first_value, const char *last_value,
                                   int max_occurrences);
void unidav_free(void *value);
#ifdef __cplusplus
}
#endif
#endif
