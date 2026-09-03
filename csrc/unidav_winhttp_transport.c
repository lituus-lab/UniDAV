// SPDX-License-Identifier: Apache-2.0
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "unidav_winhttp_transport.h"

struct unidav_winhttp_response {
  long status;
  char *body;
  size_t body_length;
  char *headers;
  char *effective_url;
  char *error;
};

static char *copy_string(const char *value) {
  if (!value) value = "";
  size_t length = strlen(value);
  char *result = (char *)malloc(length + 1);
  if (result) memcpy(result, value, length + 1);
  return result;
}

static wchar_t *utf8_to_wide(const char *value) {
  if (!value) return NULL;
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, NULL, 0);
  if (length <= 0) return NULL;
  wchar_t *result = (wchar_t *)malloc((size_t)length * sizeof(wchar_t));
  if (!result || MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1,
                                    result, length) != length) {
    free(result);
    return NULL;
  }
  return result;
}

static wchar_t *headers_to_wide(const char *value) {
  if (!value) value = "";
  size_t length = strlen(value);
  if (length > (SIZE_MAX - 1) / 2) return NULL;
  char *normalized = (char *)malloc(length * 2 + 1);
  if (!normalized) return NULL;
  size_t output = 0;
  for (size_t index = 0; index < length; ++index) {
    if (value[index] == '\n' && (index == 0 || value[index - 1] != '\r'))
      normalized[output++] = '\r';
    normalized[output++] = value[index];
  }
  normalized[output] = '\0';
  wchar_t *result = utf8_to_wide(normalized);
  free(normalized);
  return result;
}

static char *wide_to_utf8(const wchar_t *value, int length) {
  if (!value) return copy_string("");
  int needed = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, length,
                                  NULL, 0, NULL, NULL);
  if (length > 0 && needed == 0) return NULL;
  char *result = (char *)malloc((size_t)needed + 1);
  if (!result) return NULL;
  if (needed > 0 && WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value,
                                       length, result, needed, NULL, NULL) != needed) {
    free(result);
    return NULL;
  }
  result[needed] = '\0';
  return result;
}

static void set_error(unidav_winhttp_response *response, const char *message) {
  if (!response->error) response->error = copy_string(message);
}

static void set_windows_error(unidav_winhttp_response *response, const char *operation) {
  char message[160];
  (void)snprintf(message, sizeof(message), "%s failed (WinHTTP error %lu)",
                 operation, (unsigned long)GetLastError());
  set_error(response, message);
}

static int remaining_timeout(ULONGLONG started, long timeout_ms) {
  ULONGLONG elapsed = GetTickCount64() - started;
  if (elapsed >= (ULONGLONG)timeout_ms) return 0;
  ULONGLONG remaining = (ULONGLONG)timeout_ms - elapsed;
  return remaining > INT_MAX ? INT_MAX : (int)remaining;
}

static BOOL apply_timeouts(HINTERNET handle, long connect_timeout_ms,
                           long timeout_ms, ULONGLONG started) {
  int remaining = remaining_timeout(started, timeout_ms);
  if (remaining <= 0) {
    SetLastError(ERROR_TIMEOUT);
    return FALSE;
  }
  int connect = connect_timeout_ms < remaining ? (int)connect_timeout_ms : remaining;
  return WinHttpSetTimeouts(handle, connect, connect, remaining, remaining);
}

static BOOL append_body(unidav_winhttp_response *response, const char *data,
                        size_t length, size_t limit) {
  if (length > limit - response->body_length) {
    SetLastError(ERROR_INSUFFICIENT_BUFFER);
    return FALSE;
  }
  size_t required = response->body_length + length + 1;
  char *replacement = (char *)realloc(response->body, required);
  if (!replacement) {
    SetLastError(ERROR_OUTOFMEMORY);
    return FALSE;
  }
  response->body = replacement;
  memcpy(response->body + response->body_length, data, length);
  response->body_length += length;
  response->body[response->body_length] = '\0';
  return TRUE;
}

