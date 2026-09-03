# SPDX-License-Identifier: Apache-2.0
## Lossless, narrowly-scoped edits for cached vCard and iCalendar documents.
## Unknown properties, parameters, ordering and nested components are retained.
import std/[sets, strutils, tables]
import component, contentline

type
  DocumentEditError* = object of CatchableError
  MergeConflict* = object
    path*: string
    property*: string
  MergeOutcome* = object
    document*: string
    conflicts*: seq[MergeConflict]

proc textEscape*(value: string): string =
  ## The TEXT escaping both formats require. CRLF and a bare CR escape to the
  ## same `\n` as a line feed: a carriage return left raw ends the content line
  ## mid-value, and the next parser reads the rest as a new property.
  ##
  ## CRLF first, so a pair does not become two escapes.
  value.replace("\\", "\\\\")
    .replace("\r\n", "\\n")
    .replace("\r", "\\n")
    .replace("\n", "\\n")
    .replace(",", "\\,")
    .replace(";", "\\;")

proc textUnescape*(value: string): string =
  var index = 0
  while index < value.len:
    if value[index] == '\\' and index + 1 < value.len:
      case value[index + 1]
      of 'n', 'N': result.add('\n')
      of '\\', ',', ';': result.add(value[index + 1])
      else:
        result.add('\\')
        result.add(value[index + 1])
      index += 2
    else:
      result.add(value[index])
      inc index

proc editableComponent*(root: Component; childKind = ""): Component =
  if root.isNil: raise newException(DocumentEditError, "document component is required")
  if childKind.len == 0: return root
  for child in root.children(childKind): return child
  raise newException(DocumentEditError, "requested calendar component is absent")

proc propertyValue*(component: Component; name: string): string =
  let matches = component.properties(name)
  if matches.len > 0: textUnescape(matches[0].value) else: ""

proc setTextProperty*(component: Component; name, value: string;
    required = false) =
  ## Replaces the first matching value in place, retaining its group and parameters.
  ## Duplicate known scalar properties are removed. Empty optional values are removed.
  if component.isNil or name.len == 0 or name.contains({'\r', '\n', ':', ';'}):
    raise newException(DocumentEditError, "safe component and property name are required")
  if required and value.len == 0:
    raise newException(DocumentEditError, "required property cannot be empty")
  let normalized = name.toUpperAscii
  var first = -1
  var filtered: seq[ComponentEntry]
  for entry in component.entries:
    if entry.kind == ekProperty and entry.property.name.cmpIgnoreCase(
        normalized) == 0:
      if first < 0 and value.len > 0:
        var updated = entry
        updated.property.value = textEscape(value)
        first = filtered.len
        filtered.add(updated)
    else:
      filtered.add(entry)
  if first < 0 and value.len > 0:
    filtered.add(ComponentEntry(kind: ekProperty,
      property: ContentLine(name: normalized, value: textEscape(value))))
  component.entries = filtered

proc replaceProperties*(target, source: Component; names: openArray[string]) =
  ## Replaces a declared set of properties as a group while retaining every
  ## undeclared target entry. This is suitable for merging a lossy UI model
  ## back into the original standards document without dropping extensions.
  if target.isNil or source.isNil:
    raise newException(DocumentEditError, "target and source components are required")
  var selected = initHashSet[string]()
  for name in names:
    if name.len == 0 or name.contains({'\r', '\n', ':', ';'}):
      raise newException(DocumentEditError, "safe property names are required")
    selected.incl(name.toUpperAscii)
  var replacements: seq[ComponentEntry]
  for entry in source.entries:
    if entry.kind == ekProperty and entry.property.name.toUpperAscii in selected:
      replacements.add(entry)
  var inserted = false
  var merged: seq[ComponentEntry]
  for entry in target.entries:
    if entry.kind == ekProperty and entry.property.name.toUpperAscii in selected:
      if not inserted:
        merged.add(replacements)
        inserted = true
    else:
      merged.add(entry)
  if not inserted: merged.add(replacements)
  target.entries = merged

proc lineSignature(line: ContentLine): string = serializeContentLine(line)

proc propertyGroups(component: Component): OrderedTable[string, seq[ContentLine]] =
  result = initOrderedTable[string, seq[ContentLine]]()
  for entry in component.entries:
    if entry.kind != ekProperty: continue
    let key = entry.property.name.toUpperAscii
    if key notin result: result[key] = @[]
    result[key].add(entry.property)

proc sameLines(left, right: seq[ContentLine]): bool =
  if left.len != right.len: return false
  for index in 0 ..< left.len:
    if lineSignature(left[index]) != lineSignature(right[index]): return false
  true

proc mergeComponent(base, local, remote: Component; path: string;
                   conflicts: var seq[MergeConflict]): Component =
  if base.isNil or local.isNil or remote.isNil or base.name != local.name or
      base.name != remote.name or base.children().len != local.children().len or
      base.children().len != remote.children().len:
    conflicts.add(MergeConflict(path: path, property: "<component>"))
    return base
  for index, child in base.children():
    let localChild = local.children()[index]
    let remoteChild = remote.children()[index]
    if child.name != localChild.name or child.name != remoteChild.name:
      conflicts.add(MergeConflict(path: path, property: "<component>"))
      return base
  result = Component(name: base.name)
  let baseGroups = propertyGroups(base)
  let localGroups = propertyGroups(local)
  let remoteGroups = propertyGroups(remote)
  var names: seq[string]
  for groups in [baseGroups, localGroups, remoteGroups]:
    for name in groups.keys:
      if name notin names: names.add(name)
  var merged = initTable[string, seq[ContentLine]]()
  for name in names:
    let b = if name in baseGroups: baseGroups[name] else: @[]
    let l = if name in localGroups: localGroups[name] else: @[]
    let r = if name in remoteGroups: remoteGroups[name] else: @[]
    if sameLines(l, b): merged[name] = r
    elif sameLines(r, b) or sameLines(l, r): merged[name] = l
    else:
      merged[name] = b
      conflicts.add(MergeConflict(path: path, property: name))
  var emitted = initHashSet[string]()
  for entry in base.entries:
    if entry.kind == ekComponent:
      let index = base.children().find(entry.component)
      result.entries.add(ComponentEntry(kind: ekComponent, component:
        mergeComponent(entry.component, local.children()[index],
          remote.children()[index], path & "/" & entry.component.name & "[" &
          $index & "]", conflicts)))
    else:
      let name = entry.property.name.toUpperAscii
      if name in emitted: continue
      emitted.incl(name)
      if name in merged:
        for line in merged[name]:
          result.entries.add(ComponentEntry(kind: ekProperty, property: line))
  for name in names:
    if name in emitted: continue
    for line in merged[name]:
      result.entries.add(ComponentEntry(kind: ekProperty, property: line))

proc mergeThreeWay*(base, local, remote: string): MergeOutcome =
  ## Merge independent property edits while retaining base data on conflicts.
  ## The caller decides whether to present or resolve the reported conflicts.
  try:
    let bases = parseComponents(base)
    let locals = parseComponents(local)
    let remotes = parseComponents(remote)
    if bases.len != locals.len or bases.len != remotes.len:
      raise newException(DocumentEditError, "three-way documents have different roots")
    var roots: seq[Component]
    for index in 0 ..< bases.len:
      roots.add(mergeComponent(bases[index], locals[index], remotes[index],
        "/" & bases[index].name & "[" & $index & "]", result.conflicts))
    result.document = serializeComponents(roots)
  except ComponentParseError as error:
    raise newException(DocumentEditError, error.msg)
