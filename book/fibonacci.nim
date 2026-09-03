# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "Fibonacci"

nbText: """
# Fibonacci

`fibonacci(n)` returns the nth Fibonacci number, iteratively, in O(n) time and
O(1) space. It exists to be the smallest function that still has a domain, a
contract and three surfaces — everything a real engine has, with none of the
subject matter in the way.

This chapter is what a domain chapter looks like. The next one is what a
failure chapter looks like.

## Why a bound at all

The sequence is unbounded and `int64` is not. `fib(92)` is the largest value
that fits; `fib(93)` overflows. So the function has a domain, and a domain is
something a caller can get wrong — which is the whole reason the rest of this
book exists.
"""

nbCode:
  import UniDAV

  echo "FibMaxN = ", FibMaxN
  echo "fib(FibMaxN)   = ", fibonacci(FibMaxN)
  echo "high(int64)    = ", high(int64)

nbText: """
The bound is not a round number chosen for comfort. It is the largest `n` whose
result fits, and the block above shows the two values within a factor of 1.3 of
each other.

## The listings, smallest first
"""

nbCode:
  echo "fib(0) = ", fibonacci(0)
  echo "fib(1) = ", fibonacci(1)
  echo "fib(2) = ", fibonacci(2)

nbCode:
  var previous = 0
  for n in 1 .. 10:
    let current = fibonacci(n)
    echo "fib(", n, ") = ", current, "   ratio to previous: ",
         (if previous == 0: "-" else: $(current / previous))
    previous = current

nbText: """
The ratio converges on the golden ratio, 1.618…, which is why the sequence
overruns `int64` at 92 rather than somewhere larger: each term is about 1.618
times the last, so the count of representable terms is `log(high(int64)) /
log(1.618)`.

## The postcondition is cheaper than the body

The contract states `result >= 0`, which is checkable in constant time. It does
not re-derive the answer by calling `fibonacci` again — a postcondition that
recomputes its own function proves nothing and doubles the cost.

Next: what happens when a caller ignores the bound. The three surfaces do three
different things, and only one of them raises.
"""

nbSave
