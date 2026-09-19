# C1 compiler entry

`c1.asm` is the production entry under the replacement `src/` area. It
reuses the preserved ATOM reader, numeric ABI and publication modules while the
compact compiler is built in measured increments. The include boundary is
intentional: each reused module has an existing contract and measured extent,
and a later C1 change can replace one module without duplicating the whole
prototype.

C1 accepts a single arithmetic form with exact signed16 or binary16 literals,
computes the result at runtime, and publishes a committed NOBJ and COM image.
It does not yet implement global definitions, lexical bindings, procedures,
collection or general Scheme programs. Those limits are explicit capability
boundaries for this first compiler increment, not reduced language semantics.

Build and measure it with the C1 tools and tests. Production assembly uses
ATOM; the root `compiler/` and `runtime/` directories remain the preserved
product modules while replacement modules are independently accepted.
