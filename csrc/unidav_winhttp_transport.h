// SPDX-License-Identifier: Apache-2.0
#ifndef UDAV_WINHTTP_TRANSPORT_H
#define UDAV_WINHTTP_TRANSPORT_H

#include <stddef.h>

typedef struct unidav_winhttp_response unidav_winhttp_response;

int unidav_winhttp_global_init(void);
unidav_winhttp_response *unidav_winhttp_perform(const char *method, const char *url,
    const char *header_lines, const char *body, size_t body_length,
    long connect_timeout_ms, long timeout_ms, size_t max_body_bytes,
    const char *ca_bundle_path);
long unidav_winhttp_response_status(const unidav_winhttp_response *response);
const char *unidav_winhttp_response_body(const unidav_winhttp_response *response);
size_t unidav_winhttp_response_body_length(const unidav_winhttp_response *response);
const char *unidav_winhttp_response_headers(const unidav_winhttp_response *response);
const char *unidav_winhttp_response_effective_url(const unidav_winhttp_response *response);
const char *unidav_winhttp_response_error(const unidav_winhttp_response *response);
void unidav_winhttp_response_free(unidav_winhttp_response *response);

#endif
