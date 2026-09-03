# SPDX-License-Identifier: Apache-2.0
import std/[strutils]

type
  Parameter* = object
    name*: string
    values*: seq[string]

  ContentLine* = object
    group*: string
    name*: string
    params*: seq[Parameter]
    value*: string

  ParseError* = object of CatchableError

proc foldLine*(line: string): string

proc unfold*(input: string; maxLines = 100_000; maxBytes = 16 * 1024 *
    1024): seq[string] =
  if input.len > maxBytes:
    raise newException(ParseError, "document exceeds byte limit")
  var current = ""
  for line in input.splitLines:
    if line.len > 0 and line[0] in {' ', '\t'}:
      if current.len == 0:
        raise newException(ParseError, "continuation without a content line")
      current.add(line[1 .. ^1])
    else:
      if current.len > 0:
        result.add(current)
        if result.len > maxLines:
          raise newException(ParseError, "document exceeds line limit")
      current = line
  if current.len > 0:
    result.add(current)

proc findValueSeparator(line: string): int =
  var quoted = false
  var escaped = false
  for i, ch in line:
    if escaped:
      escaped = false
    elif ch == '\\':
      escaped = true
    elif ch == '"':
      quoted = not quoted
    elif ch == ':' and not quoted:
      return i
  -1

proc splitHeader(header: string): seq[string] =
  var part = ""
  var quoted = false
  for ch in header:
    if ch == '"': quoted = not quoted
    if ch == ';' and not quoted:
      result.add(part)
      part = ""
    else:
      part.add(ch)
  result.add(part)

proc decodeParameterValue(value: string): string =
  var index = 0
  while index < value.len:
    if value[index] == '^' and index + 1 < value.len:
      case value[index + 1]
      of '^': result.add('^')
      of 'n', 'N': result.add('\n')
      of '\'': result.add('\"')
      else:
        result.add('^')
        result.add(value[index + 1])
      index += 2
    else:
      result.add(value[index])
      inc index

proc splitParameterValues(raw: string): seq[string] =
  var value = ""
  var quoted = false
  for character in raw:
    if character == '\"':
      quoted = not quoted
    elif character == ',' and not quoted:
      result.add(decodeParameterValue(value))
      value = ""
    else:
      value.add(character)
  if quoted: raise newException(ParseError, "unterminated quoted parameter value")
  result.add(decodeParameterValue(value))

proc parseContentLine*(line: string): ContentLine =
  let colon = findValueSeparator(line)
  if colon <= 0:
    raise newException(ParseError, "content line has no name/value separator")
  let parts = splitHeader(line[0 ..< colon])
  var qualifiedName = parts[0]
  let dot = qualifiedName.find('.')
  if dot >= 0:
    result.group = qualifiedName[0 ..< dot]
    qualifiedName = qualifiedName[dot + 1 .. ^1]
  result.name = qualifiedName.toUpperAscii
  if result.name.len == 0:
    raise newException(ParseError, "content line has an empty name")
  result.value = line[colon + 1 .. ^1]
  for rawParam in parts[1 .. ^1]:
    let equals = rawParam.find('=')
    if equals <= 0:
      raise newException(ParseError, "parameter has no value")
    var parameter = Parameter(name: rawParam[0 ..< equals].toUpperAscii)
    parameter.values = splitParameterValues(rawParam[equals + 1 .. ^1])
    result.params.add(parameter)

proc encodeParameterValue(value: string): string =
  result = value.replace("^", "^^").replace("\n", "^n").replace("\"", "^'")
  if result.find({';', ':', ','}) >= 0:
    result = "\"" & result & "\""

proc serializeContentLine*(line: ContentLine): string =
  if line.group.len > 0: result.add(line.group & ".")
  result.add(line.name.toUpperAscii)
  for parameter in line.params:
    result.add(";" & parameter.name.toUpperAscii & "=")
    for index, value in parameter.values:
      if index > 0: result.add(',')
      result.add(encodeParameterValue(value))
  result.add(':' & line.value)
  foldLine(result)

proc foldLine*(line: string): string =
  if line.len <= 75: return line
  var start = 0
  var width = 75
  while start < line.len:
    var stop = min(start + width, line.len)
    while stop > start and stop < line.len and (line[stop].ord and 0xC0) == 0x80:
      dec stop
    if stop == start:
      raise newException(ParseError, "invalid UTF-8 fold boundary")
    if result.len > 0: result.add("\r\n ")
    result.add(line[start ..< stop])
    start = stop
    width = 74
