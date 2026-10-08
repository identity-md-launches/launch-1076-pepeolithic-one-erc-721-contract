// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Pepeolithic} from "src/Pepeolithic.sol";
import {MainnetSetup} from "test/support/MainnetSetup.sol";
import {MockCoin} from "test/Pepeolithic.t.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract PepeolithicMainnetTest is MainnetSetup {
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Bought(uint256 indexed id, address indexed buyer, uint256 price);
    event Claimed(uint256 indexed id, address indexed wallet);

    function testMainnetConstructorEmptyEVMAndExactValues() public {
        vm.etch(ZTO, hex"");
        // Distinct factory caller cannot acquire any role. Even the constructor
        // recipients can contain code that reverts on every call.
        vm.etch(ADMIN, hex"60006000fd");
        vm.etch(ADAM, hex"60006000fd");
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), ADAM, 0);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), ADMIN, 736);
        vm.prank(address(0xFAC));
        Pepeolithic target = _deploy(ROOT);
        assertEq(block.chainid, 1);
        assertEq(target.name(), "Pepeolithic");
        assertEq(target.symbol(), "PEPEO");
        assertEq(target.coin(), ZTO);
        assertEq(target.coinDecimals(), 18);
        assertEq(target.dead(), DEAD);
        assertEq(target.admin(), ADMIN);
        assertEq(target.adam(), ADAM);
        assertEq(target.seatRoot(), ROOT);
        assertEq(target.startTime(), START);
        assertEq(target.caveLength(), DAY);
        assertEq(target.roundLength(), HOUR);
        assertEq(target.firstPrice(), FIRST);
        assertEq(target.floorPrice(), FLOOR);
        assertEq(target.ownerOf(0), ADAM);
        assertEq(target.ownerOf(736), ADMIN);
        assertEq(target.balanceOf(ADAM), 1);
        assertEq(target.balanceOf(ADMIN), 1);
        assertEq(target.totalSupply(), 2);
        assertLt(address(target).code.length, 9000);
        bytes32[7] memory labels = [
            bytes32("pepeolithic-base-naij"),
            bytes32("pepeolithic-moss-naij"),
            bytes32("pepeolithic-water-naij"),
            bytes32("pepeolithic-ice-naij"),
            bytes32("pepeolithic-lava-naij"),
            bytes32("pepeolithic-crystal-naij"),
            bytes32("pepeolithic-roots-naij")
        ];
        for (uint256 c = 1; c <= 7; ++c) {
            assertEq(target.labels(c), labels[c - 1]);
        }
    }

    function testMainnetEveryScheduleBoundary() public {
        for (uint256 c = 1; c <= 7; ++c) {
            assertEq(wall.caveOpen(c), START + (c - 1) * DAY);
            assertEq(wall.caveClose(c), START + c * DAY);
            for (uint256 r = 1; r <= 21; ++r) {
                uint256 opens = START + (c - 1) * DAY + (r - 1) * HOUR;
                assertEq(wall.roundOpen(c, r), opens);
                vm.warp(opens - 1);
                vm.expectRevert(Pepeolithic.NotOpen.selector);
                _buy(c, r);
                vm.warp(opens);
                assertEq(_buy(c, r), (c - 1) * 105 + r * 5);
            }
            vm.warp(START + c * DAY);
            vm.expectRevert(Pepeolithic.NotOpen.selector);
            _buy(c, 21);
            vm.expectRevert(Pepeolithic.NotOpen.selector);
            wall.priceNow(c, 21);
        }
    }

    function testMainnetHalvingFractionalKnotsAndFloorClamp() public {
        // FIRST/FLOOR = 100, so seven equal rational segments span the hour.
        // 1800 seconds is 3.5 segments; 360 seconds is 0.7 segments.
        uint256[10] memory elapsed = [uint256(0), 360, 514, 515, 1800, 3085, 3086, 3455, 3456, 3600];
        uint256[10] memory expected = [
            FIRST,
            FIRST * 65 / 100,
            FIRST - (FIRST / 2) * 3598 / 3600,
            FIRST / 2 - (FIRST / 4) * 5 / 3600,
            FIRST * 3 / 32,
            FIRST / 32 - (FIRST / 64) * 3595 / 3600,
            FIRST / 64 - (FIRST / 128) * 2 / 3600,
            FIRST / 64 - (FIRST / 128) * 2585 / 3600,
            FLOOR,
            FLOOR
        ];
        for (uint256 i; i < elapsed.length; ++i) {
            vm.warp(START + elapsed[i]);
            assertEq(wall.priceNow(1, 1), expected[i]);
        }
        vm.warp(START + DAY - 1);
        assertEq(wall.priceNow(1, 1), FLOOR);
    }

    function testMainnetHighest147RoundLadderFitsUint256() public {
        uint256 expected = FIRST;
        for (uint256 c = 1; c <= 7; ++c) {
            for (uint256 r = 1; r <= 21; ++r) {
                vm.warp(START + (c - 1) * DAY + (r - 1) * HOUR);
                assertEq(wall.openingPrice(c, r), expected);
                assertEq(wall.priceNow(c, r), expected);
                _buy(c, r);
                assertEq(wall.lastLineSale(c, r), expected);
                expected *= 2;
            }
        }
        assertEq(zto.balanceOf(DEAD), expected - FIRST);
        assertEq(zto.balanceOf(BUYER), FUNDS - (expected - FIRST));
        assertEq(zto.balanceOf(address(wall)), 0);
        assertEq(zto.balanceOf(ADMIN), 0);
        assertEq(wall.totalSupply(), 149);
    }

    function testMainnetQuietLadderAndFloorBuyIgnored() public {
        uint256[8] memory expected = [uint256(1000000), 500000, 250000, 125000, 62500, 31250, 20000, 20000];
        for (uint256 r = 1; r <= 8; ++r) {
            assertEq(wall.openingPrice(1, r), expected[r - 1] * 1e18);
        }
        vm.warp(START + HOUR);
        assertEq(wall.priceNow(1, 1), FLOOR);
        _buy(1, 1);
        assertEq(wall.lastLineSale(1, 1), 0);
        assertEq(wall.openingPrice(1, 2), FIRST / 2);
        _buy(1, 2);
        assertEq(wall.openingPrice(1, 3), FIRST);
    }

    function testMainnetLaterSaleReplacesLastPriceAndHalfOpeningBound() public {
        for (uint256 r = 1; r <= 5; ++r) {
            vm.warp(wall.roundOpen(3, r));
            _buy(3, r);
        }
        uint256 opening = wall.openingPrice(3, 5);
        assertEq(opening, 32 * FLOOR);
        vm.warp(wall.roundOpen(3, 5) + 2880);
        assertEq(wall.priceNow(3, 5), 2 * FLOOR);
        _buy(3, 5);
        assertEq(wall.lastLineSale(3, 5), 2 * FLOOR);
        assertEq(wall.openingPrice(3, 6), opening / 2);
    }

    function testMainnetAll400SalesAnd335LeftoversFinishExactly737() public {
        uint256[7] memory totals = [uint256(21), 21, 42, 63, 84, 84, 85];
        uint256[7] memory quota = [uint256(1), 1, 2, 3, 4, 4, 4];
        for (uint256 c = 1; c <= 7; ++c) {
            vm.warp(START + c * DAY - 1);
            uint256 count;
            for (uint256 r = 1; r <= 21; ++r) {
                uint256 k = c == 7 && r == 21 ? 5 : quota[c - 1];
                for (uint256 j; j < k; ++j) {
                    assertEq(_buy(c, r), (c - 1) * 105 + r * 5 - j);
                    ++count;
                }
                vm.expectRevert(Pepeolithic.SoldOut.selector);
                _buy(c, r);
            }
            assertEq(count, totals[c - 1]);
        }
        vm.warp(START + 8 * DAY - 1);
        vm.expectRevert(Pepeolithic.TooEarly.selector);
        wall.releaseUnclaimed();
        vm.warp(START + 8 * DAY);
        wall.releaseUnclaimed();
        uint256 freeCount;
        for (uint256 c = 1; c <= 7; ++c) {
            for (uint256 r = 1; r <= 21; ++r) {
                uint256 k = c == 7 && r == 21 ? 5 : quota[c - 1];
                for (uint256 slot = 1; slot <= 5 - k; ++slot) {
                    vm.prank(BUYER);
                    assertEq(wall.buyLeftover(), (c - 1) * 105 + (r - 1) * 5 + slot);
                    ++freeCount;
                }
            }
            vm.expectRevert(Pepeolithic.SoldOut.selector);
            wall.sweep(c, 105);
        }
        assertEq(freeCount, 335);
        assertEq(wall.totalSupply(), 737);
        assertEq(wall.balanceOf(BUYER), 735);
        assertEq(zto.balanceOf(DEAD), 735 * FLOOR);
        vm.expectRevert(Pepeolithic.SoldOut.selector);
        vm.prank(BUYER);
        wall.buyLeftover();
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 737));
        wall.ownerOf(737);
    }

    function testMainnetMetadataAllCavesAndPermanentFreeze() public {
        string[7] memory labels = [
            "pepeolithic-base-naij",
            "pepeolithic-moss-naij",
            "pepeolithic-water-naij",
            "pepeolithic-ice-naij",
            "pepeolithic-lava-naij",
            "pepeolithic-crystal-naij",
            "pepeolithic-roots-naij"
        ];
        assertEq(wall.tokenURI(0), "https://pepeolithic-base-naij.sites.imd.fun/zero.json");
        assertEq(wall.tokenURI(736), "https://pepeolithic-roots-naij.sites.imd.fun/one.json");
        assertEq(wall.contractURI(), "https://pepeolithic-base-naij.sites.imd.fun/collection.json");
        vm.warp(START + 8 * DAY);
        wall.releaseUnclaimed();
        for (uint256 i; i < 335; ++i) {
            vm.prank(BUYER);
            wall.buyLeftover();
        }
        for (uint256 c = 1; c <= 7; ++c) {
            wall.sweep(c, 105);
            string memory base = string.concat("https://", labels[c - 1], ".sites.imd.fun/");
            for (uint256 r = 1; r <= 21; ++r) {
                string memory rr = r < 10 ? string.concat("0", vm.toString(r)) : vm.toString(r);
                for (uint256 slot = 1; slot <= 5; ++slot) {
                    uint256 id = (c - 1) * 105 + (r - 1) * 5 + slot;
                    string memory path = slot == 5 ? "gathering/" : string.concat("line-", vm.toString(slot), "/");
                    assertEq(wall.tokenURI(id), string.concat(base, path, rr, ".json"));
                }
            }
            vm.expectRevert(Pepeolithic.Unauthorized.selector);
            vm.prank(ADAM);
            wall.freeze(c, "ipfs://cave/");
            vm.prank(ADMIN);
            wall.freeze(c, "ipfs://cave/");
            assertEq(wall.tokenURI((c - 1) * 105 + 5), "ipfs://cave/gathering/01.json");
            vm.expectRevert(Pepeolithic.AlreadyFrozen.selector);
            vm.prank(ADMIN);
            wall.freeze(c, "ipfs://replacement/");
        }
        assertEq(wall.tokenURI(0), "ipfs://cave/zero.json");
        assertEq(wall.tokenURI(736), "ipfs://cave/one.json");
        assertEq(wall.contractURI(), "ipfs://cave/collection.json");
    }

    function testMainnetSortedProofClaimAndRelease() public {
        // A known local tree tests membership; no production-root proof was supplied.
        bytes32 a = keccak256(abi.encodePacked(BUYER));
        bytes32 b = keccak256(abi.encodePacked(ADAM));
        bytes32 root = a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
        Pepeolithic target = _deploy(root);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = b;
        vm.warp(START - 1);
        vm.expectRevert(Pepeolithic.TooEarly.selector);
        vm.prank(BUYER);
        target.claimSeat(proof);
        vm.warp(START);
        vm.expectRevert(Pepeolithic.InvalidProof.selector);
        vm.prank(ADMIN);
        target.claimSeat(proof);
        vm.expectEmit(true, true, false, true, address(target));
        emit Claimed(1, BUYER);
        vm.prank(BUYER);
        assertEq(target.claimSeat(proof), 1);
        vm.expectRevert(Pepeolithic.AlreadyClaimed.selector);
        vm.prank(BUYER);
        target.claimSeat(proof);
        vm.warp(START + 8 * DAY);
        target.releaseUnclaimed();
        proof[0] = a;
        vm.expectRevert(Pepeolithic.SeatsReleased.selector);
        vm.prank(ADAM);
        target.claimSeat(proof);
        assertEq(zto.balanceOf(DEAD), 0);
    }

    function testMainnetPaymentRollbackAndEvents() public {
        vm.warp(START);
        zto.fail(true, false);
        vm.expectRevert(Pepeolithic.PaymentFailed.selector);
        _buy(1, 1);
        assertEq(wall.totalSupply(), 2);
        assertEq(wall.roundSold(1, 1), 0);
        assertEq(wall.lastLineSale(1, 1), 0);
        assertEq(zto.balanceOf(BUYER), FUNDS);
        assertEq(zto.allowance(BUYER, address(wall)), FUNDS);
        assertEq(zto.balanceOf(DEAD), 0);
        zto.fail(false, true);
        vm.expectRevert(MockCoin.CoinReverted.selector);
        _buy(1, 1);
        zto.fail(false, false);
        vm.expectEmit(true, true, false, true, address(wall));
        emit Bought(5, BUYER, FIRST);
        _buy(1, 1);
        assertEq(zto.lastTo(), DEAD);
        assertEq(zto.lastFrom(), BUYER);
        assertEq(zto.lastAmount(), FIRST);
    }
}
