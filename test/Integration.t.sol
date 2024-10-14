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

import { Domain } from "dss-test/domains/Domain.sol";
import { ArbitrumDomain } from "dss-test/domains/ArbitrumDomain.sol";
import { TokenGatewayDeploy } from "deploy/TokenGatewayDeploy.sol";
import { L1TokenGatewayInstance } from "deploy/L1TokenGatewayInstance.sol";
import { L2TokenGatewayInstance } from "deploy/L2TokenGatewayInstance.sol";
import { L2TokenGatewaySpell } from "deploy/L2TokenGatewaySpell.sol";
import { TokenGatewayInit, GatewaysConfig, MessageParams } from "deploy/TokenGatewayInit.sol";
import { L1TokenGateway } from "src/L1TokenGateway.sol";
import { L2TokenGateway } from "src/L2TokenGateway.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { L1TokenGatewayV2Mock } from "test/mocks/L1TokenGatewayV2Mock.sol";
import { L2TokenGatewayV2Mock } from "test/mocks/L2TokenGatewayV2Mock.sol";

interface L1RelayLike {
    function l2GovernanceRelay() external view returns (address);
    function relay(
        address target,
        bytes calldata targetData,
        uint256 l1CallValue,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 maxSubmissionCost
    ) external payable;
}

interface L1RouterLike {
    function setGateways(
        address[] memory tokens,
        address[] memory gateways,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 maxSubmissionCost
    ) external payable returns (uint256);
    function owner() external view returns (address);
    function getGateway(address) external view returns (address);
    function counterpartGateway() external view returns (address);
}

