# SPDX-License-Identifier: Apache-2.0
import std/[base64, strutils, tables, uri]
import client

when defined(windows):
  {.compile: "../../csrc/unidav_winhttp_transport.c".}
  {.passL: "-lwinhttp".}
  {.emit: "typedef struct unidav_winhttp_response unidav_winhttp_response;".}
  type NativeHttpResponse {.importc: "unidav_winhttp_response",
      incompleteStruct.} = object
  proc nativeGlobalInit(): cint {.importc: "unidav_winhttp_global_init".}
  proc nativePerform(httpVerb, url, headers, body: cstring; bodyLength: csize_t;
                     connectTimeoutMs, timeoutMs: clong; maxBodyBytes: csize_t;
                     caBundlePath: cstring): ptr NativeHttpResponse
                     {.importc: "unidav_winhttp_perform".}
  proc nativeStatus(response: ptr NativeHttpResponse): clong {.importc: "unidav_winhttp_response_status".}
  proc nativeBody(response: ptr NativeHttpResponse): cstring {.importc: "unidav_winhttp_response_body".}
  proc nativeBodyLength(response: ptr NativeHttpResponse): csize_t {.importc: "unidav_winhttp_response_body_length".}
  proc nativeHeaders(response: ptr NativeHttpResponse): cstring {.importc: "unidav_winhttp_response_headers".}
  proc nativeEffectiveUrl(response: ptr NativeHttpResponse): cstring {.importc: "unidav_winhttp_response_effective_url".}
  proc nativeError(response: ptr NativeHttpResponse): cstring {.importc: "unidav_winhttp_response_error".}
  proc nativeResponseFree(response: ptr NativeHttpResponse) {.importc: "unidav_winhttp_response_free".}
else:
  {.compile: "../../csrc/unidav_curl_transport.c".}
  {.passL: "-lcurl".}
  {.emit: "typedef struct unidav_curl_response unidav_curl_response;".}
  type NativeHttpResponse {.importc: "unidav_curl_response",
      incompleteStruct.} = object
  proc nativeGlobalInit(): cint {.importc: "unidav_curl_global_init".}
  proc nativePerform(httpVerb, url, headers, body: cstring; bodyLength: csize_t;
                     connectTimeoutMs, timeoutMs: clong; maxBodyBytes: csize_t;
                     caBundlePath: cstring): ptr NativeHttpResponse
                     {.importc: "unidav_curl_perform".}
  proc nativeStatus(response: ptr NativeHttpResponse): clong {.importc: "unidav_curl_response_status".}
  proc nativeBody(response: ptr NativeHttpResponse): cstring {.importc: "unidav_curl_response_body".}
  proc nativeBodyLength(response: ptr NativeHttpResponse): csize_t {.importc: "unidav_curl_response_body_length".}
  proc nativeHeaders(response: ptr NativeHttpResponse): cstring {.importc: "unidav_curl_response_headers".}
  proc nativeEffectiveUrl(response: ptr NativeHttpResponse): cstring {.importc: "unidav_curl_response_effective_url".}
  proc nativeError(response: ptr NativeHttpResponse): cstring {.importc: "unidav_curl_response_error".}
  proc nativeResponseFree(response: ptr NativeHttpResponse) {.importc: "unidav_curl_response_free".}

type
  DavAuthKind* = enum dakNone, dakBasic, dakBearer
  DavCredentials* = object
    case kind*: DavAuthKind
    of dakBasic:
      username*: string
      password*: string
    of dakBearer:
      token*: string
    of dakNone:
      discard
  HttpTransportConfig* = object
    credentials*: DavCredentials
    connectTimeoutMs*: int
    timeoutMs*: int
    maxRequestBodyBytes*: int
    maxBodyBytes*: int
    maxRedirects*: int
    allowPlainHttp*: bool
    caBundlePath*: string
  HttpTransportError* = object of DavTransportError

let nativeInitializationResult = nativeGlobalInit()

proc defaultHttpTransportConfig*(): HttpTransportConfig =
  HttpTransportConfig(credentials: DavCredentials(kind: dakNone),
    connectTimeoutMs: 10_000, timeoutMs: 60_000,
    maxRequestBodyBytes: 16 * 1024 * 1024, maxBodyBytes: 16 * 1024 * 1024,
    maxRedirects: 5, allowPlainHttp: false)

