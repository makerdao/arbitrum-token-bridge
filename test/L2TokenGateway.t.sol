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

import { L2TokenGateway } from "src/L2TokenGateway.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { ArbSysMock } from "test/mocks/ArbSysMock.sol";
import { AddressAliasHelper } from "src/arbitrum/AddressAliasHelper.sol";

contract L2TokenGatewayTest is DssTest {

    event TokenSet(address indexed l1Address, address indexed l2Address);
    event Closed();
        event DepositFinalized(
        address indexed l1Token,
        address indexed _from,
        address indexed _to,
        uint256 _amount
    );
    event WithdrawalInitiated(
        address l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _l2ToL1Id,
        uint256 _exitNum,
        uint256 _amount
    );
    event TxToL1(address indexed _from, address indexed _to, uint256 indexed _id, bytes _data);

    address ARB_SYS_ADDRESS = address(100);
    address l1Token = address(0xf00);
    GemMock l2Token;
    L2TokenGateway gateway;
    address counterpartGateway = address(0xccc);
    address l2Router = address(0xbbb);

    function setUp() public {
        gateway = new L2TokenGateway(counterpartGateway, l2Router);
        l2Token = new GemMock(1_000_000 ether);
        l2Token.rely(address(gateway));
        l2Token.deny(address(this));
        gateway.registerToken(l1Token, address(l2Token));
        vm.etch(ARB_SYS_ADDRESS, address(new ArbSysMock()).code);
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        L2TokenGateway g = new L2TokenGateway(address(111), address(222));

        assertEq(g.isOpen(), 1);
        assertEq(g.counterpartGateway(), address(111));
        assertEq(g.l2Router(), address(222));
        assertEq(g.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(gateway), "L2TokenGateway");
    }

    function testAuthModifiers() public virtual {
        gateway.deny(address(this));

        checkModifier(address(gateway), string(abi.encodePacked("L2TokenGateway", "/not-authorized")), [
            gateway.close.selector,
            gateway.registerToken.selector
        ]);
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

        l2Token.approve(address(gateway), type(uint256).max);
        gateway.outboundTransfer(l1Token, address(0xb0b), 100 ether, 0, 0, "");

        address offsetCounterpart = AddressAliasHelper.applyL1ToL2Alias(counterpartGateway);
        vm.prank(offsetCounterpart); gateway.finalizeInboundTransfer(l1Token, address(this), address(this), 1 ether, "");

        vm.expectEmit(true, true, true, true);
        emit Closed();
        gateway.close();

        assertEq(gateway.isOpen(), 0);
        vm.expectRevert("L2TokenGateway/closed");
        gateway.outboundTransfer(l1Token, address(0xb0b), 100 ether, 0, 0, "");

        // finalizing a transfer should still be possible
        vm.prank(offsetCounterpart); gateway.finalizeInboundTransfer(l1Token, address(this), address(this), 1 ether, "");
    }

    function testOutboundTransfer() public {
        vm.expectRevert("L2TokenGateway/no-value-allowed");
        gateway.outboundTransfer{value: 1 ether}(l1Token, address(0xb0b), 100 ether, 0, 0, "");

        vm.expectRevert("L2TokenGateway/invalid-token");
        gateway.outboundTransfer(address(0xbad), address(0xb0b), 100 ether, 0, 0, "");
        
        vm.expectRevert("L2TokenGateway/extra-data-not-allowed");
        gateway.outboundTransfer(l1Token, address(0xb0b), 100 ether, 0, 0, "bad");

        l2Token.approve(address(gateway), type(uint256).max);
        uint256 balanceBefore = l2Token.balanceOf(address(this));
        uint256 supplyBefore = l2Token.totalSupply();

        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1Token, address(this), address(0xb0b), 0, 0, 100 ether);
        gateway.outboundTransfer(l1Token, address(0xb0b), 100 ether, 0, 0, "");

        assertEq(l2Token.balanceOf(address(this)), balanceBefore - 100 ether);
        assertEq(l2Token.totalSupply(), supplyBefore - 100 ether);

        bytes memory outboundCalldata = gateway.getOutboundCalldata(address(l1Token), address(this), address(0xb0b), 100 ether, "");
        vm.expectEmit(true, true, true, true);
        emit TxToL1(address(this), counterpartGateway, 0, outboundCalldata);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1Token, address(this), address(0xb0b), 0, 0, 100 ether);
        gateway.outboundTransfer(l1Token, address(0xb0b), 100 ether, "");

        assertEq(l2Token.balanceOf(address(this)), balanceBefore - 200 ether);
        assertEq(l2Token.totalSupply(), supplyBefore - 200 ether);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1Token, address(this), address(0xb0b), 0, 0, 100 ether);
        vm.prank(l2Router); gateway.outboundTransfer(l1Token, address(0xb0b), 100 ether, abi.encode(address(this), ""));

        assertEq(l2Token.balanceOf(address(this)), balanceBefore - 300 ether);
        assertEq(l2Token.totalSupply(), supplyBefore - 300 ether);
    }

    function testFinalizeInboundTransfer() public {
        vm.expectRevert("L2TokenGateway/only-counterpart-gateway");
        gateway.finalizeInboundTransfer(l1Token, address(0xb0b), address(0xced), 1 ether, "");

        vm.expectRevert("L2TokenGateway/invalid-token");
        address offsetCounterpart = AddressAliasHelper.applyL1ToL2Alias(counterpartGateway);
        vm.prank(offsetCounterpart); gateway.finalizeInboundTransfer(address(0), address(0xb0b), address(0xced), 100 ether, "");

        uint256 balanceBefore = l2Token.balanceOf(address(0xced));
        uint256 supplyBefore = l2Token.totalSupply();

        vm.expectEmit(true, true, true, true);
        emit DepositFinalized(address(l1Token), address(0xb0b), address(0xced), 100 ether);
        vm.prank(offsetCounterpart); gateway.finalizeInboundTransfer(l1Token, address(0xb0b), address(0xced), 100 ether, "");
        
        assertEq(l2Token.balanceOf(address(0xced)), balanceBefore + 100 ether);
        assertEq(l2Token.totalSupply(), supplyBefore + 100 ether);
    }

}
