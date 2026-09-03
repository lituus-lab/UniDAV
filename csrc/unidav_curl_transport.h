// SPDX-License-Identifier: Apache-2.0
#ifndef UDAV_CURL_TRANSPORT_H
#define UDAV_CURL_TRANSPORT_H

#include <stddef.h>

typedef struct unidav_curl_response unidav_curl_response;

int unidav_curl_global_init(void);
unidav_curl_response *unidav_curl_perform(const char *method, const char *url,
    const char *header_lines, const char *body, size_t body_length,
    long connect_timeout_ms, long timeout_ms, size_t max_body_bytes,
    const char *ca_bundle_path);
long unidav_curl_response_status(const unidav_curl_response *response);
const char *unidav_curl_response_body(const unidav_curl_response *response);
size_t unidav_curl_response_body_length(const unidav_curl_response *response);
const char *unidav_curl_response_headers(const unidav_curl_response *response);
const char *unidav_curl_response_effective_url(const unidav_curl_response *response);
const char *unidav_curl_response_error(const unidav_curl_response *response);
void unidav_curl_response_free(unidav_curl_response *response);

#endif
