// L1TokenGateway.spec

using Auxiliar as aux;
using InboxMock as inbox;
using BridgeMock as bridge;
using OutboxMock as outbox;
using GemMock as gem;

methods {
    // storage variables
    function wards(address) external returns (uint256) envfree;
    function l1ToL2Token(address) external returns (address) envfree;
    function isOpen() external returns (uint256) envfree;
    function escrow() external returns (address) envfree;
    // immutables
    function counterpartGateway() external returns (address) envfree;
    function l1Router() external returns (address) envfree;
    function inbox() external returns (address) envfree;
    // getter
    function getImplementation() external returns (address) envfree;
    //
    function gem.allowance(address,address) external returns (uint256) envfree;
    function gem.totalSupply() external returns (uint256) envfree;
    function gem.balanceOf(address) external returns (uint256) envfree;
    function aux.extractFrom(bytes) external returns (address,bytes) envfree;
    function aux.extractSubmission(bytes) external returns (uint256,bytes) envfree;
    function aux.getL1DataHash(address,address,address,uint256,bytes) external returns (bytes32) envfree;
    function inbox.bridge() external returns (address) envfree;
    function inbox.lastTo() external returns (address) envfree;
    function inbox.lastL2CallValue() external returns (uint256) envfree;
    function inbox.lastMaxSubmissionCost() external returns (uint256) envfree;
    function inbox.lastRefundTo() external returns (address) envfree;
    function inbox.lastUser() external returns (address) envfree;
    function inbox.lastMaxGas() external returns (uint256) envfree;
    function inbox.lastGasPriceBid() external returns (uint256) envfree;
    function inbox.lastDataHash() external returns (bytes32) envfree;
    function inbox.lastValue() external returns (uint256) envfree;
    function bridge.activeOutbox() external returns (address) envfree;
    function outbox.l2ToL1Sender() external returns (address) envfree;
    //
    function _.proxiableUUID() external => DISPATCHER(true);
    function _.transferFrom(address,address,uint256) external => DISPATCHER(true);
}

definition INITIALIZABLE_STORAGE() returns uint256 = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
definition IMPLEMENTATION_SLOT() returns uint256 = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

persistent ghost bool firstRead;
persistent ghost mathint initializedBefore;
persistent ghost bool initializingBefore;
persistent ghost mathint initializedAfter;
persistent ghost bool initializingAfter;
hook ALL_SLOAD(uint256 slot) uint256 val {
    if (slot == INITIALIZABLE_STORAGE() && firstRead) {
        firstRead = false;
        initializedBefore = val % (max_uint64 + 1);
        initializingBefore = (val / 2^64) % (max_uint8 + 1) != 0;
    } else if (slot == INITIALIZABLE_STORAGE()) {
        initializedAfter = val % (max_uint64 + 1);
        initializingAfter = (val / 2^64) % (max_uint8 + 1) != 0;
    }
}
hook ALL_SSTORE(uint256 slot, uint256 val) {
    if (slot == INITIALIZABLE_STORAGE()) {
        initializedAfter = val % (max_uint64 + 1);
        initializingAfter = (val / 2^64) % (max_uint8 + 1) != 0;
    }
}