int unidav_winhttp_global_init(void) { return 0; }

unidav_winhttp_response *unidav_winhttp_perform(const char *method, const char *url,
    const char *header_lines, const char *body, size_t body_length,
    long connect_timeout_ms, long timeout_ms, size_t max_body_bytes,
    const char *ca_bundle_path) {
  unidav_winhttp_response *response =
      (unidav_winhttp_response *)calloc(1, sizeof(*response));
  HINTERNET session = NULL, connection = NULL, request = NULL;
  wchar_t *wide_method = NULL, *wide_url = NULL, *wide_headers = NULL;
  wchar_t *host = NULL, *path = NULL;
  ULONGLONG started = GetTickCount64();
  URL_COMPONENTS parts;

  if (!response) return NULL;
  response->effective_url = copy_string(url);
  if (!method || !url || (!body && body_length != 0) || !response->effective_url) {
    set_error(response, "invalid or unallocatable WinHTTP request");
    goto cleanup;
  }
  if (connect_timeout_ms <= 0 || timeout_ms <= 0 ||
      connect_timeout_ms > timeout_ms || max_body_bytes == 0) {
    set_error(response, "invalid WinHTTP timeout or body limit");
    goto cleanup;
  }
  if (ca_bundle_path && ca_bundle_path[0] != '\0') {
    set_error(response, "custom CA bundles are unsupported by WinHTTP; use the Windows trust store");
    goto cleanup;
  }
  if (body_length > UINT32_MAX) {
    set_error(response, "DAV request body exceeds the WinHTTP size limit");
    goto cleanup;
  }

  wide_method = utf8_to_wide(method);
  wide_url = utf8_to_wide(url);
  wide_headers = headers_to_wide(header_lines);
  if (!wide_method || !wide_url || !wide_headers) {
    set_error(response, "WinHTTP request contains invalid UTF-8");
    goto cleanup;
  }

  memset(&parts, 0, sizeof(parts));
  parts.dwStructSize = sizeof(parts);
  parts.dwHostNameLength = (DWORD)-1;
  parts.dwUrlPathLength = (DWORD)-1;
  parts.dwExtraInfoLength = (DWORD)-1;
  if (!WinHttpCrackUrl(wide_url, 0, 0, &parts) || !parts.lpszHostName) {
    set_windows_error(response, "WinHttpCrackUrl");
    goto cleanup;
  }
  if (parts.nScheme != INTERNET_SCHEME_HTTP &&
      parts.nScheme != INTERNET_SCHEME_HTTPS) {
    set_error(response, "WinHTTP transport only accepts HTTP and HTTPS URLs");
    goto cleanup;
  }
  uint64_t parsed_path_length = (uint64_t)parts.dwUrlPathLength +
                                (uint64_t)parts.dwExtraInfoLength;
#if SIZE_MAX < UINT64_MAX
  if (parsed_path_length > SIZE_MAX) {
    set_error(response, "parsed WinHTTP URL is too large");
    goto cleanup;
  }
#endif
#if SIZE_MAX <= UINT32_MAX
  if ((size_t)parts.dwHostNameLength > SIZE_MAX / sizeof(wchar_t) - 1u) {
    set_error(response, "parsed WinHTTP host is too large");
    goto cleanup;
  }
#endif
  host = (wchar_t *)calloc((size_t)parts.dwHostNameLength + 1, sizeof(wchar_t));
  size_t path_length = (size_t)parsed_path_length;
  if (path_length > SIZE_MAX / sizeof(wchar_t) - 1) {
    set_error(response, "parsed WinHTTP URL is too large");
    goto cleanup;
  }
  path = (wchar_t *)calloc(path_length + 1, sizeof(wchar_t));
  if (!host || !path) {
    set_error(response, "could not allocate parsed WinHTTP URL");
    goto cleanup;
  }
  memcpy(host, parts.lpszHostName, parts.dwHostNameLength * sizeof(wchar_t));
  if (parts.dwUrlPathLength > 0)
    memcpy(path, parts.lpszUrlPath, parts.dwUrlPathLength * sizeof(wchar_t));
  if (parts.dwExtraInfoLength > 0)
    memcpy(path + parts.dwUrlPathLength, parts.lpszExtraInfo,
           parts.dwExtraInfoLength * sizeof(wchar_t));
  if (path_length == 0) wcscpy(path, L"/");

  session = WinHttpOpen(L"UniDAV/0.1", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                        WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (!session) {
    set_windows_error(response, "WinHttpOpen");
    goto cleanup;
  }
  if (!apply_timeouts(session, connect_timeout_ms, timeout_ms, started)) {
    set_windows_error(response, "WinHttpSetTimeouts");
    goto cleanup;
  }
  DWORD secure_protocols = WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 |
                           WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3;
  if (!WinHttpSetOption(session, WINHTTP_OPTION_SECURE_PROTOCOLS,
                        &secure_protocols, sizeof(secure_protocols))) {
    secure_protocols = WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2;
    if (!WinHttpSetOption(session, WINHTTP_OPTION_SECURE_PROTOCOLS,
                          &secure_protocols, sizeof(secure_protocols))) {
      set_windows_error(response, "configuring WinHTTP secure protocols");
      goto cleanup;
    }
  }
  connection = WinHttpConnect(session, host, parts.nPort, 0);
  if (!connection) {
    set_windows_error(response, "WinHttpConnect");
    goto cleanup;
  }
  request = WinHttpOpenRequest(connection, wide_method, path, NULL,
                               WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                               parts.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0);
  if (!request) {
    set_windows_error(response, "WinHttpOpenRequest");
    goto cleanup;
  }
  DWORD disabled = WINHTTP_DISABLE_REDIRECTS;
  if (!WinHttpSetOption(request, WINHTTP_OPTION_DISABLE_FEATURE,
                        &disabled, sizeof(disabled))) {
    set_windows_error(response, "disabling WinHTTP redirects");
    goto cleanup;
  }
  if (parts.nScheme == INTERNET_SCHEME_HTTPS) {
    DWORD enabled = WINHTTP_ENABLE_SSL_REVOCATION;
    if (!WinHttpSetOption(request, WINHTTP_OPTION_ENABLE_FEATURE,
                          &enabled, sizeof(enabled))) {
      set_windows_error(response, "enabling WinHTTP certificate revocation checks");
      goto cleanup;
    }
  }
  DWORD decompression = WINHTTP_DECOMPRESSION_FLAG_GZIP |
                        WINHTTP_DECOMPRESSION_FLAG_DEFLATE;
  (void)WinHttpSetOption(request, WINHTTP_OPTION_DECOMPRESSION,
                         &decompression, sizeof(decompression));
  if (wide_headers[0] != L'\0' &&
      !WinHttpAddRequestHeaders(request, wide_headers, (DWORD)-1,
                                WINHTTP_ADDREQ_FLAG_ADD)) {
    set_windows_error(response, "WinHttpAddRequestHeaders");
    goto cleanup;
  }
  if (!apply_timeouts(request, connect_timeout_ms, timeout_ms, started) ||
      !WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                          body_length ? (LPVOID)body : WINHTTP_NO_REQUEST_DATA,
                          (DWORD)body_length, (DWORD)body_length, 0)) {
    set_windows_error(response, "WinHttpSendRequest");
    goto cleanup;
  }
  if (!apply_timeouts(request, connect_timeout_ms, timeout_ms, started) ||
      !WinHttpReceiveResponse(request, NULL)) {
    set_windows_error(response, "WinHttpReceiveResponse");
    goto cleanup;
  }

  DWORD status = 0, status_size = sizeof(status);
  if (!WinHttpQueryHeaders(request,
      WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_size,
      WINHTTP_NO_HEADER_INDEX)) {
    set_windows_error(response, "querying WinHTTP status");
    goto cleanup;
  }
  response->status = (long)status;

  DWORD header_bytes = 0;
  (void)WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF,
                            WINHTTP_HEADER_NAME_BY_INDEX, NULL, &header_bytes,
                            WINHTTP_NO_HEADER_INDEX);
  if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || header_bytes > 256u * 1024u) {
    set_error(response, header_bytes > 256u * 1024u
      ? "DAV response headers exceed safety limit"
      : "could not size WinHTTP response headers");
    goto cleanup;
  }
  wchar_t *raw_headers = (wchar_t *)malloc(header_bytes);
  if (!raw_headers || !WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF,
      WINHTTP_HEADER_NAME_BY_INDEX, raw_headers, &header_bytes,
      WINHTTP_NO_HEADER_INDEX)) {
    free(raw_headers);
    set_windows_error(response, "querying WinHTTP response headers");
    goto cleanup;
  }
  response->headers = wide_to_utf8(raw_headers,
                                    (int)(header_bytes / sizeof(wchar_t)) - 1);
  free(raw_headers);
  if (!response->headers) {
    set_error(response, "could not encode WinHTTP response headers");
    goto cleanup;
  }

  for (;;) {
    if (!apply_timeouts(request, connect_timeout_ms, timeout_ms, started)) {
      if (remaining_timeout(started, timeout_ms) <= 0)
        set_error(response, "WinHTTP request exceeded total timeout");
      else
        set_windows_error(response, "updating WinHTTP response timeout");
      goto cleanup;
    }
    DWORD available = 0;
    if (!WinHttpQueryDataAvailable(request, &available)) {
      set_windows_error(response, "WinHttpQueryDataAvailable");
      goto cleanup;
    }
    if (available == 0) break;
    if ((size_t)available > max_body_bytes - response->body_length) {
      set_error(response, "DAV response exceeds configured body limit");
      goto cleanup;
    }
    char *chunk = (char *)malloc(available);
    if (!chunk) {
      set_error(response, "could not allocate WinHTTP response body");
      goto cleanup;
    }
    DWORD received = 0;
    BOOL read_ok = WinHttpReadData(request, chunk, available, &received);
    BOOL append_ok = read_ok && append_body(response, chunk, received, max_body_bytes);
    free(chunk);
    if (!append_ok) {
      set_windows_error(response, read_ok ? "buffering WinHTTP response" : "WinHttpReadData");
      goto cleanup;
    }
  }
  if (!response->body) response->body = copy_string("");

