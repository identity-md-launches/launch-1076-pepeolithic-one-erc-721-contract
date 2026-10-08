// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Pepeolithic} from "src/Pepeolithic.sol";
import {MainnetSetup} from "test/support/MainnetSetup.sol";
import {MockCoin} from "test/Pepeolithic.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// @dev Real balance/allowance changes surround a single arbitrary callback.
/// The nested payment and the outer payment can fail independently.
contract CallbackZTO {
    error RejectedPayment();
    error InvalidPayment();

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    Pepeolithic private target;
    bytes private callbackData;
    uint256 private outerId;
    uint8 private outerResult;
    uint8 private innerResult;
    bool private entered;
    bool public nestedSuccess;
    bytes public nestedResult;
    uint256 public observedSupply;
    address public observedOwner;

    function mint(address who, uint256 amount) external {
        balanceOf[who] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function arm(Pepeolithic wall, bytes memory data, uint256 id, uint8 outer, uint8 inner) external {
        target = wall;
        callbackData = data;
        outerId = id;
        outerResult = outer;
        innerResult = inner;
        nestedSuccess = false;
        delete nestedResult;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (
            msg.sender != address(target) || to != 0x000000000000000000000000000000000000dEaD
                || balanceOf[from] < amount || allowance[from][msg.sender] < amount
        ) revert InvalidPayment();
        balanceOf[from] -= amount;
        allowance[from][msg.sender] -= amount;
        balanceOf[to] += amount;
        if (entered) return _result(innerResult);
        observedSupply = target.totalSupply();
        observedOwner = target.ownerOf(outerId);
        if (callbackData.length != 0) {
            entered = true;
            (nestedSuccess, nestedResult) = address(target).call(callbackData);
            entered = false;
        }
        return _result(outerResult);
    }

    // 0: true; 1: false after doing work; 2: revert after doing work.
    function _result(uint8 mode) private pure returns (bool) {
        if (mode == 2) revert RejectedPayment();
        return mode == 0;
    }
}

contract PepeolithicCallbacksTest is MainnetSetup {
    CallbackZTO private callbackCoin;

    function setUp() public override {
        vm.chainId(1);
        wall = _deploy(ROOT);
        CallbackZTO implementation = new CallbackZTO();
        vm.etch(ZTO, address(implementation).code);
        callbackCoin = CallbackZTO(ZTO);
        // Both mocks expose the same mint/approve/balance/allowance interface.
        zto = MockCoin(ZTO);
        _fund(BUYER, wall);
        _fund(ZTO, wall);
    }

    function testOuterFalseRollsBackSuccessfulNestedSale() public {
        _outerFailureRollsBackSales(1);
    }

    function testOuterRevertRollsBackSuccessfulNestedSale() public {
        _outerFailureRollsBackSales(2);
    }

    function _outerFailureRollsBackSales(uint8 failureMode) private {
        vm.warp(START + 2 * DAY);
        bytes memory nested = abi.encodeCall(Pepeolithic.buy, (3, 1));
        callbackCoin.arm(wall, nested, 215, failureMode, 0);
        vm.expectRevert(failureMode == 1 ? Pepeolithic.PaymentFailed.selector : CallbackZTO.RejectedPayment.selector);
        _buy(3, 1);
        assertEq(wall.totalSupply(), 2);
        assertEq(wall.roundSold(3, 1), 0);
        assertEq(wall.lastLineSale(3, 1), 0);
        assertEq(wall.openingPrice(3, 2), 2 * FLOOR);
        _missing(215);
        _missing(214);
        _uncharged(BUYER);
        _uncharged(ZTO);
        assertEq(callbackCoin.balanceOf(DEAD), 0);

        callbackCoin.arm(wall, nested, 215, 0, 0);
        vm.recordLogs();
        assertEq(_buy(3, 1), 215);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 4, "both mints and purchases emit exactly once");
        _mintAndBuyLogs(logs, 0, 215, BUYER, 2 * FLOOR);
        _mintAndBuyLogs(logs, 2, 214, ZTO, 2 * FLOOR);
        assertTrue(callbackCoin.nestedSuccess());
        assertEq(abi.decode(callbackCoin.nestedResult(), (uint256)), 214);
        assertEq(callbackCoin.observedSupply(), 3, "mint precedes the coin call");
        assertEq(callbackCoin.observedOwner(), BUYER);
        assertEq(wall.ownerOf(215), BUYER);
        assertEq(wall.ownerOf(214), ZTO);
        assertEq(wall.roundSold(3, 1), 2);
        assertEq(wall.totalSupply(), 4);
        assertEq(callbackCoin.balanceOf(DEAD), 4 * FLOOR);
        assertEq(callbackCoin.balanceOf(address(wall)), 0);
        assertEq(callbackCoin.balanceOf(ADMIN), 0);
    }

    function testCaughtNestedFalseDoesNotConsumeSaleOrPayment() public {
        _caughtNestedFailure(1);
    }

    function testCaughtNestedRevertDoesNotConsumeSaleOrPayment() public {
        _caughtNestedFailure(2);
    }

    function _caughtNestedFailure(uint8 failureMode) private {
        vm.warp(START + 2 * DAY);
        callbackCoin.arm(wall, abi.encodeCall(Pepeolithic.buy, (3, 1)), 215, 0, failureMode);
        assertEq(_buy(3, 1), 215);
        assertFalse(callbackCoin.nestedSuccess());
        assertEq(
            callbackCoin.nestedResult(),
            abi.encodeWithSelector(
                failureMode == 1 ? Pepeolithic.PaymentFailed.selector : CallbackZTO.RejectedPayment.selector
            )
        );
        _missing(214);
        _uncharged(ZTO);
        assertEq(wall.roundSold(3, 1), 1);
        assertEq(wall.totalSupply(), 3);
        assertEq(wall.lastLineSale(3, 1), 2 * FLOOR);
        assertEq(wall.openingPrice(3, 2), 4 * FLOOR);
        assertEq(callbackCoin.balanceOf(DEAD), 2 * FLOOR);
        assertEq(callbackCoin.balanceOf(BUYER), FUNDS - 2 * FLOOR);
        assertEq(callbackCoin.allowance(BUYER, address(wall)), FUNDS - 2 * FLOOR);
        callbackCoin.arm(wall, "", 214, 0, 0);
        assertEq(_buy(3, 1), 214, "failed inner purchase leaves inventory available");
    }

    function testNestedBuyCannotReuseTheFinalSaleSlot() public {
        vm.warp(START);
        callbackCoin.arm(wall, abi.encodeCall(Pepeolithic.buy, (1, 1)), 5, 0, 0);
        assertEq(_buy(1, 1), 5);
        assertFalse(callbackCoin.nestedSuccess());
        assertEq(callbackCoin.nestedResult(), abi.encodeWithSelector(Pepeolithic.SoldOut.selector));
        assertEq(wall.roundSold(1, 1), 1);
        assertEq(wall.totalSupply(), 3);
        assertEq(callbackCoin.balanceOf(DEAD), FIRST);
        _uncharged(ZTO);
    }

    function testOuterFalseRollsBackBothLeftoversAndSharedCursor() public {
        vm.warp(START + 8 * DAY);
        wall.releaseUnclaimed();
        bytes memory nested = abi.encodeCall(Pepeolithic.buyLeftover, ());
        callbackCoin.arm(wall, nested, 1, 1, 0);
        vm.expectRevert(Pepeolithic.PaymentFailed.selector);
        vm.prank(BUYER);
        wall.buyLeftover();
        assertTrue(wall.unclaimedReleased());
        assertEq(wall.nextFree(), 1);
        assertEq(wall.totalSupply(), 2);
        _missing(1);
        _missing(2);
        _uncharged(BUYER);
        _uncharged(ZTO);
        assertEq(callbackCoin.balanceOf(DEAD), 0);

        callbackCoin.arm(wall, nested, 1, 0, 0);
        vm.prank(BUYER);
        assertEq(wall.buyLeftover(), 1);
        assertTrue(callbackCoin.nestedSuccess());
        assertEq(abi.decode(callbackCoin.nestedResult(), (uint256)), 2);
        assertEq(wall.nextFree(), 3);
        assertEq(wall.ownerOf(1), BUYER);
        assertEq(wall.ownerOf(2), ZTO);
        assertEq(callbackCoin.balanceOf(DEAD), 2 * FLOOR);
        assertEq(wall.totalSupply(), 4);
    }

    function testNestedLeftoverCannotExceedFreeInventory() public {
        vm.warp(START + 8 * DAY);
        wall.releaseUnclaimed();
        // Obtain the expected free IDs from the assignment's allocation table.
        uint256[7] memory quotas = [uint256(1), 1, 2, 3, 4, 4, 4];
        uint256 count;
        for (uint256 c = 1; c <= 7; ++c) {
            for (uint256 r = 1; r <= 21; ++r) {
                uint256 k = c == 7 && r == 21 ? 5 : quotas[c - 1];
                for (uint256 slot = 1; slot <= 5 - k; ++slot) {
                    uint256 id = (c - 1) * 105 + (r - 1) * 5 + slot;
                    bytes memory nested = count == 334 ? abi.encodeCall(Pepeolithic.buyLeftover, ()) : bytes("");
                    callbackCoin.arm(wall, nested, id, 0, 0);
                    vm.prank(BUYER);
                    assertEq(wall.buyLeftover(), id);
                    ++count;
                }
            }
        }
        assertEq(count, 335);
        assertEq(wall.ownerOf(726), BUYER, "last free piece");
        assertFalse(callbackCoin.nestedSuccess());
        assertEq(callbackCoin.nestedResult(), abi.encodeWithSelector(Pepeolithic.SoldOut.selector));
        assertEq(wall.totalSupply(), 337);
        assertEq(callbackCoin.balanceOf(DEAD), 335 * FLOOR);
        _uncharged(ZTO);
        _missing(731); // Last-round slot 1 is a sale, never a leftover.
    }

    function testOuterFailureRollsBackNestedSeatClaim() public {
        wall = _deploy(keccak256(abi.encodePacked(ZTO)));
        _fund(BUYER, wall);
        vm.warp(START);
        bytes memory nested = abi.encodeCall(Pepeolithic.claimSeat, (new bytes32[](0)));
        callbackCoin.arm(wall, nested, 5, 1, 0);
        uint256 balanceBefore = callbackCoin.balanceOf(BUYER);
        vm.expectRevert(Pepeolithic.PaymentFailed.selector);
        _buy(1, 1);
        assertEq(callbackCoin.balanceOf(BUYER), balanceBefore);
        assertEq(callbackCoin.balanceOf(DEAD), 0);
        assertEq(wall.totalSupply(), 2);
        assertEq(wall.roundSold(1, 1), 0);
        assertEq(wall.nextFree(), 1);
        assertFalse(wall.claimed(ZTO));
        _missing(1);
        _missing(5);

        callbackCoin.arm(wall, nested, 5, 0, 0);
        assertEq(_buy(1, 1), 5);
        assertTrue(callbackCoin.nestedSuccess());
        assertEq(abi.decode(callbackCoin.nestedResult(), (uint256)), 1);
        assertTrue(wall.claimed(ZTO));
        assertEq(wall.ownerOf(1), ZTO);
        assertEq(wall.nextFree(), 2);
        assertEq(wall.totalSupply(), 4);
        assertEq(callbackCoin.balanceOf(DEAD), FIRST, "the nested seat remains free");
    }

    function _missing(uint256 id) private {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, id));
        wall.ownerOf(id);
    }

    function _uncharged(address who) private view {
        assertEq(callbackCoin.balanceOf(who), FUNDS);
        assertEq(callbackCoin.allowance(who, address(wall)), FUNDS);
    }

    function _mintAndBuyLogs(Vm.Log[] memory logs, uint256 offset, uint256 id, address buyer, uint256 price)
        private
        view
    {
        assertEq(logs[offset].emitter, address(wall));
        assertEq(logs[offset].topics.length, 4);
        assertEq(logs[offset].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[offset].topics[1], bytes32(0));
        assertEq(logs[offset].topics[2], bytes32(uint256(uint160(buyer))));
        assertEq(logs[offset].topics[3], bytes32(id));
        assertEq(logs[offset + 1].emitter, address(wall));
        assertEq(logs[offset + 1].topics.length, 3);
        assertEq(logs[offset + 1].topics[0], keccak256("Bought(uint256,address,uint256)"));
        assertEq(logs[offset + 1].topics[1], bytes32(id));
        assertEq(logs[offset + 1].topics[2], bytes32(uint256(uint160(buyer))));
        assertEq(abi.decode(logs[offset + 1].data, (uint256)), price);
    }
}
