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

import { ITokenGateway } from "../arbitrum/ITokenGateway.sol";
import { ICustomGateway } from "../arbitrum/ICustomGateway.sol";
import { AddressAliasHelper } from "../arbitrum/AddressAliasHelper.sol";
import { L2ArbitrumMessenger } from "../arbitrum/L2ArbitrumMessenger.sol";

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
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        counterpartGateway = _counterpartGateway;
        l2Router = _l2Router;
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

    function registerTokens(address[] calldata l1Tokens, address[] calldata l2Tokens) external auth {
        for(uint256 i; i < l1Tokens.length; i++) {
            (address l1Token, address l2Token) = (l1Tokens[i], l2Tokens[i]);
            l1ToL2Token[l1Token] = l2Token;
            emit TokenSet(l1Token, l2Token);
        }
    }

    // --- ITokenGateway ---

    /**
     * @notice Calculate the address used when bridging an ERC20 token
     * @param l1Token address of L1 token
     * @return L2 address of a bridged ERC20 token
     */
    function calculateL2TokenAddress(address l1Token) external view returns (address) {
        return l1ToL2Token[l1Token];
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
     * @notice Initiates a token withdrawal from Arbitrum to Ethereum
     * @param l1Token l1 address of token
     * @param to destination address
     * @param amount amount of tokens withdrawn
     * @return res encoded unique identifier for withdrawal
     */
    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        uint256, /* maxGas */
        uint256, /* gasPriceBid */
        bytes calldata data
    ) public payable override returns (bytes memory res) {
        require(msg.value == 0, "L2TokenGateway/no-value-allowed");
        require(isOpen == 1, "L2TokenGateway/closed");
        address l2Token = l1ToL2Token[l1Token];
        require(l2Token != address(0), "L2TokenGateway/invalid-token");

        (address from, bytes memory extraData) = parseOutboundData(data);
        require(extraData.length == 0, "L2TokenGateway/extra-data-not-allowed");

        TokenLike(l2Token).burn(from, amount);

        uint256 id = createOutboundTx(
            from,
            getOutboundCalldata(l1Token, from, to, amount, extraData)
        );

        emit WithdrawalInitiated(l1Token, from, to, id, 0, amount);

        res = abi.encode(id);
    }

    function parseOutboundData(bytes memory data) internal view returns (address from, bytes memory extraData) {
        (from, extraData) = msg.sender == l2Router ? abi.decode(data, (address, bytes)) : (msg.sender, data);
    }

    function getOutboundCalldata(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) public pure returns (bytes memory outboundCalldata) {
        outboundCalldata = abi.encodeWithSelector(
            ITokenGateway.finalizeInboundTransfer.selector,
            token,
            from,
            to,
            amount,
            abi.encode(0, data) // using 0 for exitNum as exit redirection is not supported
        );
    }

    function createOutboundTx(
        address from,
        bytes memory outboundCalldata
    ) internal returns (uint256) {
        return
            sendTxToL1(
                0, // l1 call value is 0
                from,
                counterpartGateway,
                outboundCalldata
            );
    }

    // --- inbound transfers ---

     /**
     * @notice Mint on L2 upon L1 deposit.
     * @dev Callable only by the L1TokenGateway.outboundTransferCustomRefund method.
     * @param l1Token L1 address of ERC20
     * @param from account that initiated the deposit in the L1
     * @param to account to be credited with the tokens in the L2 (can be the user's L2 account or a contract)
     * @param amount token amount to be minted to the user
     */
    function finalizeInboundTransfer(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes calldata /* data */
    ) external payable onlyCounterpartGateway {
        address l2Token = l1ToL2Token[l1Token];
        require(l2Token != address(0), "L2TokenGateway/invalid-token"); // TODO: we can retry if this reverts but note that L2ArbitrumGateway triggers withdrawal instead of reverting

        TokenLike(l2Token).mint(to, amount);

        emit DepositFinalized(l1Token, from, to, amount);
    }
}
