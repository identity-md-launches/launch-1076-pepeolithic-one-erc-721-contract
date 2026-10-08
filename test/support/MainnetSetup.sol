// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Pepeolithic} from "src/Pepeolithic.sol";
import {MockCoin} from "test/Pepeolithic.t.sol";

/// @dev Mainnet values from the assignment. All payment code is local to the test EVM.
abstract contract MainnetSetup is Test {
    address internal constant ZTO = address(bytes20(hex"d782bdea4ef02a0bd391eb9089470c8080f0a68e"));
    address internal constant ADMIN = address(bytes20(hex"433c8a73bec1273561e4e2201649de12f20b7d58"));
    address internal constant ADAM = address(bytes20(hex"047F606fD5b2BaA5f5C6c4aB8958E45CB6B054B7"));
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    bytes32 internal constant ROOT = 0xbe96ac9140fa07013148f2dd158576ae6cbe2b4a0ce4be64782b37acc9ad0e1b;
    uint256 internal constant START = 1791810000;
    uint256 internal constant DAY = 86400;
    uint256 internal constant HOUR = 3600;
    uint256 internal constant FIRST = 1000000000000000000000000;
    uint256 internal constant FLOOR = 10000000000000000000000;
    address internal constant BUYER = address(0xA11CE);
    // Test funds cover the sum of 147 successive doublings at mainnet prices.
    uint256 internal constant FUNDS = 1 << 240;

    Pepeolithic internal wall;
    MockCoin internal zto;

    function _deploy(bytes32 root) internal returns (Pepeolithic) {
        return new Pepeolithic(
            ZTO,
            ADMIN,
            ADAM,
            root,
            START,
            DAY,
            HOUR,
            FIRST,
            FLOOR,
            bytes32("pepeolithic-base-naij"),
            bytes32("pepeolithic-moss-naij"),
            bytes32("pepeolithic-water-naij"),
            bytes32("pepeolithic-ice-naij"),
            bytes32("pepeolithic-lava-naij"),
            bytes32("pepeolithic-crystal-naij"),
            bytes32("pepeolithic-roots-naij")
        );
    }

    function setUp() public virtual {
        vm.chainId(1);
        wall = _deploy(ROOT);
        MockCoin mock = new MockCoin();
        vm.etch(ZTO, address(mock).code);
        zto = MockCoin(ZTO);
        _fund(BUYER, wall);
    }

    function _fund(address buyer, Pepeolithic target) internal {
        zto.mint(buyer, FUNDS);
        vm.prank(buyer);
        zto.approve(address(target), FUNDS);
    }

    function _buy(uint256 cave, uint256 round) internal returns (uint256) {
        vm.prank(BUYER);
        return wall.buy(cave, round);
    }
}
