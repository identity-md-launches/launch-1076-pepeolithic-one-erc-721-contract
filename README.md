# Pepeolithic

Pepeolithic is one non-upgradeable ERC-721 application for 737 pieces of a wall painted live by workers. The Ethereum mainnet launch uses existing ZTO; it creates no coin, pool, proxy, treasury, owner, or pause mechanism. Purchases transfer ZTO directly from the buyer to the dead address. Minting and all state updates precede that call, and a false return or revert rolls back the entire purchase.

## Build and checks

```sh
forge build
forge test
forge fmt --check
python3 script/check_launch.py
```

The compiler is pinned to Solidity **0.8.26**, targeting Cancun, with `via_ir = true`, `optimizer_runs = 1`, and `bytecode_hash = "none"`. The Yul sequence is the 0.8.26 default with FunctionSpecializer (`F`) omitted. This keeps the application at **8,285 deployed bytes**, below 9,000, and prevents compiler-emitted event-topic data from failing the launcher's literal opcode scan. A test repeats the protected scan, including its treatment of data after executable code. No FFI or filesystem cheatcode permissions are enabled.

All Solidity dependencies are ordinary vendored files: OpenZeppelin Contracts **v5.0.2** (the unmodified ERC-721 dependency closure, including Math) and forge-std **v1.9.7**, with their licenses under `lib/`. Builds need no package download once the pinned compiler is installed. There are no submodules. `script/check_launch.py` uses only Python's standard library; it checks the manifest against the compiled constructor ABI, exact mainnet arguments, generated label encoding, size, and forbidden opcodes.

Mainnet tests use a local mock installed at the configured ZTO address. The inherited reference suites additionally exercise alternate constructor parameters and a compressed schedule; these test fixtures are not deployment values. They cover every piece and sale allocation, all 335 seat claims using sorted-pair Merkle proofs, complete issuance of 737 tokens, sale boundaries, halving/interpolation, ladder transitions, floor purchases, payment failures, reentry, sweep batching, release, metadata, royalties, transfers, and events. Tests do not read or modify environment variables or use a fork. Slither and Mythril were not available in the worker environment; these checks are not an independent security audit.

## Reference fidelity

