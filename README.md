# qtxFunctional

A functional programming framework for [Quartex Pascal](https://quartexdeveloper.com/),
modelled on the ideas behind Hackage's *Friday* library and written in pure
Object Pascal with no inline JavaScript.

| Idea | Provided by |
|---|---|
| Higher-order functions | `TFunction`, `TVarFunction`, `TFloatFunction`, `TFn` |
| Lazy evaluation | `TLazy`, `TLazyList`, `TSequence`, `TLazyInteger` |
| Function composition | `Compose`, `AndThen`, `TFn.Pipeline` |
| Fusion | `TFusion` (build-time rewrites, single-pass execution) |
| Immutable data | `TImmutableList`, `TPersistentMap` (AVL, structural sharing), `TVector`, `TMatrix` |
| Applications | `TFourier` (FFT), `TAutomaton`, `TNetwork` (neural net) |
| Computation graphs | `TGraphNode`, `TFunctionGraph` (inspect, optimise, execute) |

```pascal
uses functional.functions, functional.sequence;

TSequence.From(1)                                   // infinite
  .Map(TVarFunction.Lift(TFunction.Square))
  .Filter(TVarFunction.LiftPredicate(TFunction.IsOdd))
  .Take(5)
  .AsString;                                        // [1, 9, 25, 49, 81]
```

The three stages run as one fused pass, and the infinite source stops after
the ninth value.

## Repository layout

```
src/                  16 functional.*.pas library units
package/              qtxFunctional.pkg (v1.1.0.0) and its manifest
tools/                build-package.py: rebuilds the package from src/
tests/qtxFunctional   Node.js test suite (155 checks)
demos/                Four browser demonstrations (see below)
docs/GUIDE.md         Full guide to the library and the demos
```

## Installing

1. Copy `package/qtxFunctional.pkg` into `%APPDATA%\qtx\packages`.
2. Restart the Quartex Pascal IDE.
3. Add the `functional.*` units you need to a `uses` clause.

## Demonstrations

| Project | What it shows |
|---|---|
| `demos/qtxFunctionalDemo` | A 14-page tour of the whole library, from primes and fusion to FFT, automata, a neural network and benchmarks |
| `demos/qtxLazySequence` | Builds a pipeline from controls and traces every call, comparing lazy and eager work |
| `demos/qtxMemoisation` | Naive versus memoised recursion (fib(30): 2,692,537 calls versus 59), lazy values and a memoised infinite list |
| `demos/qtxFunctionGraph` | Computation graphs drawn before and after optimisation, with a rewrite log and single-pass execution |

Copy a project folder into your Quartex projects folder and open it in the IDE.

**Read [docs/GUIDE.md](docs/GUIDE.md)** for what each unit does and what each
demonstration shows.

## Licence

MIT. See [LICENSE](LICENSE).
