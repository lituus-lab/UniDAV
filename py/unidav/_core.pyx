# cython: language_level=3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
from libc.stdlib cimport free

cdef extern from "UniDAV.h":
    const char *unidav_version()
    int unidav_status()
    char *unidav_validate_json(const char *input)
    char *unidav_normalize(const char *input)
    char *unidav_project_json(const char *input)
    char *unidav_validate_availability(const char *input)
    char *unidav_merge_three_way(const char *base, const char *local, const char *remote)
    char *unidav_patch_projection(const char *input, const char *patch_json)
    char *unidav_to_jcard(const char *input)
    char *unidav_from_jcard(const char *input)
    char *unidav_to_jcal(const char *input)
    char *unidav_from_jcal(const char *input)
    char *unidav_to_jscontact(const char *input)
    char *unidav_from_jscontact(const char *input)
    char *unidav_expand_recurrence(const char *start_value, const char *rule,
                                 const char *first_value, const char *last_value,
                                 int max_occurrences)
    char *unidav_timezone_offset(const char *vtimezone, const char *tzid,
                               const char *local_value)
    char *unidav_expand_recurrence_local(const char *vtimezone, const char *start_value,
                                       const char *rule, const char *tzid,
                                       const char *first_value, const char *last_value,
                                       int max_occurrences)
    void unidav_free(void *value)

def version():
    return (<bytes>unidav_version()).decode("utf-8")

def status():
    return unidav_status()

def validate(str value):
    import json
    cdef bytes encoded = value.encode("utf-8")
    cdef char *result = unidav_validate_json(encoded)
    if result == NULL:
        raise MemoryError("UniDAV returned no validation report")
    try:
        return json.loads((<bytes>result).decode("utf-8"))
    finally:
        unidav_free(result)

def normalize(str value):
    cdef bytes encoded = value.encode("utf-8")
    cdef char *result = unidav_normalize(encoded)
    if result == NULL:
        raise ValueError("Invalid vCard or iCalendar document")
    try:
        return (<bytes>result).decode("utf-8")
    finally:
        unidav_free(result)

def project(str value):
    import json
    cdef bytes encoded = value.encode("utf-8")
    cdef char *result = unidav_project_json(encoded)
    if result == NULL:
        raise ValueError("Unsupported vCard or iCalendar document")
    try:
        return json.loads((<bytes>result).decode("utf-8"))
    finally:
        unidav_free(result)

def validate_availability(str value):
    import json
    cdef bytes encoded = value.encode("utf-8")
    cdef char *result = unidav_validate_availability(encoded)
    if result == NULL:
        raise ValueError("Invalid availability input")
    try:
        return json.loads((<bytes>result).decode("utf-8"))["valid"]
    finally:
        unidav_free(result)

def merge(str base, str local, str remote):
    import json
    cdef bytes encoded_base = base.encode("utf-8")
    cdef bytes encoded_local = local.encode("utf-8")
    cdef bytes encoded_remote = remote.encode("utf-8")
    cdef char *result = unidav_merge_three_way(encoded_base, encoded_local, encoded_remote)
    if result == NULL:
        raise ValueError("Invalid three-way merge input")
    try:
        return json.loads((<bytes>result).decode("utf-8"))
    finally:
        unidav_free(result)

def patch(str value, dict projection):
    import json
    cdef bytes encoded = value.encode("utf-8")
    cdef bytes encoded_patch = json.dumps(projection).encode("utf-8")
    cdef char *result = unidav_patch_projection(encoded, encoded_patch)
    if result == NULL:
        raise ValueError("Invalid projected document update")
    try:
        return (<bytes>result).decode("utf-8")
    finally:
        unidav_free(result)

def to_jcard(str value):
    import json
    cdef bytes encoded = value.encode("utf-8")
    cdef char *result = unidav_to_jcard(encoded)
    if result == NULL:
        raise ValueError("Invalid vCard 4.0 document")
    try:
        return json.loads((<bytes>result).decode("utf-8"))
    finally:
        unidav_free(result)

