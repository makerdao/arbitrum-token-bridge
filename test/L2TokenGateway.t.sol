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
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Upgrades, Options } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { L2TokenGateway } from "src/L2TokenGateway.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { ArbSysMock } from "test/mocks/ArbSysMock.sol";
import { AddressAliasHelper } from "src/arbitrum/AddressAliasHelper.sol";
import { L2TokenGatewayV2Mock } from "test/mocks/L2TokenGatewayV2Mock.sol";

contract L2TokenGatewayTest is DssTest {

    event TokenSet(address indexed l1Address, address indexed l2Address);
    event MaxWithdrawSet(address indexed l2Token, uint256 maxWithdraw);
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
    event UpgradedTo(string version);

    address ARB_SYS_ADDRESS = address(100);
    address l1Token = address(0xf00);
    GemMock l2Token;
    L2TokenGateway gateway;
    address counterpartGateway = address(0xccc);
    address l2Router = address(0xbbb);
    bool validate;

    function setUp() public {
        validate = vm.envOr("VALIDATE", false);

        L2TokenGateway imp = new L2TokenGateway(counterpartGateway, l2Router);
        assertEq(imp.counterpartGateway(), counterpartGateway);
        assertEq(imp.l2Router(), l2Router);

        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        gateway = L2TokenGateway(address(new ERC1967Proxy(address(imp), abi.encodeCall(L2TokenGateway.initialize, ()))));
        assertEq(gateway.getImplementation(), address(imp));
        assertEq(gateway.wards(address(this)), 1);
        assertEq(gateway.isOpen(), 1);
        assertEq(gateway.counterpartGateway(), counterpartGateway);
        assertEq(gateway.l2Router(), l2Router);

        l2Token = new GemMock(1_000_000 ether);
        l2Token.rely(address(gateway));
        l2Token.deny(address(this));
        gateway.registerToken(l1Token, address(l2Token));
        gateway.setMaxWithdraw(address(l2Token), 1_000_000 ether);
        vm.etch(ARB_SYS_ADDRESS, address(new ArbSysMock()).code);
    }

    function testAuth() public {
        checkAuth(address(gateway), "L2TokenGateway");
    }

    function testAuthModifiers() public virtual {
        gateway.deny(address(this));

        checkModifier(address(gateway), string(abi.encodePacked("L2TokenGateway", "/not-authorized")), [
            gateway.close.selector,
            gateway.registerToken.selector,
            gateway.setMaxWithdraw.selector,
            gateway.upgradeToAndCall.selector
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

    function testSetmaxWithdraw() public {
        assertEq(gateway.maxWithdraws(address(22)), 0);

        vm.expectEmit(true, true, true, true);
        emit MaxWithdrawSet(address(22), 123);
        gateway.setMaxWithdraw(address(22), 123);

        assertEq(gateway.maxWithdraws(address(22)), 123);
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

        vm.expectRevert("L2TokenGateway/amount-too-large");
        gateway.outboundTransfer(l1Token, address(0xb0b), 1_000_000 ether + 1, 0, 0, "");
        
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

    function testDeployWithUpgradesLib() public {
        Options memory opts;
        if (!validate) {
            opts.unsafeSkipAllChecks = true;
        } else {
            opts.unsafeAllow = 'state-variable-immutable,constructor';
        }
        opts.constructorData = abi.encode(counterpartGateway, l2Router);

        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        address proxy = Upgrades.deployUUPSProxy(
            "out/L2TokenGateway.sol/L2TokenGateway.json",
            abi.encodeCall(L2TokenGateway.initialize, ()),
            opts
        );
        assertEq(L2TokenGateway(proxy).version(), "1");
        assertEq(L2TokenGateway(proxy).wards(address(this)), 1);
    }

    function testUpgrade() public {
        address newImpl = address(new L2TokenGatewayV2Mock());
        vm.expectEmit(true, true, true, true);
        emit UpgradedTo("2");
        gateway.upgradeToAndCall(newImpl, abi.encodeCall(L2TokenGatewayV2Mock.reinitialize, ()));

        assertEq(gateway.getImplementation(), newImpl);
        assertEq(gateway.version(), "2");
        assertEq(gateway.wards(address(this)), 1); // still a ward
    }

    function testUpgradeWithUpgradesLib() public {
        address implementation1 = gateway.getImplementation();

        Options memory opts;
        if (!validate) {
            opts.unsafeSkipAllChecks = true;
        } else {
            opts.referenceContract = "out/L2TokenGateway.sol/L2TokenGateway.json";
            opts.unsafeAllow = 'constructor';
        }

        vm.expectEmit(true, true, true, true);
        emit UpgradedTo("2");
        Upgrades.upgradeProxy(
            address(gateway),
            "out/L2TokenGatewayV2Mock.sol/L2TokenGatewayV2Mock.json",
            abi.encodeCall(L2TokenGatewayV2Mock.reinitialize, ()),
            opts
        );

        address implementation2 = gateway.getImplementation();
        assertTrue(implementation1 != implementation2);
        assertEq(gateway.version(), "2");
        assertEq(gateway.wards(address(this)), 1); // still a ward
    }

    function testInitializeAgain() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        gateway.initialize();
    }

    function testInitializeDirectly() public {
        address implementation = gateway.getImplementation();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        L2TokenGateway(implementation).initialize();
    }

}
