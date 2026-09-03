// SPDX-License-Identifier: Apache-2.0
#include <curl/curl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "unidav_curl_transport.h"

typedef struct {
  char *data;
  size_t length;
  size_t capacity;
  size_t limit;
  int exceeded;
} unidav_buffer;

struct unidav_curl_response {
  long status;
  char *body;
  size_t body_length;
  char *headers;
  char *effective_url;
  char *error;
};

static char *unidav_copy_string(const char *value) {
  size_t length;
  char *copy;
  if (value == NULL) value = "";
  length = strlen(value);
  copy = (char *)malloc(length + 1);
  if (copy != NULL) memcpy(copy, value, length + 1);
  return copy;
}

static int unidav_buffer_append(unidav_buffer *buffer, const char *data, size_t length) {
  size_t required;
  size_t capacity;
  char *replacement;
  if (length > buffer->limit - buffer->length) {
    buffer->exceeded = 1;
    return 0;
  }
  required = buffer->length + length + 1;
  if (required > buffer->capacity) {
    capacity = buffer->capacity == 0 ? 4096 : buffer->capacity;
    while (capacity < required) {
      if (capacity > buffer->limit / 2) {
        capacity = buffer->limit + 1;
        break;
      }
      capacity *= 2;
    }
    replacement = (char *)realloc(buffer->data, capacity);
    if (replacement == NULL) return 0;
    buffer->data = replacement;
    buffer->capacity = capacity;
  }
  memcpy(buffer->data + buffer->length, data, length);
  buffer->length += length;
  buffer->data[buffer->length] = '\0';
  return 1;
}

static size_t unidav_write_callback(char *data, size_t size, size_t count, void *userdata) {
  unidav_buffer *buffer = (unidav_buffer *)userdata;
  size_t length = size * count;
  return unidav_buffer_append(buffer, data, length) ? length : 0;
}

int unidav_curl_global_init(void) {
  return (int)curl_global_init(CURL_GLOBAL_DEFAULT);
}

unidav_curl_response *unidav_curl_perform(const char *method, const char *url,
    const char *header_lines, const char *body, size_t body_length,
    long connect_timeout_ms, long timeout_ms, size_t max_body_bytes,
    const char *ca_bundle_path) {
  CURL *handle = NULL;
  CURLcode code;
  struct curl_slist *headers = NULL;
  unidav_buffer body_buffer = {NULL, 0, 0, max_body_bytes, 0};
  unidav_buffer header_buffer = {NULL, 0, 0, 256 * 1024, 0};
  unidav_curl_response *response = (unidav_curl_response *)calloc(1, sizeof(*response));
  char error_buffer[CURL_ERROR_SIZE] = {0};
  char *effective_url = NULL;
  const char *cursor;

  if (response == NULL) return NULL;
  handle = curl_easy_init();
  if (handle == NULL) {
    response->error = unidav_copy_string("libcurl could not allocate a request handle");
    return response;
  }

  cursor = header_lines == NULL ? "" : header_lines;
  while (*cursor != '\0') {
    const char *end = strchr(cursor, '\n');
    size_t length = end == NULL ? strlen(cursor) : (size_t)(end - cursor);
    char *line = (char *)malloc(length + 1);
    if (line == NULL) {
      response->error = unidav_copy_string("could not allocate HTTP headers");
      goto cleanup;
    }
    memcpy(line, cursor, length);
    line[length] = '\0';
    headers = curl_slist_append(headers, line);
    free(line);
    if (headers == NULL) {
      response->error = unidav_copy_string("could not allocate HTTP headers");
      goto cleanup;
    }
    if (end == NULL) break;
    cursor = end + 1;
  }

#define UDAV_SETOPT(option, value) do { \
  code = curl_easy_setopt(handle, option, value); \
  if (code != CURLE_OK) goto option_error; \
} while (0)
  /* body may be NULL only when there is nothing to send. Passing NULL with a
     nonzero length makes libcurl read body_length bytes from address zero. */
  if (body == NULL && body_length != 0) {
    response->error = unidav_copy_string("request body is NULL with a nonzero length");
    goto cleanup;
  }
  UDAV_SETOPT(CURLOPT_URL, url);
  UDAV_SETOPT(CURLOPT_CUSTOMREQUEST, method);
  UDAV_SETOPT(CURLOPT_HTTPHEADER, headers);
  UDAV_SETOPT(CURLOPT_POSTFIELDS, body_length == 0 ? "" : body);
  UDAV_SETOPT(CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)body_length);
  UDAV_SETOPT(CURLOPT_CONNECTTIMEOUT_MS, connect_timeout_ms);
  UDAV_SETOPT(CURLOPT_TIMEOUT_MS, timeout_ms);
  UDAV_SETOPT(CURLOPT_NOSIGNAL, 1L);
  UDAV_SETOPT(CURLOPT_FOLLOWLOCATION, 0L);
  UDAV_SETOPT(CURLOPT_PROTOCOLS_STR, "http,https");
  UDAV_SETOPT(CURLOPT_SSL_VERIFYPEER, 1L);
  UDAV_SETOPT(CURLOPT_SSL_VERIFYHOST, 2L);
  if (ca_bundle_path != NULL && ca_bundle_path[0] != '\0') {
    UDAV_SETOPT(CURLOPT_CAINFO, ca_bundle_path);
  }
  UDAV_SETOPT(CURLOPT_USERAGENT, "UniDAV/0.1");
  UDAV_SETOPT(CURLOPT_ACCEPT_ENCODING, "");
  UDAV_SETOPT(CURLOPT_LOW_SPEED_LIMIT, 1L);
  UDAV_SETOPT(CURLOPT_LOW_SPEED_TIME, 30L);
  UDAV_SETOPT(CURLOPT_WRITEFUNCTION, unidav_write_callback);
  UDAV_SETOPT(CURLOPT_WRITEDATA, &body_buffer);
  UDAV_SETOPT(CURLOPT_HEADERFUNCTION, unidav_write_callback);
  UDAV_SETOPT(CURLOPT_HEADERDATA, &header_buffer);
  UDAV_SETOPT(CURLOPT_ERRORBUFFER, error_buffer);
