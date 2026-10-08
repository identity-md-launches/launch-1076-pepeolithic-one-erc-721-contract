// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Pepeolithic} from "src/Pepeolithic.sol";
import {MainnetSetup} from "test/support/MainnetSetup.sol";

contract PepeolithicAdversarialTest is MainnetSetup {
    /// @dev This forward model never reads an opening, last sale or price from
    /// the implementation to construct its expectations. It covers all 147
    /// rounds, including cave transitions, with independently randomized actions.
    /// forge-config: default.fuzz.runs = 128
    function testFuzzFullWeekLadderAgainstForwardModel(uint256 seed) public {
        uint256 opening = FIRST;
        uint256 spent;
        uint256 minted;
        for (uint256 index; index < 147; ++index) {
            uint256 c = index / 21 + 1;
            uint256 r = index % 21 + 1;
            uint256 choice = uint256(keccak256(abi.encode(seed, index)));
            assertEq(wall.openingPrice(c, r), opening, "forward ladder opening");
            (uint256 last, uint256 paid, uint256 count) = _round(c, r, opening, choice);
            spent += paid;
            minted += count;
            assertEq(wall.lastLineSale(c, r), last, "only the last above-floor sale matters");
            assertEq(wall.roundSold(c, r), count, "failed buys cannot advance inventory");
            assertEq(wall.openingPrice(c, r), opening, "first successful buy pins the opening");
            uint256 next = opening / 2;
            if (2 * last > next) next = 2 * last;
            if (2 * FLOOR > next) next = 2 * FLOOR;
            opening = next;
        }
        assertEq(wall.totalSupply(), 2 + minted);
        assertEq(wall.balanceOf(BUYER), minted);
        assertEq(zto.balanceOf(DEAD), spent, "independent model accounts for every charge");
        assertEq(zto.balanceOf(BUYER), FUNDS - spent);
        assertEq(zto.allowance(BUYER, address(wall)), FUNDS - spent);
        assertEq(zto.balanceOf(address(wall)), 0);
        assertEq(zto.balanceOf(ADMIN), 0);
    }

    function _round(uint256 c, uint256 r, uint256 opening, uint256 choice)
        private
        returns (uint256 last, uint256 paid, uint256 count)
    {
        uint256 opens = START + (c - 1) * DAY + (r - 1) * HOUR;
        vm.warp(opens);
        assertEq(wall.priceNow(c, r), opening);
        uint256 mode = choice % 6;
        if (mode == 0) return (0, 0, 0); // Quiet, with no stored opening.
        if (mode == 5) {
            // A failure must remain quiet even though buy writes before _pay.
            uint256 beforeSupply = wall.totalSupply();
            zto.fail(true, false);
            vm.expectRevert(Pepeolithic.PaymentFailed.selector);
            _buy(c, r);
            zto.fail(false, false);
            assertEq(wall.totalSupply(), beforeSupply);
            return (0, 0, 0);
        }
        uint256[7] memory quotas = [uint256(1), 1, 2, 3, 4, 4, 4];
        uint256 quota = c == 7 && r == 21 ? 5 : quotas[c - 1];
        count = mode == 4 ? quota : 1;
        for (uint256 j; j < count; ++j) {
            uint256 elapsed;
            if (mode == 1) elapsed = HOUR; // First buy at floor still saves opening.
            else if (mode == 3) elapsed = (choice >> 8) % HOUR;
            else if (mode == 4 && quota > 1) elapsed = HOUR * j / (quota - 1);
            vm.warp(opens + elapsed);
            uint256 expectedPrice = _weightedPrice(opening, elapsed);
            assertEq(wall.priceNow(c, r), expectedPrice, "rational halving interpolation");
            assertEq(_buy(c, r), (c - 1) * 105 + 5 * r - j);
            if (expectedPrice > FLOOR) last = expectedPrice;
            paid += expectedPrice;
        }
        if (count == quota) {
            vm.expectRevert(Pepeolithic.SoldOut.selector);
            _buy(c, r);
        }
    }

    /// @dev Weighted average of adjacent integer knots, rounded up. The target
    /// subtracts a rounded-down discount with mulDiv; this oracle uses a direct
    /// rational sum. Mainnet FIRST * 2^146 * HOUR fits uint256, so no shared
    /// full-precision arithmetic library or quote helper is needed.
    function _weightedPrice(uint256 opening, uint256 elapsed) private pure returns (uint256) {
        if (elapsed >= HOUR) return FLOOR;
        uint256 segments = 1;
        while (opening / (2 ** segments) > FLOOR) ++segments;
        uint256 phase = elapsed * segments;
        uint256 knot = phase / HOUR;
        uint256 rightWeight = phase % HOUR;
        uint256 leftValue = opening / (2 ** knot);
        uint256 rightValue = opening / (2 ** (knot + 1));
        uint256 numerator = leftValue * (HOUR - rightWeight) + rightValue * rightWeight;
        uint256 price = (numerator + HOUR - 1) / HOUR;
        return price < FLOOR ? FLOOR : price;
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzInvalidCaveRejectedAcrossValidatedAPI(uint256 raw) public {
        uint256 c = raw % 2 == 0 ? 0 : bound(raw, 8, type(uint256).max);
        vm.expectRevert(Pepeolithic.InvalidCave.selector);
        wall.caveOpen(c);
        vm.expectRevert(Pepeolithic.InvalidCave.selector);
        wall.caveClose(c);
        vm.expectRevert(Pepeolithic.InvalidCave.selector);
        wall.roundOpen(c, 1);
        vm.expectRevert(Pepeolithic.InvalidCave.selector);
        wall.saleCount(c, 1);
        vm.expectRevert(Pepeolithic.InvalidCave.selector);
        wall.roundSold(c, 1);
        vm.expectRevert(Pepeolithic.InvalidCave.selector);
        wall.lastLineSale(c, 1);
        vm.expectRevert(Pepeolithic.InvalidCave.selector);
        wall.openingPrice(c, 1);
        vm.expectRevert(Pepeolithic.InvalidCave.selector);
        wall.priceNow(c, 1);
        vm.expectRevert(Pepeolithic.InvalidCave.selector);
        wall.buy(c, 1);
        vm.expectRevert(Pepeolithic.InvalidCave.selector);
        wall.sweep(c, 1);
        vm.expectRevert(Pepeolithic.InvalidCave.selector);
        vm.prank(ADMIN);
        wall.freeze(c, "ipfs://cave/");
        assertEq(wall.totalSupply(), 2);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzInvalidRoundRejectedAcrossValidatedAPI(uint256 raw, uint8 caveSeed) public {
        uint256 c = bound(caveSeed, 1, 7);
        uint256 r = raw % 2 == 0 ? 0 : bound(raw, 22, type(uint256).max);
        vm.expectRevert(Pepeolithic.InvalidRound.selector);
        wall.roundOpen(c, r);
        vm.expectRevert(Pepeolithic.InvalidRound.selector);
        wall.saleCount(c, r);
        vm.expectRevert(Pepeolithic.InvalidRound.selector);
        wall.roundSold(c, r);
        vm.expectRevert(Pepeolithic.InvalidRound.selector);
        wall.lastLineSale(c, r);
        vm.expectRevert(Pepeolithic.InvalidRound.selector);
        wall.openingPrice(c, r);
        vm.expectRevert(Pepeolithic.InvalidRound.selector);
        wall.priceNow(c, r);
        vm.expectRevert(Pepeolithic.InvalidRound.selector);
        wall.buy(c, r);
        assertEq(wall.totalSupply(), 2);
    }

    function testMaximumIndicesRevertWithCustomErrorsRatherThanArithmeticPanics() public {
        testFuzzInvalidCaveRejectedAcrossValidatedAPI(type(uint256).max);
        testFuzzInvalidRoundRejectedAcrossValidatedAPI(type(uint256).max, 7);
        vm.expectRevert(Pepeolithic.InvalidPiece.selector);
        wall.piece(type(uint256).max);
        vm.expectRevert(Pepeolithic.InvalidPiece.selector);
        wall.isSalePiece(type(uint256).max);
    }

    function testTransferredTokensDoNotTransferClaimsOrAdminAuthority() public {
        wall = _deploy(keccak256(abi.encodePacked(BUYER)));
        vm.warp(START);
        vm.prank(BUYER);
        assertEq(wall.claimSeat(new bytes32[](0)), 1);
        vm.prank(BUYER);
        wall.transferFrom(BUYER, ADAM, 1);
        vm.expectRevert(Pepeolithic.AlreadyClaimed.selector);
        vm.prank(BUYER);
        wall.claimSeat(new bytes32[](0));
        vm.expectRevert(Pepeolithic.InvalidProof.selector);
        vm.prank(ADAM);
        wall.claimSeat(new bytes32[](0));
        assertTrue(wall.claimed(BUYER));
        assertFalse(wall.claimed(ADAM));
        assertEq(wall.nextFree(), 2);
        vm.prank(ADMIN);
        wall.transferFrom(ADMIN, BUYER, 736);
        vm.prank(ADAM);
        wall.transferFrom(ADAM, BUYER, 0);
        vm.expectRevert(Pepeolithic.Unauthorized.selector);
        vm.prank(BUYER);
        wall.freeze(1, "ipfs://hijacked/");
        assertFalse(wall.frozen(1));
        vm.prank(ADMIN);
        wall.freeze(1, "ipfs://permanent/");
        assertEq(wall.tokenURI(0), "ipfs://permanent/zero.json");
        (address recipient, uint256 fee) = wall.royaltyInfo(736, 999);
        assertEq(recipient, ADMIN);
        assertEq(fee, 9);
        assertEq(wall.totalSupply(), 3);
    }

    function testDistinctCavesCanFreezeBeforeMintWithoutChangingOtherBases() public {
        vm.warp(START - 1);
        for (uint256 c = 1; c <= 7; ++c) {
            string memory base = string.concat("ipfs://cave-", vm.toString(c), "/");
            vm.prank(ADMIN);
            wall.freeze(c, base);
        }
        assertEq(wall.tokenURI(0), "ipfs://cave-1/zero.json");
        assertEq(wall.tokenURI(736), "ipfs://cave-7/one.json");
        assertEq(wall.contractURI(), "ipfs://cave-1/collection.json");
        uint256[7] memory quota = [uint256(1), 1, 2, 3, 4, 4, 4];
        for (uint256 c = 1; c <= 7; ++c) {
            vm.warp(START + c * DAY);
            assertEq(wall.sweep(c, quota[c - 1]), quota[c - 1]);
            assertEq(
                wall.tokenURI((c - 1) * 105 + 5), string.concat("ipfs://cave-", vm.toString(c), "/gathering/01.json")
            );
            vm.expectRevert(Pepeolithic.AlreadyFrozen.selector);
            vm.prank(ADMIN);
            wall.freeze(c, "ipfs://replacement/");
        }
    }
}