// Verify no more entry points exist
rule entryPoints(method f) filtered { f -> !f.isView } {
    env e;

    calldataarg args;
    f(e, args);

    assert f.selector == sig:initialize().selector ||
           f.selector == sig:upgradeToAndCall(address,bytes).selector ||
           f.selector == sig:rely(address).selector ||
           f.selector == sig:deny(address).selector ||
           f.selector == sig:file(bytes32,address).selector ||
           f.selector == sig:close().selector ||
           f.selector == sig:registerToken(address,address).selector ||
           f.selector == sig:outboundTransfer(address,address,uint256,uint256,uint256,bytes).selector ||
           f.selector == sig:outboundTransferCustomRefund(address,address,address,uint256,uint256,uint256,bytes).selector ||
           f.selector == sig:finalizeInboundTransfer(address,address,address,uint256,bytes).selector;
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) filtered { f -> f.selector != sig:upgradeToAndCall(address, bytes).selector } {
    env e;

    address anyAddr;

    initializedAfter = initializedBefore;

    mathint wardsBefore = wards(anyAddr);
    address l1ToL2TokenBefore = l1ToL2Token(anyAddr);
    mathint isOpenBefore = isOpen();
    address escrowBefore = escrow();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    address l1ToL2TokenAfter = l1ToL2Token(anyAddr);
    mathint isOpenAfter = isOpen();
    address escrowAfter = escrow();

    assert initializedAfter != initializedBefore => f.selector == sig:initialize().selector, "Assert 1";
    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector || f.selector == sig:initialize().selector, "Assert 2";
    assert l1ToL2TokenAfter != l1ToL2TokenBefore => f.selector == sig:registerToken(address,address).selector, "Assert 3";
    assert isOpenAfter != isOpenBefore => f.selector == sig:close().selector || f.selector == sig:initialize().selector, "Assert 4";
    assert escrowAfter != escrowBefore => f.selector == sig:file(bytes32,address).selector, "Assert 5";
}

// Verify correct storage changes for non reverting initialize
rule initialize() {
    env e;

    address other;
    require other != e.msg.sender;

    mathint wardsOtherBefore = wards(other);

    initialize(e);

    mathint wardsSenderAfter = wards(e.msg.sender);
    mathint wardsOtherAfter = wards(other);
    mathint isOpenAfter = isOpen();

    assert initializedAfter == 1, "Assert 1";
    assert !initializingAfter, "Assert 2";
    assert wardsSenderAfter == 1, "Assert 3";
    assert wardsOtherAfter == wardsOtherBefore, "Assert 4";
    assert isOpenAfter == 1, "Assert 5";
}

