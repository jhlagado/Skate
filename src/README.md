# Compact Skate source

The compact replacement uses `src/compiler/` for the compiler and
`src/runtime/` for its runtime source. The existing root-level `compiler/` and
`runtime/` directories retain the prototype; they are not moved or copied here.

The C1 release is the first tested program in this source area. The current
build still retains the older root-level product while the replacement grows
module by module; each replacement must pass its own target proof and size
budget before it becomes the default build.

New assembly uses ATOM. Reuse of a prototype module must name its contract and
include its measured code, immutable data and workspace in the compact budget.
The engineering rules in `docs/compact/engineering.md` apply from the first
module: normally at most 500 lines, never over 1,000, with assembly contracts
and explanatory commentary. Each increment needs correctness verification,
independent review and measured compaction before the next increment.