def from_jcard(value):
    import json
    cdef bytes encoded = json.dumps(value, separators=(",", ":")).encode("utf-8")
    cdef char *result = unidav_from_jcard(encoded)
    if result == NULL:
        raise ValueError("Invalid jCard document")
    try:
        return (<bytes>result).decode("utf-8")
    finally:
        unidav_free(result)

def to_jcal(str value):
    import json
    cdef bytes encoded = value.encode("utf-8")
    cdef char *result = unidav_to_jcal(encoded)
    if result == NULL:
        raise ValueError("Invalid iCalendar document")
    try:
        return json.loads((<bytes>result).decode("utf-8"))
    finally:
        unidav_free(result)

def from_jcal(value):
    import json
    cdef bytes encoded = json.dumps(value, separators=(",", ":")).encode("utf-8")
    cdef char *result = unidav_from_jcal(encoded)
    if result == NULL:
        raise ValueError("Invalid jCal document")
    try:
        return (<bytes>result).decode("utf-8")
    finally:
        unidav_free(result)

def to_jscontact(str value):
    import json
    cdef bytes encoded = value.encode("utf-8")
    cdef char *result = unidav_to_jscontact(encoded)
    if result == NULL:
        raise ValueError("Invalid vCard for JSContact conversion")
    try:
        return json.loads((<bytes>result).decode("utf-8"))
    finally:
        unidav_free(result)

def from_jscontact(value):
    import json
    cdef bytes encoded = json.dumps(value, separators=(",", ":")).encode("utf-8")
    cdef char *result = unidav_from_jscontact(encoded)
    if result == NULL:
        raise ValueError("Invalid JSContact document")
    try:
        return (<bytes>result).decode("utf-8")
    finally:
        unidav_free(result)

def expand_recurrence(str start, str rule, str first, str last, int maximum=1000):
    import json
    cdef bytes encoded_start = start.encode("utf-8")
    cdef bytes encoded_rule = rule.encode("utf-8")
    cdef bytes encoded_first = first.encode("utf-8")
    cdef bytes encoded_last = last.encode("utf-8")
    cdef char *result = unidav_expand_recurrence(encoded_start, encoded_rule,
                                               encoded_first, encoded_last, maximum)
    if result == NULL:
        raise ValueError("Invalid or unsupported bounded recurrence")
    try:
        return json.loads((<bytes>result).decode("utf-8"))
    finally:
        unidav_free(result)

def timezone_offset(str vtimezone, str tzid, str local):
    import json
    cdef bytes encoded_timezone = vtimezone.encode("utf-8")
    cdef bytes encoded_tzid = tzid.encode("utf-8")
    cdef bytes encoded_local = local.encode("utf-8")
    cdef char *result = unidav_timezone_offset(encoded_timezone, encoded_tzid,
                                             encoded_local)
    if result == NULL:
        raise ValueError("Invalid or unregistered VTIMEZONE")
    try:
        return json.loads((<bytes>result).decode("utf-8"))["offsetSeconds"]
    finally:
        unidav_free(result)

def expand_recurrence_local(str vtimezone, str start, str rule, str tzid,
                            str first, str last, int maximum=1000):
    import json
    cdef bytes encoded_timezone = vtimezone.encode("utf-8")
    cdef bytes encoded_start = start.encode("utf-8")
    cdef bytes encoded_rule = rule.encode("utf-8")
    cdef bytes encoded_tzid = tzid.encode("utf-8")
    cdef bytes encoded_first = first.encode("utf-8")
    cdef bytes encoded_last = last.encode("utf-8")
    cdef char *result = unidav_expand_recurrence_local(encoded_timezone, encoded_start,
        encoded_rule, encoded_tzid, encoded_first, encoded_last, maximum)
    if result == NULL:
        raise ValueError("Invalid or unsupported timezone recurrence")
    try:
        return json.loads((<bytes>result).decode("utf-8"))
    finally:
        unidav_free(result)