contract IntegrationTest is DssTest {

    Domain l1Domain;
    ArbitrumDomain l2Domain;

    // L1-side
    DssInstance dss;
    address PAUSE_PROXY;
    address ESCROW;
    address L1_GOV_RELAY;
    GemMock l1Token;
    L1TokenGateway l1Gateway;
    address INBOX;
    address L1_ROUTER;

    // L2-side
    address L2_GOV_RELAY;
    GemMock l2Token;
    L2TokenGateway l2Gateway;
    address l2Spell;
    address L2_ROUTER;

    function setUp() public {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1"); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");

        l1Domain = new Domain(config, getChain("mainnet"));
        l1Domain.selectFork();
        l1Domain.loadDssFromChainlog();
        dss = l1Domain.dss();
        PAUSE_PROXY  = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
        ESCROW       = dss.chainlog.getAddress("ARBITRUM_ESCROW");
        L1_GOV_RELAY = dss.chainlog.getAddress("ARBITRUM_GOV_RELAY");
        L2_GOV_RELAY = L1RelayLike(L1_GOV_RELAY).l2GovernanceRelay();
        vm.label(address(PAUSE_PROXY),  "PAUSE_PROXY");
        vm.label(address(ESCROW),       "ESCROW");
        vm.label(address(L1_GOV_RELAY), "L1_GOV_RELAY");
        vm.label(address(L2_GOV_RELAY), "L2_GOV_RELAY");

        l2Domain = new ArbitrumDomain(config, getChain("arbitrum_one"), l1Domain);
        INBOX = l2Domain.readConfigAddress("inbox");
        vm.label(INBOX, "INBOX");
        L1_ROUTER = l2Domain.readConfigAddress("l1Router");
        vm.label(L1_ROUTER, "L1_ROUTER");
        L2_ROUTER = L1RouterLike(L1_ROUTER).counterpartGateway();
        vm.label(L2_ROUTER, "L2_ROUTER");

        address l1Gateway_ = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 4); // foundry increments a global nonce across domains
        l2Domain.selectFork();
        L2TokenGatewayInstance memory l2GatewayInstance = TokenGatewayDeploy.deployL2Gateway({
            deployer:  address(this),
            owner:     L2_GOV_RELAY,
            l1Gateway: l1Gateway_, 
            l2Router:  L2_ROUTER
        });
        l2Gateway = L2TokenGateway(l2GatewayInstance.gateway);
        l2Spell = l2GatewayInstance.spell;
        assertEq(address(L2TokenGatewaySpell(l2Spell).l2Gateway()), address(l2Gateway));
        assertEq(l2Gateway.version(), "1");
        assertEq(l2Gateway.getImplementation(), l2GatewayInstance.gatewayImp);

        l1Domain.selectFork();
        L1TokenGatewayInstance memory l1GatewayInstance = TokenGatewayDeploy.deployL1Gateway({
            deployer:  address(this),
            owner:     PAUSE_PROXY,
            l2Gateway: address(l2Gateway), 
            l1Router:  L1_ROUTER,
            inbox:     INBOX
        });
        l1Gateway = L1TokenGateway(l1GatewayInstance.gateway);
        assertEq(address(l1Gateway), l1Gateway_);
        assertEq(l1Gateway.version(), "1");
        assertEq(l1Gateway.getImplementation(), l1GatewayInstance.gatewayImp);

        l1Token = new GemMock(100 ether);
        vm.label(address(l1Token), "l1Token");

        l2Domain.selectFork();
        l2Token = new GemMock(0);
        l2Token.rely(L2_GOV_RELAY);
        l2Token.deny(address(this));
        vm.label(address(l2Token), "l2Token");

        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(l1Token);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = address(l2Token);
        uint256[] memory maxWithdraws = new uint256[](1);
        maxWithdraws[0] = 10_000_000 ether;
        MessageParams memory xchainMsg = MessageParams({
            gasPriceBid:       0.1 gwei,
            maxGas:            300_000,
            maxSubmissionCost: 0.01 ether
        });
        GatewaysConfig memory cfg = GatewaysConfig({
            l1Router:     L1_ROUTER,
            inbox:        INBOX,
            l1Tokens:     l1Tokens,
            l2Tokens:     l2Tokens,
            maxWithdraws: maxWithdraws,
            xchainMsg:    xchainMsg
        });

        l1Domain.selectFork();
        vm.startPrank(PAUSE_PROXY);
        TokenGatewayInit.initGateways(dss, l1GatewayInstance, l2GatewayInstance, cfg);
        vm.stopPrank();

        // test L1 side of initGateways
        assertEq(l1Token.allowance(ESCROW, l1Gateway_), type(uint256).max);
        assertEq(l1Gateway.l1ToL2Token(address(l1Token)), address(l2Token));
        assertEq(dss.chainlog.getAddress("ARBITRUM_TOKEN_BRIDGE"), address(l1Gateway));
        assertEq(dss.chainlog.getAddress("ARBITRUM_TOKEN_BRIDGE_IMP"), l1GatewayInstance.gatewayImp);

        l2Domain.relayFromHost(true);

        // test L2 side of initGateways
        assertEq(l2Gateway.l1ToL2Token(address(l1Token)), address(l2Token));
        assertEq(l2Gateway.maxWithdraws(address(l2Token)), 10_000_000 ether);
        assertEq(l2Token.wards(address(l2Gateway)), 1);

        // Register L1 & L2 gateways in L1 & L2 routers
        l1Domain.selectFork();
        address[] memory l1Gateways = new address[](1);
        l1Gateways[0] = address(l1Gateway);
        address routerOwner = L1RouterLike(L1_ROUTER).owner();
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 maxGas = 1_000_000;
        uint256 gasPriceBid = 1 gwei;
        uint256 value = maxSubmissionCost + maxGas * gasPriceBid;
        vm.deal(routerOwner, value);
        vm.prank(routerOwner); L1RouterLike(L1_ROUTER).setGateways{value: value}({
            tokens:            l1Tokens,
            gateways:          l1Gateways,
            maxGas:            maxGas,
            gasPriceBid:       gasPriceBid,
            maxSubmissionCost: maxSubmissionCost
        });
        assertEq(L1RouterLike(L1_ROUTER).getGateway(address(l1Token)), address(l1Gateway));
        l2Domain.relayFromHost(false);
    }

    function _deposit(address target) internal {
        l1Token.approve(address(l1Gateway), 100 ether);
        uint256 escrowBefore = l1Token.balanceOf(ESCROW);

        uint256 maxSubmissionCost = 0.1 ether;
        uint256 maxGas = 1_000_000;
        uint256 gasPriceBid = 1 gwei;
        uint256 value = maxSubmissionCost + maxGas * gasPriceBid;
        L1TokenGateway(target).outboundTransferCustomRefund{value: value}(
            address(l1Token),
            address(0x7ef),
            address(0xb0b),
            50 ether,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, "")
        );
        L1TokenGateway(target).outboundTransfer{value: value}(
            address(l1Token),
            address(0xb0b),
            50 ether,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, "")
        );

        assertEq(l1Token.balanceOf(ESCROW), escrowBefore + 100 ether);
        l2Domain.relayFromHost(true);

        assertEq(l2Token.balanceOf(address(0xb0b)), 100 ether);
    }

    function testDeposit() public {
        _deposit(address(l1Gateway));
    }

    function testDepositViaRouter() public {
        _deposit(L1_ROUTER);
    }

    function _withdraw(address target) internal {
        _deposit(address(l1Gateway));

        vm.startPrank(address(0xb0b));
        l2Token.approve(address(l2Gateway), 100 ether);
        L2TokenGateway(target).outboundTransfer(
            address(l1Token),
            address(0xced),
            50 ether,
            0,
            0,
            ""
        );
        L2TokenGateway(target).outboundTransfer(
            address(l1Token),
            address(0xced),
            50 ether,
            ""
        );
        vm.stopPrank();

        assertEq(l2Token.balanceOf(address(0xb0b)), 0);
        l2Domain.relayToHost(true);

        assertEq(l1Token.balanceOf(address(0xced)), 100 ether);
    }

    function testWithdraw() public {
        _withdraw(address(l2Gateway));
    }

    function testWithdrawViaRouter() public {
        _withdraw(L2_ROUTER);
    }

    function testUpgrade() public {
        l2Domain.selectFork();
        address newL2Imp = address(new L2TokenGatewayV2Mock());
        l1Domain.selectFork();
        address newL1Imp = address(new L1TokenGatewayV2Mock());

        vm.startPrank(PAUSE_PROXY);
        l1Gateway.upgradeToAndCall(newL1Imp, abi.encodeCall(L1TokenGatewayV2Mock.reinitialize, ()));
        vm.stopPrank();

        assertEq(l1Gateway.getImplementation(), newL1Imp);
        assertEq(l1Gateway.version(), "2");
        assertEq(l1Gateway.wards(PAUSE_PROXY), 1); // still a ward

        vm.startPrank(PAUSE_PROXY);
        L1RelayLike(L1_GOV_RELAY).relay({
            target:     l2Spell,
            targetData: abi.encodeCall(L2TokenGatewaySpell.upgradeToAndCall, (
                newL2Imp,
                abi.encodeCall(L2TokenGatewayV2Mock.reinitialize, ())
            )),
            l1CallValue:       0.01 ether + 300_000 * 0.1 gwei,
            gasPriceBid:       0.1 gwei,
            maxGas:            300_000,
            maxSubmissionCost: 0.01 ether
        });
        vm.stopPrank();

        l2Domain.relayFromHost(true);

        assertEq(l2Gateway.getImplementation(), newL2Imp);
        assertEq(l2Gateway.version(), "2");
        assertEq(l2Gateway.wards(L2_GOV_RELAY), 1); // still a ward
    }
}