cleanup:
  if (request) WinHttpCloseHandle(request);
  if (connection) WinHttpCloseHandle(connection);
  if (session) WinHttpCloseHandle(session);
  free(path);
  free(host);
  free(wide_headers);
  free(wide_url);
  free(wide_method);
  return response;
}

long unidav_winhttp_response_status(const unidav_winhttp_response *response) {
  return response ? response->status : 0;
}
const char *unidav_winhttp_response_body(const unidav_winhttp_response *response) {
  return !response || !response->body ? "" : response->body;
}
size_t unidav_winhttp_response_body_length(const unidav_winhttp_response *response) {
  return response ? response->body_length : 0;
}
const char *unidav_winhttp_response_headers(const unidav_winhttp_response *response) {
  return !response || !response->headers ? "" : response->headers;
}
const char *unidav_winhttp_response_effective_url(const unidav_winhttp_response *response) {
  return !response || !response->effective_url ? "" : response->effective_url;
}
const char *unidav_winhttp_response_error(const unidav_winhttp_response *response) {
  return !response || !response->error ? "" : response->error;
}
void unidav_winhttp_response_free(unidav_winhttp_response *response) {
  if (!response) return;
  free(response->body);
  free(response->headers);
  free(response->effective_url);
  free(response->error);
  free(response);
}