#undef UDAV_SETOPT

  code = curl_easy_perform(handle);
  if (code != CURLE_OK) {
    if (body_buffer.exceeded) response->error = unidav_copy_string("DAV response exceeds configured body limit");
    else if (header_buffer.exceeded) response->error = unidav_copy_string("DAV response headers exceed safety limit");
    else response->error = unidav_copy_string(error_buffer[0] == '\0' ? curl_easy_strerror(code) : error_buffer);
    goto cleanup;
  }
  curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &response->status);
  curl_easy_getinfo(handle, CURLINFO_EFFECTIVE_URL, &effective_url);
  response->effective_url = unidav_copy_string(effective_url);
  response->body = body_buffer.data == NULL ? unidav_copy_string("") : body_buffer.data;
  response->body_length = body_buffer.length;
  response->headers = header_buffer.data == NULL ? unidav_copy_string("") : header_buffer.data;
  body_buffer.data = NULL;
  header_buffer.data = NULL;
  goto cleanup;

option_error:
  response->error = unidav_copy_string(curl_easy_strerror(code));

cleanup:
  free(body_buffer.data);
  free(header_buffer.data);
  curl_slist_free_all(headers);
  curl_easy_cleanup(handle);
  return response;
}

long unidav_curl_response_status(const unidav_curl_response *response) {
  return response == NULL ? 0 : response->status;
}

const char *unidav_curl_response_body(const unidav_curl_response *response) {
  return response == NULL || response->body == NULL ? "" : response->body;
}

size_t unidav_curl_response_body_length(const unidav_curl_response *response) {
  return response == NULL ? 0 : response->body_length;
}

const char *unidav_curl_response_headers(const unidav_curl_response *response) {
  return response == NULL || response->headers == NULL ? "" : response->headers;
}

const char *unidav_curl_response_effective_url(const unidav_curl_response *response) {
  return response == NULL || response->effective_url == NULL ? "" : response->effective_url;
}

const char *unidav_curl_response_error(const unidav_curl_response *response) {
  return response == NULL || response->error == NULL ? "" : response->error;
}

void unidav_curl_response_free(unidav_curl_response *response) {
  if (response == NULL) return;
  free(response->body);
  free(response->headers);
  free(response->effective_url);
  free(response->error);
  free(response);
}
