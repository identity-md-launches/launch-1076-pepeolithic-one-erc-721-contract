# Vendored source provenance

All dependencies are ordinary source files. There are no submodules, package-install
steps, FFI calls, filesystem cheatcode permissions, or RPC requirements for tests.
The worker must supply the compiler pinned by `foundry.toml`: Solidity 0.8.26.

The import source is
[identity-md-launches/launch-928-ochre-one-erc-721-contract at b0923044ec165ae0a94a70ea58793153692a5a93](https://github.com/identity-md-launches/launch-928-ochre-one-erc-721-contract/tree/b0923044ec165ae0a94a70ea58793153692a5a93).

| Files | Origin | License |
| --- | --- | --- |
| `src/Pepeolithic.sol` | Reference `src/Ochre.sol`, collection/interface identifiers renamed | MIT, as declared by the source SPDX header |
| `lib/openzeppelin-contracts/` | OpenZeppelin Contracts v5.0.2 dependency closure, unchanged from reference | `lib/openzeppelin-contracts/LICENSE` |
| `lib/forge-std/` | forge-std v1.9.7, unchanged from reference | `lib/forge-std/LICENSE-MIT`, `lib/forge-std/LICENSE-APACHE` |
| Reference unit, property and invariant tests | Reference tests, identifiers and paths renamed | MIT, as declared by source SPDX headers |

The original `src/Ochre.sol` SHA-256 is
`c2976d1940899f54e3e7d54d5bdc64c15bf7d986a43eebdcf183ffb4ec61901c`.
The offline launch checker reverses the permitted identifier changes and removes
whitespace before comparing against the reference fingerprint. Formatting cannot
change that check. The compiler settings and remappings are retained from the
reference; the Yul optimizer sequence is intentional.

Mainnet fixture tests and deployment values were added for this assignment.