proc containsControl(value: string): bool =
  for character in value:
    if character < ' ' or character == '\x7f': return true

proc validateConfig(config: HttpTransportConfig) =
  if nativeInitializationResult != 0:
    raise newException(HttpTransportError,
      "native HTTP initialization failed with code " &
      $nativeInitializationResult)
  if config.connectTimeoutMs <= 0 or config.timeoutMs <= 0:
    raise newException(HttpTransportError, "HTTP timeouts must be positive")
  if config.connectTimeoutMs > config.timeoutMs:
    raise newException(HttpTransportError, "connect timeout must not exceed total timeout")
  if config.maxRequestBodyBytes <= 0 or config.maxBodyBytes <= 0:
    raise newException(HttpTransportError, "maximum request and response sizes must be positive")
  if config.maxRedirects < 0 or config.maxRedirects > 20:
    raise newException(HttpTransportError, "maximum redirects must be between 0 and 20")
  if config.caBundlePath.len > 4096 or containsControl(config.caBundlePath):
    raise newException(HttpTransportError, "custom CA bundle path is unsafe")
  when defined(windows):
    if config.caBundlePath.len > 0:
      raise newException(HttpTransportError,
        "custom CA bundles are unsupported by WinHTTP; use the Windows trust store")
  case config.credentials.kind
  of dakBasic:
    if config.credentials.username.len == 0:
      raise newException(HttpTransportError, "Basic authentication username is required")
    if config.credentials.username.contains(':'):
      raise newException(HttpTransportError, "Basic authentication username must not contain a colon")
    if containsControl(config.credentials.username) or containsControl(
        config.credentials.password):
      raise newException(HttpTransportError, "Basic authentication credentials contain control characters")
  of dakBearer:
    if config.credentials.token.len == 0 or containsControl(
        config.credentials.token):
      raise newException(HttpTransportError, "Bearer token is empty or contains control characters")
  of dakNone: discard

proc validateHttpUrl(url: string; allowPlainHttp: bool) =
  if containsControl(url):
    raise newException(HttpTransportError, "HTTP URL contains control characters")
  let parsed = parseUri(url)
  if parsed.hostname.len == 0:
    raise newException(HttpTransportError, "HTTP URL requires a host")
  if parsed.username.len > 0 or parsed.password.len > 0:
    raise newException(HttpTransportError, "credentials in URLs are forbidden")
  if parsed.scheme == "https": discard
  elif parsed.scheme == "http" and allowPlainHttp: discard
  else:
    raise newException(HttpTransportError, "HTTPS is required by the DAV transport")

proc normalizedOrigin(url: string): string =
  let parsed = parseUri(url)
  let port = if parsed.port.len > 0: parsed.port
    elif parsed.scheme == "https": "443" else: "80"
  parsed.scheme.toLowerAscii & "://" & parsed.hostname.toLowerAscii & ":" & port

proc sameOrigin*(firstUrl, secondUrl: string): bool =
  normalizedOrigin(firstUrl) == normalizedOrigin(secondUrl)

proc authorization(credentials: DavCredentials): string =
  case credentials.kind
  of dakNone: ""
  of dakBasic: "Basic " & base64.encode(credentials.username & ":" &
      credentials.password)
  of dakBearer: "Bearer " & credentials.token

proc methodName(httpMethod: DavMethod): string =
  case httpMethod
  of dmGet: "GET"
  of dmPut: "PUT"
  of dmPost: "POST"
  of dmDelete: "DELETE"
  of dmOptions: "OPTIONS"
  of dmPropfind: "PROPFIND"
  of dmReport: "REPORT"

proc encodeHeaders(headers: Table[string, string]; auth: string): string =
  for name, value in headers:
    if name.len == 0 or name.contains(':') or containsControl(name) or
        containsControl(value):
      raise newException(HttpTransportError, "HTTP header name or value is unsafe")
    if name.cmpIgnoreCase("Proxy-Authorization") == 0 or name.cmpIgnoreCase(
        "Host") == 0:
      raise newException(HttpTransportError, "transport-owned HTTP header cannot be overridden")
    if auth.len > 0 and name.cmpIgnoreCase("Authorization") == 0:
      raise newException(HttpTransportError, "Authorization header conflicts with configured credentials")
    result.add(name & ": " & value & "\n")
  if auth.len > 0:
    result.add("Authorization: " & auth & "\n")
  if result.len > 64 * 1024:
    raise newException(HttpTransportError, "HTTP request headers exceed safety limit")

