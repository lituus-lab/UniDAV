# SPDX-License-Identifier: Apache-2.0
import std/[strutils]
import contentline

type
  Component* = ref ComponentObj
  EntryKind* = enum ekProperty, ekComponent
  ComponentEntry* = object
    case kind*: EntryKind
    of ekProperty:
      property*: ContentLine
    of ekComponent:
      component*: Component
  ComponentObj* = object
    name*: string
    entries*: seq[ComponentEntry]
  ComponentParseError* = object of CatchableError

proc parseComponent(lines: seq[string]; index: var int; depth,
    maxDepth: int): Component =
  if depth > maxDepth:
    raise newException(ComponentParseError, "component nesting exceeds depth limit")
  if index >= lines.len:
    raise newException(ComponentParseError, "expected BEGIN component")
  let beginLine = parseContentLine(lines[index])
  if beginLine.name != "BEGIN" or beginLine.value.len == 0:
    raise newException(ComponentParseError,
        "expected BEGIN component at line " & $(index + 1))
  result = Component(name: beginLine.value.toUpperAscii)
  inc index
  while index < lines.len:
    let line = parseContentLine(lines[index])
    if line.name == "BEGIN":
      result.entries.add(ComponentEntry(kind: ekComponent,
        component: parseComponent(lines, index, depth + 1, maxDepth)))
    elif line.name == "END":
      if line.value.toUpperAscii != result.name:
        raise newException(ComponentParseError, "mismatched END at line " & $(
            index + 1) &
          ": expected " & result.name & ", got " & line.value.toUpperAscii)
      inc index
      return
    else:
      result.entries.add(ComponentEntry(kind: ekProperty, property: line))
      inc index
  raise newException(ComponentParseError, "missing END:" & result.name)

proc parseComponents*(input: string; maxDepth = 16): seq[Component] =
  let lines = unfold(input)
  var index = 0
  while index < lines.len:
    result.add(parseComponent(lines, index, 1, maxDepth))

proc properties*(component: Component; name: string): seq[ContentLine] =
  for entry in component.entries:
    if entry.kind == ekProperty and entry.property.name.cmpIgnoreCase(name) == 0:
      result.add(entry.property)

proc children*(component: Component; name = ""): seq[Component] =
  for entry in component.entries:
    if entry.kind == ekComponent and
        (name.len == 0 or entry.component.name.cmpIgnoreCase(name) == 0):
      result.add(entry.component)

proc serializeComponent*(component: Component): string =
  if component.isNil: raise newException(ComponentParseError, "cannot serialize nil component")
  result.add("BEGIN:" & component.name.toUpperAscii & "\r\n")
  for entry in component.entries:
    case entry.kind
    of ekProperty: result.add(serializeContentLine(entry.property) & "\r\n")
    of ekComponent: result.add(serializeComponent(entry.component))
  result.add("END:" & component.name.toUpperAscii & "\r\n")

proc serializeComponents*(components: openArray[Component]): string =
  for component in components: result.add(serializeComponent(component))

# End of module.
