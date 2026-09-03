# SPDX-License-Identifier: Apache-2.0
import std/atomics
import contracts

type
  SyncPhase* = enum
    spIdle, spDiscover, spInventory, spDiff, spApplyRemote, spApplyLocal,
    spVerify, spCheckpoint, spComplete, spSuspended, spRetry, spFailed
  RetryDecision* = enum rdContinue, rdRetry, rdRefreshInventory, rdConflict,
    rdSuspend, rdFail
  SyncState* = object
    phase*: SyncPhase
    attempt*: int
    syncToken*: string
    lastError*: string
  CancellationToken* = ref object
    cancelled: Atomic[bool]
  SyncCancelledError* = object of CatchableError

proc newCancellationToken*(): CancellationToken =
  result = CancellationToken()
  result.cancelled.store(false, moRelaxed)

proc cancel*(token: CancellationToken) =
  if not token.isNil: token.cancelled.store(true, moRelease)

proc isCancelled*(token: CancellationToken): bool =
  not token.isNil and token.cancelled.load(moAcquire)

proc checkCancelled*(token: CancellationToken) =
  if token.isCancelled:
    raise newException(SyncCancelledError, "synchronization cancelled")

proc startSync*(token = ""): SyncState {.contractual.} =
  ensure:
    result.phase == spDiscover and result.attempt == 0 and
      result.syncToken == token
  body:
    result = SyncState(phase: spDiscover, syncToken: token)

proc advance*(state: var SyncState) =
  state.phase = case state.phase
  of spDiscover: spInventory
  of spInventory: spDiff
  of spDiff: spApplyRemote
  of spApplyRemote: spApplyLocal
  of spApplyLocal: spVerify
  of spVerify: spCheckpoint
  of spCheckpoint: spComplete
  else: state.phase

proc decideHttpStatus*(status: int; invalidSyncToken = false): RetryDecision =
  if invalidSyncToken: return rdRefreshInventory
  case status
  of 200..299: rdContinue
  of 401, 403: rdSuspend
  of 409, 412: rdConflict
  of 423, 425, 429, 500..599: rdRetry
  else: rdFail

proc retryDelayMs*(attempt: int; retryAfterMs = 0;
    jitterPermille = 0): int {.contractual.} =
  ensure:
    result >= 0 and result <= 300_000
  body:
    if retryAfterMs > 0:
      result = min(retryAfterMs, 300_000)
    else:
      let boundedAttempt = min(max(attempt, 0), 8)
      let base = min(500 * (1 shl boundedAttempt), 120_000)
      let boundedJitter = min(max(jitterPermille, -200), 200)
      result = max(0, base + (base * boundedJitter div 1000))

# Keep source mapping stable for gcov-generated branch locations.
# Coverage is intentionally strict: new branches require tests.
# End of module.
