# Linux build disabled on this branch

`codex/full-app-baseline-and-architecture` is a historical architecture/WIP
branch. Its committed Linux runtime and helper contract are not the certified
SecureWave Linux product, so this branch must not produce Linux application or
package artifacts.

The single source of truth for Linux builds, helper packaging, runtime fixes,
and live certification is:

`codex/linux-runtime-final`

`CMakeLists.txt` deliberately stops Linux configuration on this branch. Resolve
that guard only through an explicit architecture merge from the canonical
branch; do not bypass it or copy an older helper payload into a release.