proc headerValue(headers: Table[string, string]; wanted: string): string =
  for name, value in headers:
    if name.cmpIgnoreCase(wanted) == 0: return value

proc removeSensitiveHeaders(headers: var Table[string, string]) =
  var removals: seq[string]
  for name in headers.keys:
    if name.cmpIgnoreCase("Authorization") == 0 or
        name.cmpIgnoreCase("Proxy-Authorization") == 0 or
        name.cmpIgnoreCase("Cookie") == 0 or name.cmpIgnoreCase("Host") == 0:
      removals.add(name)
  for name in removals: headers.del(name)

proc decodeHeaders(raw: string): Table[string, string] =
  result = initTable[string, string]()
  for line in raw.splitLines:
    if line.startsWith("HTTP/"):
      result.clear()
      continue
    let separator = line.find(':')
    if separator <= 0: continue
    let name = line[0 ..< separator].strip
    let value = line[separator + 1 .. ^1].strip
    if result.hasKey(name): result[name].add(", " & value)
    else: result[name] = value

proc singleRequest(request: DavRequest; config: HttpTransportConfig;
                   auth: string): DavHttpResponse =
  if request.body.len > config.maxRequestBodyBytes:
    raise newException(HttpTransportError, "DAV request body exceeds configured limit")
  let encodedHeaders = encodeHeaders(request.headers, auth)
  let httpVerb = methodName(request.httpMethod)
  let requestUrl = request.url
  let requestBody = request.body
  let response = nativePerform(cstring(httpVerb), cstring(requestUrl), cstring(
      encodedHeaders),
    cstring(requestBody), csize_t(requestBody.len), clong(
        config.connectTimeoutMs),
    clong(config.timeoutMs), csize_t(config.maxBodyBytes), cstring(
        config.caBundlePath))
  if response.isNil:
    raise newException(HttpTransportError, "native HTTP response allocation failed")
  defer: nativeResponseFree(response)
  let error = $nativeError(response)
  if error.len > 0: raise newException(HttpTransportError, error)
  let bodyLength = int(nativeBodyLength(response))
  var body = newString(bodyLength)
  if bodyLength > 0: copyMem(body[0].addr, nativeBody(response), bodyLength)
  result = DavHttpResponse(status: int(nativeStatus(response)), body: body,
    headers: decodeHeaders($nativeHeaders(response)),
        finalUrl: $nativeEffectiveUrl(response))

proc newHttpTransport*(config = defaultHttpTransportConfig()): DavTransport =
  validateConfig(config)
  result = proc(initialRequest: DavRequest): DavHttpResponse =
    validateHttpUrl(initialRequest.url, config.allowPlainHttp)
    if parseUri(initialRequest.url).scheme == "http" and
        config.credentials.kind != dakNone:
      raise newException(HttpTransportError, "authentication over plain HTTP is forbidden")
    var request = initialRequest
    var auth = authorization(config.credentials)
    for redirectCount in 0 .. config.maxRedirects:
      result = singleRequest(request, config, auth)
      if result.status notin [301, 302, 303, 307, 308]: return
      if redirectCount == config.maxRedirects:
        raise newException(HttpTransportError, "DAV redirect limit exceeded")
      let location = headerValue(result.headers, "Location")
      if location.len == 0:
        raise newException(HttpTransportError, "DAV redirect has no Location header")
      let nextUrl = resolveUrl(request.url, location)
      validateHttpUrl(nextUrl, config.allowPlainHttp)
      if parseUri(request.url).scheme == "https" and parseUri(nextUrl).scheme == "http":
        raise newException(HttpTransportError, "HTTPS to HTTP redirect is forbidden")
      if not sameOrigin(request.url, nextUrl):
        auth = ""
        request.headers.removeSensitiveHeaders()
      request.url = nextUrl
      if result.status == 303:
        request.httpMethod = dmGet
        request.body = ""
        request.headers.del("Content-Type")
        request.headers.del("Content-Length")

proc newCurlTransport*(config = defaultHttpTransportConfig()): DavTransport
    {.deprecated: "use newHttpTransport".} =
  newHttpTransport(config)

# Keep source mapping stable for gcov-generated exception branches.
# End of module.