// Verify revert rules on initialize
rule initialize_revert() {
    env e;

    firstRead = true;
    mathint bridgeCodeSize = nativeCodesize[currentContract]; // This should actually be always > 0

    initialize@withrevert(e);

    bool initialSetup = initializedBefore == 0 && !initializingBefore;
    bool construction = initializedBefore == 1 && bridgeCodeSize == 0;

    bool revert1 = e.msg.value > 0;
    bool revert2 = !initialSetup && !construction;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting initialize
rule upgradeToAndCall(address newImplementation, bytes data) {
    env e;

    require data.length == 0; // Avoid evaluating the delegatecCall part

    upgradeToAndCall(e, newImplementation, data);

    address implementationAfter = getImplementation();

    assert implementationAfter == newImplementation, "Assert 1";
}

// Verify revert rules on upgradeToAndCall
rule upgradeToAndCall_revert(address newImplementation, bytes data) {
    env e;

    require data.length == 0; // Avoid evaluating the delegatecCall part

    address self = currentContract.__self;
    address implementation = getImplementation();
    mathint wardsSender = wards(e.msg.sender);
    bytes32 newImplementationProxiableUUID = newImplementation.proxiableUUID(e);

    upgradeToAndCall@withrevert(e, newImplementation, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = self == currentContract || implementation != self;
    bool revert3 = wardsSender != 1;
    bool revert4 = newImplementationProxiableUUID != to_bytes32(IMPLEMENTATION_SLOT());

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4, "Revert rules failed";
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 1, "Assert 1";
    assert wardsOtherAfter == wardsOtherBefore, "Assert 2";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 0, "Assert 1";
    assert wardsOtherAfter == wardsOtherBefore, "Assert 2";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting file
rule file(bytes32 what, address data) {
    env e;

    file(e, what, data);

    address escrowAfter = escrow();

    assert escrowAfter == data, "Assert 1";
}

// Verify revert rules on file
rule file_revert(bytes32 what, address data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x657363726f770000000000000000000000000000000000000000000000000000);

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

// Verify correct storage changes for non reverting close
rule close() {
    env e;

    close(e);

    mathint isOpenAfter = isOpen();

    assert isOpenAfter == 0, "Assert 1";
}

// Verify revert rules on close
rule close_revert() {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    close@withrevert(e);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting registerToken
rule registerToken(address l1Token, address l2Token) {
    env e;

    registerToken(e, l1Token, l2Token);

    address l1ToL2TokenAfter = l1ToL2Token(l1Token);

    assert l1ToL2TokenAfter == l2Token, "Assert 1";
}

// Verify revert rules on registerToken
rule registerToken_revert(address l1Token, address l2Token) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    registerToken@withrevert(e, l1Token, l2Token);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting outboundTransfer
rule outboundTransfer(address l1Token, address to, uint256 amount, uint256 maxGas, uint256 gasPriceBid, bytes data) {
    env e;

    require l1Token == gem;

    address l1Router = l1Router();
    address counterpartGateway = counterpartGateway();
    address escrow = escrow();
    require e.msg.sender != escrow;

    address from;
    bytes auxData;
    if (e.msg.sender == l1Router) {
        from, auxData = aux.extractFrom(data);
    } else {
        from = e.msg.sender;
        auxData = data;
    }
    require from != escrow;
    mathint maxSubmissionCost;
    bytes extraData;
    maxSubmissionCost, extraData = aux.extractSubmission(auxData);

    bytes32 dataHash = aux.getL1DataHash(l1Token, from, counterpartGateway, amount, extraData);

    mathint l1TokenBalanceOfFromBefore = gem.balanceOf(from);
    mathint l1TokenBalanceOfEscrowBefore = gem.balanceOf(escrow);
    // ERC20 assumption
    require gem.totalSupply() >= l1TokenBalanceOfFromBefore + l1TokenBalanceOfEscrowBefore;

    outboundTransfer(e, l1Token, to, amount, maxGas, gasPriceBid, data);

    address lastToAfter = inbox.lastTo();
    mathint lastL2CallValueAfter = inbox.lastL2CallValue();
    mathint lastMaxSubmissionCostAfter = inbox.lastMaxSubmissionCost();
    address lastRefundToAfter = inbox.lastRefundTo();
    address lastUserAfter = inbox.lastUser();
    mathint lastMaxGasAfter = inbox.lastMaxGas();
    mathint lastGasPriceBidAfter = inbox.lastGasPriceBid();
    bytes32 lastDataHashAfter = inbox.lastDataHash();
    mathint lastValueAfter = inbox.lastValue();
    mathint l1TokenBalanceOfFromAfter = gem.balanceOf(from);
    mathint l1TokenBalanceOfEscrowAfter = gem.balanceOf(escrow);

    assert lastToAfter == counterpartGateway, "Assert 1";
    assert lastL2CallValueAfter == 0, "Assert 2";
    assert lastMaxSubmissionCostAfter == maxSubmissionCost, "Assert 3";
    assert lastRefundToAfter == to, "Assert 4";
    assert lastUserAfter == from, "Assert 5";
    assert lastMaxGasAfter == maxGas, "Assert 6";
    assert lastGasPriceBidAfter == gasPriceBid, "Assert 7";
    assert lastDataHashAfter == dataHash, "Assert 8";
    assert lastValueAfter == e.msg.value, "Assert 9";
    assert l1TokenBalanceOfFromAfter == l1TokenBalanceOfFromBefore - amount, "Assert 10";
    assert l1TokenBalanceOfEscrowAfter == l1TokenBalanceOfEscrowBefore + amount, "Assert 11";
}

// Verify revert rules on outboundTransfer
rule outboundTransfer_revert(address l1Token, address to, uint256 amount, uint256 maxGas, uint256 gasPriceBid, bytes data) {
    env e;

    require l1Token == gem;

    mathint isOpen = isOpen();
    address l1ToL2TokenL1Token = l1ToL2Token(l1Token);

    address l1Router = l1Router();
    address escrow = escrow();

    address from;
    bytes auxData;
    if (e.msg.sender == l1Router) {
        from, auxData = aux.extractFrom(data);
    } else {
        from = e.msg.sender;
        auxData = data;
    }
    require from != escrow;
    mathint a;
    bytes extraData;
    a, extraData = aux.extractSubmission(auxData);

    mathint l1TokenBalanceOfFrom = gem.balanceOf(from);
    mathint l1TokenBalanceOfEscrow = gem.balanceOf(escrow);
    mathint senderBalance = nativeBalances[e.msg.sender];
    mathint inboxBalance = nativeBalances[inbox];

    // ERC20 assumption
    require gem.totalSupply() >= l1TokenBalanceOfFrom + l1TokenBalanceOfEscrow;
    // User assumptions
    require l1TokenBalanceOfFrom >= amount;
    require gem.allowance(from, currentContract) >= amount;
    // Practical assumption
    require inboxBalance + e.msg.value <= max_uint256;

    outboundTransfer@withrevert(e, l1Token, to, amount, maxGas, gasPriceBid, data);

    bool revert1 = senderBalance < e.msg.value;
    bool revert2 = isOpen != 1;
    bool revert3 = l1ToL2TokenL1Token == 0;
    bool revert4 = extraData.length > 0;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4, "Revert rules failed";
}

// Verify correct storage changes for non reverting outboundTransferCustomRefund
rule outboundTransferCustomRefund(address l1Token, address refundTo, address to, uint256 amount, uint256 maxGas, uint256 gasPriceBid, bytes data) {
    env e;

    require l1Token == gem;

    address l1Router = l1Router();
    address counterpartGateway = counterpartGateway();
    address escrow = escrow();
    require e.msg.sender != escrow;

    address from;
    bytes auxData;
    if (e.msg.sender == l1Router) {
        from, auxData = aux.extractFrom(data);
    } else {
        from = e.msg.sender;
        auxData = data;
    }
    require from != escrow;
    mathint maxSubmissionCost;
    bytes extraData;
    maxSubmissionCost, extraData = aux.extractSubmission(auxData);

    bytes32 dataHash = aux.getL1DataHash(l1Token, from, counterpartGateway, amount, extraData);

    mathint l1TokenBalanceOfFromBefore = gem.balanceOf(from);
    mathint l1TokenBalanceOfEscrowBefore = gem.balanceOf(escrow);
    // ERC20 assumption
    require gem.totalSupply() >= l1TokenBalanceOfFromBefore + l1TokenBalanceOfEscrowBefore;

    outboundTransferCustomRefund(e, l1Token, refundTo, to, amount, maxGas, gasPriceBid, data);

    address lastToAfter = inbox.lastTo();
    mathint lastL2CallValueAfter = inbox.lastL2CallValue();
    mathint lastMaxSubmissionCostAfter = inbox.lastMaxSubmissionCost();
    address lastRefundToAfter = inbox.lastRefundTo();
    address lastUserAfter = inbox.lastUser();
    mathint lastMaxGasAfter = inbox.lastMaxGas();
    mathint lastGasPriceBidAfter = inbox.lastGasPriceBid();
    bytes32 lastDataHashAfter = inbox.lastDataHash();
    mathint lastValueAfter = inbox.lastValue();
    mathint l1TokenBalanceOfFromAfter = gem.balanceOf(from);
    mathint l1TokenBalanceOfEscrowAfter = gem.balanceOf(escrow);

    assert lastToAfter == counterpartGateway, "Assert 1";
    assert lastL2CallValueAfter == 0, "Assert 2";
    assert lastMaxSubmissionCostAfter == maxSubmissionCost, "Assert 3";
    assert lastRefundToAfter == refundTo, "Assert 4";
    assert lastUserAfter == from, "Assert 5";
    assert lastMaxGasAfter == maxGas, "Assert 6";
    assert lastGasPriceBidAfter == gasPriceBid, "Assert 7";
    assert lastDataHashAfter == dataHash, "Assert 8";
    assert lastValueAfter == e.msg.value, "Assert 9";
    assert l1TokenBalanceOfFromAfter == l1TokenBalanceOfFromBefore - amount, "Assert 10";
    assert l1TokenBalanceOfEscrowAfter == l1TokenBalanceOfEscrowBefore + amount, "Assert 11";
}

// Verify revert rules on outboundTransferCustomRefund
rule outboundTransferCustomRefund_revert(address l1Token, address refundTo, address to, uint256 amount, uint256 maxGas, uint256 gasPriceBid, bytes data) {
    env e;

    require l1Token == gem;

    mathint isOpen = isOpen();
    address l1ToL2TokenL1Token = l1ToL2Token(l1Token);

    address l1Router = l1Router();
    address escrow = escrow();

    address from;
    bytes auxData;
    if (e.msg.sender == l1Router) {
        from, auxData = aux.extractFrom(data);
    } else {
        from = e.msg.sender;
        auxData = data;
    }
    require from != escrow;
    mathint a;
    bytes extraData;
    a, extraData = aux.extractSubmission(auxData);

    mathint l1TokenBalanceOfFrom = gem.balanceOf(from);
    mathint l1TokenBalanceOfEscrow = gem.balanceOf(escrow);
    mathint senderBalance = nativeBalances[e.msg.sender];
    mathint inboxBalance = nativeBalances[inbox];

    // ERC20 assumption
    require gem.totalSupply() >= l1TokenBalanceOfFrom + l1TokenBalanceOfEscrow;
    // User assumptions
    require l1TokenBalanceOfFrom >= amount;
    require gem.allowance(from, currentContract) >= amount;
    // Practical assumption
    require inboxBalance + e.msg.value <= max_uint256;

    outboundTransferCustomRefund@withrevert(e, l1Token, refundTo, to, amount, maxGas, gasPriceBid, data);

    bool revert1 = senderBalance < e.msg.value;
    bool revert2 = isOpen != 1;
    bool revert3 = l1ToL2TokenL1Token == 0;
    bool revert4 = extraData.length > 0;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4, "Revert rules failed";
}

// Verify correct storage changes for non reverting finalizeInboundTransfer
rule finalizeInboundTransfer(address l1Token, address from, address to, uint256 amount, bytes data) {
    env e;

    require l1Token == gem;

    address escrow = escrow();

    mathint l1TokenBalanceOfEscrowBefore = gem.balanceOf(escrow);
    mathint l1TokenBalanceOfToBefore = gem.balanceOf(to);

    // ERC20 assumption
    require gem.totalSupply() >= l1TokenBalanceOfEscrowBefore + l1TokenBalanceOfToBefore;

    finalizeInboundTransfer(e, l1Token, from, to, amount, data);

    mathint l1TokenBalanceOfEscrowAfter = gem.balanceOf(escrow);
    mathint l1TokenBalanceOfToAfter = gem.balanceOf(to);

    assert escrow != to => l1TokenBalanceOfEscrowAfter == l1TokenBalanceOfEscrowBefore - amount, "Assert 1";
    assert escrow != to => l1TokenBalanceOfToAfter == l1TokenBalanceOfToBefore + amount, "Assert 2";
    assert escrow == to => l1TokenBalanceOfEscrowAfter == l1TokenBalanceOfEscrowBefore, "Assert 3";
}

// Verify revert rules on finalizeInboundTransfer
rule finalizeInboundTransfer_revert(address l1Token, address from, address to, uint256 amount, bytes data) {
    env e;

    require l1Token == gem;

    address l2ToL1Sender = outbox.l2ToL1Sender();

    address counterpartGateway = counterpartGateway();
    address escrow = escrow();

    mathint l1TokenBalanceOfEscrow = gem.balanceOf(escrow);
    mathint senderBalance = nativeBalances[e.msg.sender];

    // ERC20 assumption
    require gem.totalSupply() >= l1TokenBalanceOfEscrow + gem.balanceOf(to);
    // Bridge assumption
    require l1TokenBalanceOfEscrow >= amount;
    // Set up assumption
    require gem.allowance(escrow, currentContract) == max_uint256;

    finalizeInboundTransfer@withrevert(e, l1Token, from, to, amount, data);

    bool revert1 = senderBalance < e.msg.value;
    bool revert2 = e.msg.sender != bridge;
    bool revert3 = l2ToL1Sender == 0;
    bool revert4 = l2ToL1Sender != counterpartGateway;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4, "Revert rules failed";
}
