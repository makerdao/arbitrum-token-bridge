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

import { ITokenGateway } from "src/arbitrum/ITokenGateway.sol";
import { ICustomGateway } from "src/arbitrum/ICustomGateway.sol";
import { AddressAliasHelper } from "src/arbitrum/AddressAliasHelper.sol";
import { L2ArbitrumMessenger } from "src/arbitrum/L2ArbitrumMessenger.sol";

interface TokenLike {
    function mint(address, uint256) external;
    function burn(address, uint256) external;
}

contract L2TokenGateway is ITokenGateway, ICustomGateway, L2ArbitrumMessenger {
    // --- storage variables ---

    mapping(address => uint256) public wards;
    mapping(address => address) public l1ToL2Token;
    uint256 public isOpen = 1;

    // --- immutables ---

    address public immutable l2Router;
    address public immutable counterpartGateway;

     // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
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

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "L2TokenGateway/not-authorized");
        _;
    }

    modifier onlyCounterpartGateway() {
        require(
            msg.sender == AddressAliasHelper.applyL1ToL2Alias(counterpartGateway),
            "L2TokenGateway/only-counterpart-gateway"
        );
        _;
    }

    // --- constructor ---

    constructor(
        address _counterpartGateway,
        address _l2Router
    ) {
        counterpartGateway = _counterpartGateway;
        l2Router = _l2Router;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- administration ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function close() external auth {
        isOpen = 0;
        emit Closed();
    }

    function registerToken(address l1Token, address l2Token) external auth {
        l1ToL2Token[l1Token] = l2Token;
        emit TokenSet(l1Token, l2Token);
    }

    // --- outbound transfers ---

    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes memory) {
        return outboundTransfer(l1Token, to, amount, 0, 0, data);
    }

    /**
     * @notice Initiates a token withdrawal from L2 to L1
     * @param l1Token address of the withdrawn token on L1
     * @param to account to credit with the tokens on L1
     * @param amount amount of tokens to withdraw
     * @return res encoded unique identifier for withdrawal
     */
    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        uint256, /* maxGas */
        uint256, /* gasPriceBid */
        bytes calldata data
    ) public payable returns (bytes memory res) {
        require(msg.value == 0, "L2TokenGateway/no-value-allowed");
        require(isOpen == 1, "L2TokenGateway/closed");
        address l2Token = l1ToL2Token[l1Token];
        require(l2Token != address(0), "L2TokenGateway/invalid-token");
        address from;
        bytes memory extraData = data;
        (from, extraData) = msg.sender == l2Router ? abi.decode(extraData, (address, bytes)) : (msg.sender, extraData);
        require(extraData.length == 0, "L2TokenGateway/extra-data-not-allowed");

        TokenLike(l2Token).burn(from, amount);

        uint256 id = createOutboundTx(
            from,
            getOutboundCalldata(l1Token, from, to, amount, extraData)
        );

        emit WithdrawalInitiated(l1Token, from, to, id, 0, amount);

        res = abi.encode(id);
    }

    function getOutboundCalldata(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) public pure returns (bytes memory outboundCalldata) {
        outboundCalldata = abi.encodeCall(ITokenGateway.finalizeInboundTransfer, (
            token,
            from,
            to,
            amount,
            abi.encode(0, data) // using 0 for exitNum as exit redirection is not supported
        ));
    }

    function createOutboundTx(
        address from,
        bytes memory outboundCalldata
    ) internal returns (uint256) {
        return
            sendTxToL1({
                _l1CallValue: 0,
                _from: from,
                _to: counterpartGateway,
                _data: outboundCalldata
            });
    }

    // --- inbound transfers ---

     /**
     * @notice Finalizes a token deposit from L1 to L2
     * @dev Callable only by the L1TokenGateway.outboundTransferCustomRefund method.
     * @param l1Token address of the deposited token on L1
     * @param from account that initiated the deposit on L1
     * @param to account to credit with the tokens on L2
     * @param amount amount of tokens to deposit
     */
    function finalizeInboundTransfer(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes calldata /* data */
    ) external payable onlyCounterpartGateway {
        address l2Token = l1ToL2Token[l1Token];
        require(l2Token != address(0), "L2TokenGateway/invalid-token");

        TokenLike(l2Token).mint(to, amount);

        emit DepositFinalized(l1Token, from, to, amount);
    }

    // --- router integration ---

    /**
     * @notice Calculate the address used when bridging an ERC20 token
     * @param l1Token address of L1 token
     * @return l2Token L2 address of a bridged ERC20 token
     */
    function calculateL2TokenAddress(address l1Token) external view returns (address l2Token) {
        l2Token = l1ToL2Token[l1Token];
    }
}
