# SPDX-License-Identifier: Apache-2.0
import std/[osproc, streams, strutils, tables, unittest]
import UniDAV

suite "native DAV HTTP transport":
  var fixture = startProcess("python3", args = @["tests/http_fixture.py"],
    options = {poUsePath, poStdErrToStdOut})
  defer:
    fixture.terminate()
    discard fixture.waitForExit()
    fixture.close()
  let port = fixture.outputStream.readLine().parseInt
  let baseUrl = "http://127.0.0.1:" & $port

  var config = defaultHttpTransportConfig()
  config.allowPlainHttp = true
  let transport = newHttpTransport(config)

  test "preserves DAV method and body across a 307 redirect":
    var headers = initTable[string, string]()
    headers["Content-Type"] = "application/xml"
    let response = transport(DavRequest(httpMethod: dmPropfind,
      url: baseUrl & "/redirect", headers: headers, body: "<propfind/>"))
    check response.status == 207
    check response.finalUrl == baseUrl & "/dav"
    check response.headers["X-Fixture"] == "ready"
    check response.body == "PROPFIND:<propfind/>"
    let lowercase = transport(DavRequest(httpMethod: dmPropfind,
      url: baseUrl & "/lowercase-location", headers: initTable[string, string]()))
    check lowercase.status == 207
    let seeOther = transport(DavRequest(httpMethod: dmPropfind,
      url: baseUrl & "/see-other", headers: headers, body: "discarded"))
    check seeOther.status == 200
    check seeOther.body == "GET"

  test "supports standard methods beside DAV extensions":
    check transport(DavRequest(httpMethod: dmDelete, url: baseUrl & "/resource",
      headers: initTable[string, string]())).status == 204
    check transport(DavRequest(httpMethod: dmOptions, url: baseUrl,
      headers: initTable[string, string]())).body == "OPTIONS"
    check transport(DavRequest(httpMethod: dmPost, url: baseUrl,
      headers: initTable[string, string](), body: "schedule")).body == "POST"

  test "does not forward credentials to another origin":
    check sameOrigin(baseUrl & "/a", baseUrl & "/b")
    check not sameOrigin(baseUrl, "http://localhost:" & $port)
    var sensitive = initTable[string, string]()
    sensitive["Authorization"] = "Bearer caller-secret"
    sensitive["Cookie"] = "session=caller-secret"
    let response = transport(DavRequest(httpMethod: dmPropfind,
      url: baseUrl & "/cross-origin", headers: sensitive))
    check response.status == 207
    check response.body == "absent"

  test "rejects unsafe configuration, requests and redirects":
    var invalid = config
    invalid.credentials = DavCredentials(kind: dakBasic, username: "bad:name", password: "x")
    expect HttpTransportError: discard newHttpTransport(invalid)
    var insecure = config
    insecure.credentials = DavCredentials(kind: dakBearer, token: "secret")
    expect HttpTransportError:
      discard newHttpTransport(insecure)(DavRequest(httpMethod: dmGet,
        url: baseUrl,
        headers: initTable[string, string]()))
    expect HttpTransportError:
      discard transport(DavRequest(httpMethod: dmGet, url: "file:///etc/passwd",
        headers: initTable[string, string]()))
    expect HttpTransportError:
      discard transport(DavRequest(httpMethod: dmGet,
        url: "http://user:pass@127.0.0.1/",
        headers: initTable[string, string]()))
    expect HttpTransportError:
      discard transport(DavRequest(httpMethod: dmGet, url: baseUrl &
        "/bad\nurl",
        headers: initTable[string, string]()))
    expect HttpTransportError:
      discard transport(DavRequest(httpMethod: dmPropfind, url: baseUrl &
        "/missing-location",
        headers: initTable[string, string]()))
    var noRedirects = config
    noRedirects.maxRedirects = 0
    expect HttpTransportError:
      discard newHttpTransport(noRedirects)(DavRequest(httpMethod: dmPropfind,
        url: baseUrl & "/loop", headers: initTable[string, string]()))

  test "validates every transport bound and credential form":
    var invalid = config
    invalid.connectTimeoutMs = 0
    expect HttpTransportError: discard newHttpTransport(invalid)
    invalid = config
    invalid.connectTimeoutMs = invalid.timeoutMs + 1
    expect HttpTransportError: discard newHttpTransport(invalid)
    invalid = config
    invalid.maxBodyBytes = 0
    expect HttpTransportError: discard newHttpTransport(invalid)
    invalid = config
    invalid.maxRedirects = 21
    expect HttpTransportError: discard newHttpTransport(invalid)
    invalid = config
    invalid.credentials = DavCredentials(kind: dakBasic, username: "", password: "x")
    expect HttpTransportError: discard newHttpTransport(invalid)
    invalid.credentials = DavCredentials(kind: dakBasic, username: "ada",
        password: "bad\n")
    expect HttpTransportError: discard newHttpTransport(invalid)
    invalid.credentials = DavCredentials(kind: dakBearer, token: "")
    expect HttpTransportError: discard newHttpTransport(invalid)
    invalid = config
    invalid.caBundlePath = "bad\npath"
    expect HttpTransportError: discard newHttpTransport(invalid)
    invalid.caBundlePath = repeat("x", 4097)
    expect HttpTransportError: discard newHttpTransport(invalid)
    when defined(windows):
      invalid = config
      invalid.caBundlePath = "private-ca.pem"
      expect HttpTransportError: discard newHttpTransport(invalid)

  test "rejects header injection and transport-owned overrides":
    for pair in [("Bad:Name", "x"), ("X-Test", "bad\nvalue"), ("Host", "evil.test"),
                 ("Proxy-Authorization", "Basic x")]:
      var headers = initTable[string, string]()
      headers[pair[0]] = pair[1]
      expect HttpTransportError:
        discard transport(DavRequest(httpMethod: dmGet, url: baseUrl,
            headers: headers))
    var huge = initTable[string, string]()
    huge["X-Huge"] = repeat("x", 65 * 1024)
    expect HttpTransportError:
      discard transport(DavRequest(httpMethod: dmGet, url: baseUrl,
          headers: huge))
    var authenticated = config
    authenticated.allowPlainHttp = false
    authenticated.connectTimeoutMs = 100
    authenticated.timeoutMs = 100
    authenticated.credentials = DavCredentials(kind: dakBasic, username: "ada",
        password: "secret")
    var conflict = initTable[string, string]()
    conflict["Authorization"] = "Bearer duplicate"
    expect HttpTransportError:
      discard newHttpTransport(authenticated)(DavRequest(httpMethod: dmGet,
        url: "https://127.0.0.1:1/", headers: conflict))
    authenticated.credentials = DavCredentials(kind: dakBearer, token: "secret")
    expect HttpTransportError:
      discard newHttpTransport(authenticated)(DavRequest(httpMethod: dmGet,
        url: "https://127.0.0.1:1/", headers: initTable[string, string]()))

  test "bounds response bodies":
    var boundedConfig = config
    boundedConfig.maxBodyBytes = 128
    let bounded = newHttpTransport(boundedConfig)
    expect HttpTransportError:
      discard bounded(DavRequest(httpMethod: dmPropfind, url: baseUrl &
        "/large",
        headers: initTable[string, string]()))
    boundedConfig.maxRequestBodyBytes = 4
    let uploadBounded = newHttpTransport(boundedConfig)
    expect HttpTransportError:
      discard uploadBounded(DavRequest(httpMethod: dmPut, url: baseUrl & "/dav",
        headers: initTable[string, string](), body: "12345"))
