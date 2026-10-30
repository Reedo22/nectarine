# Unified backend fallback

`0001-unified-backend-fallback.patch` includes the DXMT integration and
persistent backend selector/presentation-health changes. Apply to unified's
`cdbf4647b97fb07c1e3bd885dbe91fe0e482c9c1` tree (bigpc `7bd6d9db763`, Mac
`280cafe`). Do not first apply `patches/dxmt/0001-wine-dxmt-backend.patch`.

```sh
git switch -c fallback-chain
git apply --index /path/to/0001-unified-backend-fallback.patch
git commit -m 'Add unified backend fallback with presentation health'
```

The actual local Wine history is preserved on `fallback-chain` in
`~/nectarine-work/be-fallback` and Mac `~/protonbuild/wine-fallback`:
merge `ba428c4276e`, implementation `4b90ae08e9e`, corrections `32868430d00`,
`b601c9a74bb`, and `d7d19d2043c`.

Apply `gsession.patch` / `gsession-inner.patch` to the Mac's session launchers
to register `unified-fallback`, enable automatic trials, retain candidate
isolation/cleanup, and delay optional capture preloads until the game.
They are already installed on the test Mac. No live engine is modified.

Build/install, overrides, reset instructions, measured results and remaining
Satisfactory validation are in
[`results/2026-10-28-fallback/README.md`](../../results/2026-10-28-fallback/README.md).
