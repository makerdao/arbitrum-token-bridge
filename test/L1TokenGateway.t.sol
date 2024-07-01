// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2024 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

import "dss-test/DssTest.sol";

import { L1TokenGateway } from "src/L1TokenGateway.sol";
import { InboxMock, BridgeMock, OutboxMock } from "test/mocks/InboxMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";

contract L1TokenGatewayTest is DssTest {

    event TokenSet(address indexed l1Address, address indexed l2Address);
    event Closed();
    event DepositInitiated(
        address l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _sequenceNumber,
        uint256 _amount
    );
    event WithdrawalFinalized(
        address l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _exitNum,
        uint256 _amount
    );
    event TxToL2(address indexed _from, address indexed _to, uint256 indexed _seqNum, bytes _data);

    GemMock l1Token;
    L1TokenGateway gateway;
    address escrow = address(0xeee);
    address counterpartGateway = address(0xccc);
    address l1Router = address(0xbbb);
    InboxMock inbox;

    function setUp() public {
        inbox = new InboxMock();
        gateway = new L1TokenGateway(counterpartGateway, l1Router, address(inbox), escrow);
        l1Token = new GemMock(1_000_000 ether);
        vm.prank(escrow); l1Token.approve(address(gateway), type(uint256).max);
        gateway.registerToken(address(l1Token), address(0xf00));
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        L1TokenGateway g = new L1TokenGateway(address(111), address(222), address(333), address(444));

        assertEq(g.isOpen(), 1);
        assertEq(g.counterpartGateway(), address(111));
        assertEq(g.l1Router(), address(222));
        assertEq(g.inbox(), address(333));
        assertEq(g.escrow(), address(444));
        assertEq(g.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(gateway), "L1TokenGateway");
    }

    function testAuthModifiers() public virtual {
        gateway.deny(address(this));

        checkModifier(address(gateway), string(abi.encodePacked("L1TokenGateway", "/not-authorized")), [
            gateway.close.selector,
            gateway.registerToken.selector
        ]);
    }

    function testErc165() public view {
        assertEq(gateway.supportsInterface(gateway.supportsInterface.selector), true);
        assertEq(gateway.supportsInterface(gateway.outboundTransferCustomRefund.selector), true);
        assertEq(gateway.supportsInterface(0xffffffff), false);
        assertEq(gateway.supportsInterface(0xbadbadba), false);
    }

    function testTokenRegistration() public {
        assertEq(gateway.l1ToL2Token(address(11)), address(0));
        assertEq(gateway.calculateL2TokenAddress(address(11)), address(0));

        vm.expectEmit(true, true, true, true);
        emit TokenSet(address(11), address(22));
        gateway.registerToken(address(11), address(22));

        assertEq(gateway.l1ToL2Token(address(11)), address(22));
        assertEq(gateway.calculateL2TokenAddress(address(11)), address(22));
    }

    function testClose() public {
        assertEq(gateway.isOpen(), 1);

        l1Token.approve(address(gateway), type(uint256).max);
        gateway.outboundTransfer(address(l1Token), address(0xb0b), 100 ether, 1_000_000, 1 gwei, abi.encode(0.1 ether, ""));

        BridgeMock bridge = BridgeMock(inbox.bridge());
        OutboxMock(bridge.activeOutbox()).setL2ToL1Sender(counterpartGateway);
        vm.prank(address(bridge)); gateway.finalizeInboundTransfer(address(l1Token), address(this), address(this), 1 ether, "");

        vm.expectEmit(true, true, true, true);
        emit Closed();
        gateway.close();

        assertEq(gateway.isOpen(), 0);
        vm.expectRevert("L1TokenGateway/closed");
        gateway.outboundTransfer(address(l1Token), address(0xb0b), 100 ether, 1_000_000, 1 gwei, abi.encode(0.1 ether, ""));

        // finalizing a transfer should still be possible
        vm.prank(address(bridge)); gateway.finalizeInboundTransfer(address(l1Token), address(this), address(this), 1 ether, "");
    }

    function testOutboundTransfer() public {
        vm.expectRevert("L1TokenGateway/invalid-token");
        gateway.outboundTransfer(address(0xbad), address(0xb0b), 100 ether, 1_000_000, 1 gwei, abi.encode(0.1 ether, ""));

        vm.expectRevert("L1TokenGateway/extra-data-not-allowed");
        gateway.outboundTransfer(address(l1Token), address(0xb0b), 100 ether, 1_000_000, 1 gwei, abi.encode(0.1 ether, "bad"));

        uint256 balanceBefore = l1Token.balanceOf(address(this));
        l1Token.approve(address(gateway), type(uint256).max);

        bytes memory outboundCalldata = gateway.getOutboundCalldata(address(l1Token), address(this), address(0xb0b), 100 ether, "");
        vm.expectEmit(true, true, true, true);
        emit TxToL2(address(this), counterpartGateway, 0, outboundCalldata);
        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(l1Token), address(this), address(0xb0b), 0, 100 ether);
        gateway.outboundTransfer(address(l1Token), address(0xb0b), 100 ether, 1_000_000, 1 gwei, abi.encode(0.1 ether, ""));

        assertEq(l1Token.balanceOf(address(this)), balanceBefore - 100 ether);
        assertEq(l1Token.balanceOf(escrow), 100 ether);

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(l1Token), address(this), address(0xb0b), 0, 100 ether);
        gateway.outboundTransferCustomRefund(address(l1Token), address(this), address(0xb0b), 100 ether, 1_000_000, 1 gwei, abi.encode(0.1 ether, ""));

        assertEq(l1Token.balanceOf(address(this)), balanceBefore - 200 ether);
        assertEq(l1Token.balanceOf(escrow), 200 ether);

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(l1Token), address(this), address(0xb0b), 0, 100 ether);
        vm.prank(l1Router); gateway.outboundTransfer(address(l1Token), address(0xb0b), 100 ether, 1_000_000, 1 gwei, abi.encode(address(this), abi.encode(0.1 ether, "")));

        assertEq(l1Token.balanceOf(address(this)), balanceBefore - 300 ether);
        assertEq(l1Token.balanceOf(escrow), 300 ether);
    }

    function testFinalizeInboundTransfer() public {
        vm.expectRevert("L1TokenGateway/not-from-bridge");
        gateway.finalizeInboundTransfer(address(l1Token), address(0xb0b), address(0xced), 1 ether, "");

        BridgeMock bridge = BridgeMock(inbox.bridge());
        vm.expectRevert("NO_SENDER");
        vm.prank(address(bridge)); gateway.finalizeInboundTransfer(address(l1Token), address(0xb0b), address(0xced), 1 ether, "");

        OutboxMock(bridge.activeOutbox()).setL2ToL1Sender(address(0xbad));
        vm.expectRevert("L1TokenGateway/only-counterpart-gateway");
        vm.prank(address(bridge)); gateway.finalizeInboundTransfer(address(l1Token), address(0xb0b), address(0xced), 1 ether, "");

        OutboxMock(bridge.activeOutbox()).setL2ToL1Sender(counterpartGateway);
        deal(address(l1Token), escrow, 100 ether, true);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalFinalized(address(l1Token), address(0xb0b), address(0xced), 0, 100 ether);
        vm.prank(address(bridge)); gateway.finalizeInboundTransfer(address(l1Token), address(0xb0b), address(0xced), 100 ether, "");

        assertEq(l1Token.balanceOf(escrow), 0);
        assertEq(l1Token.balanceOf(address(0xced)), 100 ether);
    }
}