Production source and vendored dependencies come from [swarm launch 928, commit b0923044ec165ae0a94a70ea58793153692a5a93](https://github.com/identity-md-launches/launch-928-ochre-one-erc-721-contract/tree/b0923044ec165ae0a94a70ea58793153692a5a93). Only the collection and interface identifiers, name (`Pepeolithic`), symbol (`PEPEO`), and deployment values change. `script/check_launch.py` verifies the normalized source fingerprint against that pinned reference, as well as the manifest. Dependencies and licenses are ordinary files; see [DEPENDENCIES.md](DEPENDENCIES.md).

The exact reference uses the getter `coin()` for ZTO. Its per-round storage contains `opening`, `lastLineSale`, and `sold`; nonzero `lastLineSale` represents the presence of line sales. It does not keep a separate `lineSales` counter. This representation is retained to satisfy the explicit exact-reference requirement. The ladder ignores floor purchases because they never update `lastLineSale`.

## Deployment handoff

`launch.json` deploys **only Pepeolithic** on **Ethereum mainnet, chain ID 1**, through the project's deployment service. Its constructor takes **exactly 16 static arguments**. The dead address and coin decimals are constants, keeping the manifest within its 16-argument limit. Constructors are nonpayable and make no external calls, including metadata or receiver calls; deployment therefore also works in an empty EVM. Neither the factory nor `msg.sender` receives administrative authority.

| Position | Argument | Mainnet value |
| --- | --- | --- |
| 1 | `coin_` | `0xd782bdea4ef02a0bd391eb9089470c8080f0a68e` |
| 2 | `admin_` | `0x433c8a73bec1273561e4e2201649de12f20b7d58` |
| 3 | `adam_` | `0x047F606fD5b2BaA5f5C6c4aB8958E45CB6B054B7` |
| 4 | `seatRoot_` | `0xbe96ac9140fa07013148f2dd158576ae6cbe2b4a0ce4be64782b37acc9ad0e1b` |
| 5 | `startTime_` | `1791810000` Unix seconds (October 12, 2026, 13:00 UTC / 09:00 New York) |
| 6 | `caveLength_` | `86400` seconds (1 day) |
| 7 | `roundLength_` | `3600` seconds (1 hour) |
| 8 | `firstPrice_` | `1000000000000000000000000` ZTO base units (1,000,000 ZTO) |
| 9 | `floorPrice_` | `10000000000000000000000` ZTO base units (10,000 ZTO) |
| 10–16 | `label1` … `label7` | `pepeolithic-base-naij`, `pepeolithic-moss-naij`, `pepeolithic-water-naij`, `pepeolithic-ice-naij`, `pepeolithic-lava-naij`, `pepeolithic-crystal-naij`, `pepeolithic-roots-naij` |

Labels are ASCII bytes32 values, right-padded with zeros. The manifest contains their byte encoding; the offline checker verifies it. `dead` is always `0x000000000000000000000000000000000000dEaD`, and `coinDecimals` is always 18. Configuration has public getters and no setters. It occupies storage to meet the runtime-size budget. Prices are constructor arguments, not code constants. Validation requires nonzero coin/admin/Adam/root, nonempty correctly padded ASCII labels, positive floor and round length, `firstPrice >= 2 * floorPrice`, `21 * roundLength <= caveLength`, and representable schedule arithmetic.

This repository is the reviewable deployment handoff; no wallet keys were read and no transaction was broadcast. The deployer must confirm chain ID, the existing ZTO contract, the supplied root, parameters, and recipients before deployment, then publish the confirmed address and verify the source. The constructor deliberately does not probe the coin or enforce a chain ID. Live ZTO behavior is an external dependency; local tests verify the specified bool-returning payment interface.

## After launch

The deployer selects **chain ID 1**, verifies the static arguments and existing ZTO contract, then publishes the confirmed deployment address and verifies its source. This assignment prepares that handoff; it does not broadcast a transaction. No setup setter or initialization is needed. The supplied ZTO address and root are requester inputs; live ZTO behavior and the production proof list have not been independently verified here.

The seat organizer must publish proofs for the supplied root. Proof distribution does not change on-chain configuration; successful proof tests use deterministic local trees because the production wallet list was not supplied. Site operators publish each cave's JSON and assets at its assigned label. Admin publishes and checks permanent assets, then calls `freeze(c,base)` once per cave. Anyone can sweep closed caves in batches and call `releaseUnclaimed()` from October 20, 2026 at 13:00 UTC. Full issuance needs these calls and buyers or claimants for every free piece. The last cave closes October 19 at 13:00 UTC.

Admin's metadata privilege, royalty recipient, swept-piece recipient, Adam, schedule, prices, root and coin address cannot be changed. Admin key loss therefore prevents future freezes. Purchases rely on ZTO honoring its bool-returning `transferFrom`; a token pause, blacklist or failed allowance blocks that purchase and rolls it back. No oracle or randomness is used. An independent contributor's adversarial review remains a deployment responsibility.

## Pieces and time

ID **0** is Zero, minted to Adam in the constructor. ID **736** is One, minted to admin. For IDs 1–735, `piece(id)` returns:

```text
cave  = (id - 1) / 105 + 1
round = ((id - 1) % 105) / 5 + 1
slot  = (id - 1) % 5 + 1
```

Slots 1–4 are lines; slot 5 is the gathering. Zero and One map to caves 1 and 7 with round/slot zero. No public mint or burn exists, and `totalSupply()` counts all minted pieces.

Cave `c` opens at `startTime + (c-1)*caveLength`. Its close is exclusive for buying and inclusive for sweeping. Round `r` opens at `caveOpen(c) + (r-1)*roundLength`. All 21 rounds fit within their cave; older rounds remain independently purchasable at their floor until the cave closes.

| Cave | Sale pieces per round | Cave sale total | Seat total |
| --- | --- | --- | --- |
| 1 | 1 | 21 | 84 |
| 2 | 1 | 21 | 84 |
| 3 | 2 | 42 | 63 |
| 4 | 3 | 63 | 42 |
| 5 | 4 | 84 | 21 |
| 6 | 4 | 84 | 21 |
| 7 | 4; 5 in round 21 | 85 | 20 |
| Total | | **400** | **335** |

`buy(c,r)` allocates the next sale piece in slot order **5, 4, 3, 2, 1**, up to the round's quota. Buyers approve Pepeolithic on ZTO first. Every charge uses `transferFrom(buyer, dead, price)` and requires a true returned bool. There is no wallet limit, native-ETH payment, refund, payout, fee recipient, or withdrawal path. Payments never enter Pepeolithic. Unsolicited transfers to the application have no recovery function.

## Halving price and ladder

Each round starts at its own opening. Let `K` be the smallest integer for which `opening / 2^K <= floor`. Its line consists of `K` equal-duration segments over one `roundLength`, joining the integer-halved values. Prices are clamped at the floor during interpolation and stay there after the line.

Segment boundaries are rational, not rounded seconds: with elapsed time `t < roundLength`, compute segment `s = floor(t*K/roundLength)` and remainder `m = (t*K) % roundLength`. The price is:

```text
high  = opening >> s
low   = opening >> (s + 1)
price = max(floorPrice, high - floor((high - low) * m / roundLength))
```

Full-precision multiplication/division avoids intermediate overflow and divide-before-multiply precision loss. Sub-base-unit discounts truncate downward, so the integer price rounds upward. For example, the first round has seven segments: its 1,000,000 ZTO opening falls to 650,000 ZTO at 360 seconds, 93,750 ZTO at 1,800 seconds, and reaches the 10,000 ZTO floor at 3,456 seconds (before the one-hour line ends). Fractional segment boundaries are preserved even though block timestamps are integer seconds.

The opening of cave 1 round 1 is `firstPrice`. Every subsequent round follows the previous round in week order:

- With a prior line sale: `max(2 * prior.lastLineSale, prior.opening / 2, 2 * floorPrice)`.
- Without one: `max(prior.opening / 2, 2 * floorPrice)`.

Only purchases strictly above the floor set `lastLineSale`. A round's first purchase stores its opening, including a first purchase at the floor. Unbought rounds derive their opening by walking backward to a stored opening and halving through quiet rounds, bounded by 147 rounds. The calculation also crosses cave boundaries. There is no economic cap; Solidity's uint256 range is the arithmetic limit. The supplied mainnet parameters fit that range even with a doubling at every one of the 147 rounds; a test executes that complete sequence.

`openingPrice`, `roundSold`, and `lastLineSale` expose the round state; `priceNow` rejects unopened rounds or closed caves. `roundSold` counts purchases, not swept pieces. A quote is not a price reservation: a predecessor's line sale can change an unbought round's opening before a transaction executes. An exact ZTO allowance can bound the charge.

## Seats, leftovers, and sweeps

`claimSeat(proof)` is available from `startTime`. Its leaf is `keccak256(abi.encodePacked(wallet))`; each proof step hashes its two bytes32 children in ascending order. This is a single address hash, not a double-hashed standard-tree leaf. Each wallet may claim once. Claims take free pieces in increasing ID order across all seven caves, without waiting for later caves to open. A bad proof or duplicate claim reverts.

At `startTime + 8*caveLength`, anyone may call `releaseUnclaimed()` once. Claims remain available until that transaction happens. Afterwards, claims stop and anyone can repeatedly call `buyLeftover()` to buy the next free piece at `floorPrice`, with no time window or wallet limit. Claims and leftovers share one cursor and cannot mint the same piece twice.

After a cave closes, anyone may call `sweep(c,max)` with positive `max`. It mints up to that many unsold sale pieces to admin in increasing ID order. It skips every seat piece and every already-minted sale piece. Each cave has a persistent cursor for batching; a call with no eligible pieces reverts. Sold pieces stay excluded even if transferred to another wallet. Full issuance depends on callers sweeping unsold sales and on seats being claimed or remaining seats being purchased; expiry does not mint automatically.

## Metadata and rights

Before a cave is frozen, its base is `https://<label>.sites.imd.fun/`. Suffixes are `gathering/01.json` … `gathering/21.json` or `line-<slot>/01.json` … `line-<slot>/21.json`. Zero uses cave 1's `zero.json`; One uses cave 7's `one.json`. `tokenURI` rejects unminted IDs. `contractURI()` uses cave 1's base plus `collection.json`.

Only admin may call `freeze(c,base)`, once per cave, including before the cave opens. The base must be nonempty and end with `/`, for example `ipfs://<cid>/`. Freezing replaces that cave's base permanently. Cave 1's freeze also fixes the collection base. The contract does not check availability or content: admin must publish and verify every file first. HTTP content can change before freezing, and a frozen HTTP URL alone does not make its content immutable. Choose content-addressed storage when permanence is intended.

The fixed ERC-2981 royalty is `(admin, salePrice / 100)` for every ID, with integer rounding down and no setter. This is a royalty signal; marketplaces decide whether to pay it. ERC-165, ERC-721, ERC-721Metadata, and ERC-2981 are supported. ERC-721 Enumerable is not implemented.

All issuance uses `_mint` with no receiver callback. To honor the brief's prohibition on callbacks anywhere, both `safeTransferFrom` overloads reject recipients that currently have code; `transferFrom` remains available for deliberate contract custody. This is an intentional restriction on usual ERC-721 receiver interoperability. Contract wallets can buy or claim directly without implementing a receiver. Standard owner balances, token approvals, operator approvals, transfer events, and zero-address protections come from OpenZeppelin.

The contract emits `Bought(id,buyer,price)`, `Claimed(id,wallet)`, and `Swept(id)` alongside ERC-721 `Transfer` events. ID and wallet fields are indexed. `Frozen(cave,base)` and `UnclaimedReleased()` record the two permanent operational transitions. Admin's only application privilege is metadata freezing; admin also receives swept pieces and the fixed royalty. There are no changeable roles, prices, schedule, root, payment destination, or emergency controls.
