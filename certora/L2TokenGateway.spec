// L2TokenGateway.spec

using Auxiliar as aux;
using ArbSysMock as arb;
using GemMock as gem;

methods {
    // storage variables
    function wards(address) external returns (uint256) envfree;
    function l1ToL2Token(address) external returns (address) envfree;
    function maxWithdraws(address) external returns (uint256) envfree;
    function isOpen() external returns (uint256) envfree;
    // immutables
    function l2Router() external returns (address) envfree;
    function counterpartGateway() external returns (address) envfree;
    // getter
    function getImplementation() external returns (address) envfree;
    //
    function gem.wards(address) external returns (uint256) envfree;
    function gem.allowance(address,address) external returns (uint256) envfree;
    function gem.totalSupply() external returns (uint256) envfree;
    function gem.balanceOf(address) external returns (uint256) envfree;
    function aux.extractFrom(bytes) external returns (address,bytes) envfree;
    function aux.extractSubmission(bytes) external returns (uint256,bytes) envfree;
    function aux.getL2DataHash(address,address,address,uint256,bytes) external returns (bytes32) envfree;
    function aux.applyL1ToL2Alias(address) external returns (address) envfree;
    function arb.lastTo() external returns (address) envfree;
    function arb.lastDataHash() external returns (bytes32) envfree;
    function arb.lastValue() external returns (uint256) envfree;
    //
    function _.proxiableUUID() external => DISPATCHER(true);
    function _.burn(address,uint256) external => DISPATCHER(true);
    function _.mint(address,uint256) external => DISPATCHER(true);
    function _.sendTxToL1(address,bytes) external => DISPATCHER(true);
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
           f.selector == sig:close().selector ||
           f.selector == sig:registerToken(address,address).selector ||
           f.selector == sig:setMaxWithdraw(address,uint256).selector ||
           f.selector == sig:outboundTransfer(address,address,uint256,bytes).selector ||
           f.selector == sig:outboundTransfer(address,address,uint256,uint256,uint256,bytes).selector ||
           f.selector == sig:finalizeInboundTransfer(address,address,address,uint256,bytes).selector;
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) filtered { f -> f.selector != sig:upgradeToAndCall(address, bytes).selector } {
    env e;

    address anyAddr;

    initializedAfter = initializedBefore;

    mathint wardsBefore = wards(anyAddr);
    address l1ToL2TokenBefore = l1ToL2Token(anyAddr);
    mathint maxWithdrawsBefore = maxWithdraws(anyAddr);
    mathint isOpenBefore = isOpen();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    address l1ToL2TokenAfter = l1ToL2Token(anyAddr);
    mathint maxWithdrawsAfter = maxWithdraws(anyAddr);
    mathint isOpenAfter = isOpen();

    assert initializedAfter != initializedBefore => f.selector == sig:initialize().selector, "Assert 1";
    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector || f.selector == sig:initialize().selector, "Assert 2";
    assert l1ToL2TokenAfter != l1ToL2TokenBefore => f.selector == sig:registerToken(address,address).selector, "Assert 3";
    assert maxWithdrawsAfter != maxWithdrawsBefore => f.selector == sig:setMaxWithdraw(address,uint256).selector, "Assert 4";
    assert isOpenAfter != isOpenBefore => f.selector == sig:close().selector || f.selector == sig:initialize().selector, "Assert 5";
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

// Verify correct storage changes for non reverting setMaxWithdraw
rule setMaxWithdraw(address l2Token, uint256 maxWithdraw) {
    env e;

    setMaxWithdraw(e, l2Token, maxWithdraw);

    mathint maxWithdrawsAfter = maxWithdraws(l2Token);

    assert maxWithdrawsAfter == maxWithdraw, "Assert 1";
}

// Verify revert rules on setMaxWithdraw
rule setMaxWithdraw_revert(address l2Token, uint256 maxWithdraw) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    setMaxWithdraw@withrevert(e, l2Token, maxWithdraw);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting outboundTransfer
rule outboundTransfer(address l1Token, address to, uint256 amount, bytes data) {
    env e;

    require arb == 100;

    address l2Router = l2Router();
    address counterpartGateway = counterpartGateway();
    address l1ToL2TokenL1Token = l1ToL2Token(l1Token);

    require l1ToL2TokenL1Token == gem;

    address from;
    bytes extraData;
    if (e.msg.sender == l2Router) {
        from, extraData = aux.extractFrom(data);
    } else {
        from = e.msg.sender;
        extraData = data;
    }

    bytes32 dataHash = aux.getL2DataHash(l1Token, from, counterpartGateway, amount, extraData);

    mathint l1TokenTotalSupplyBefore = gem.totalSupply();
    mathint l1TokenBalanceOfFromBefore = gem.balanceOf(from);
    // ERC20 assumption
    require l1TokenTotalSupplyBefore >= l1TokenBalanceOfFromBefore;

    outboundTransfer(e, l1Token, to, amount, data);

    address lastToAfter = arb.lastTo();
    bytes32 lastDataHashAfter = arb.lastDataHash();
    mathint lastValueAfter = arb.lastValue();
    mathint l1TokenTotalSupplyAfter = gem.totalSupply();
    mathint l1TokenBalanceOfFromAfter = gem.balanceOf(from);

    assert lastToAfter == counterpartGateway, "Assert 1";
    assert lastDataHashAfter == dataHash, "Assert 2";
    assert lastValueAfter == 0, "Assert 3";
    assert l1TokenTotalSupplyAfter == l1TokenTotalSupplyBefore - amount, "Assert 4";
    assert l1TokenBalanceOfFromAfter == l1TokenBalanceOfFromBefore - amount, "Assert 5";
}

// Verify revert rules on outboundTransfer
rule outboundTransfer_revert(address l1Token, address to, uint256 amount, bytes data) {
    env e;

    require arb == 100;

    mathint isOpen = isOpen();
    address l1ToL2TokenL1Token = l1ToL2Token(l1Token);
    mathint maxWithdrawsL2Token = maxWithdraws(l1ToL2TokenL1Token);

    require l1ToL2TokenL1Token == gem;

    address l2Router = l2Router();

    address from;
    bytes extraData;
    if (e.msg.sender == l2Router) {
        from, extraData = aux.extractFrom(data);
    } else {
        from = e.msg.sender;
        extraData = data;
    }

    mathint l1TokenBalanceOfFrom = gem.balanceOf(from);

    // ERC20 assumption
    require gem.totalSupply() >= l1TokenBalanceOfFrom;
    // User assumptions
    require l1TokenBalanceOfFrom >= amount;
    require gem.allowance(from, currentContract) >= amount;

    outboundTransfer@withrevert(e, l1Token, to, amount, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = isOpen != 1;
    bool revert3 = l1ToL2TokenL1Token == 0;
    bool revert4 = amount > maxWithdrawsL2Token;
    bool revert5 = extraData.length > 0;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5, "Revert rules failed";
}

// Verify correct storage changes for non reverting outboundTransfer
rule outboundTransfer2(address l1Token, address to, uint256 amount, uint256 maxGas, uint256 gasPriceBid, bytes data) {
    env e;

    require arb == 100;

    address l2Router = l2Router();
    address counterpartGateway = counterpartGateway();
    address l1ToL2TokenL1Token = l1ToL2Token(l1Token);

    require l1ToL2TokenL1Token == gem;

    address from;
    bytes extraData;
    if (e.msg.sender == l2Router) {
        from, extraData = aux.extractFrom(data);
    } else {
        from = e.msg.sender;
        extraData = data;
    }

    bytes32 dataHash = aux.getL2DataHash(l1Token, from, counterpartGateway, amount, extraData);

    mathint l1TokenTotalSupplyBefore = gem.totalSupply();
    mathint l1TokenBalanceOfFromBefore = gem.balanceOf(from);
    // ERC20 assumption
    require l1TokenTotalSupplyBefore >= l1TokenBalanceOfFromBefore;

    outboundTransfer(e, l1Token, to, amount, maxGas, gasPriceBid, data);

    address lastToAfter = arb.lastTo();
    bytes32 lastDataHashAfter = arb.lastDataHash();
    mathint lastValueAfter = arb.lastValue();
    mathint l1TokenTotalSupplyAfter = gem.totalSupply();
    mathint l1TokenBalanceOfFromAfter = gem.balanceOf(from);

    assert lastToAfter == counterpartGateway, "Assert 1";
    assert lastDataHashAfter == dataHash, "Assert 2";
    assert lastValueAfter == 0, "Assert 3";
    assert l1TokenTotalSupplyAfter == l1TokenTotalSupplyBefore - amount, "Assert 4";
    assert l1TokenBalanceOfFromAfter == l1TokenBalanceOfFromBefore - amount, "Assert 5";
}

// Verify revert rules on outboundTransfer
rule outboundTransfer2_revert(address l1Token, address to, uint256 amount, uint256 maxGas, uint256 gasPriceBid, bytes data) {
    env e;

    require arb == 100;

    mathint isOpen = isOpen();
    address l1ToL2TokenL1Token = l1ToL2Token(l1Token);
    mathint maxWithdrawsL2Token = maxWithdraws(l1ToL2TokenL1Token);

    require l1ToL2TokenL1Token == gem;

    address l2Router = l2Router();

    address from;
    bytes extraData;
    if (e.msg.sender == l2Router) {
        from, extraData = aux.extractFrom(data);
    } else {
        from = e.msg.sender;
        extraData = data;
    }

    mathint l1TokenBalanceOfFrom = gem.balanceOf(from);

    // ERC20 assumption
    require gem.totalSupply() >= l1TokenBalanceOfFrom;
    // User assumptions
    require l1TokenBalanceOfFrom >= amount;
    require gem.allowance(from, currentContract) >= amount;

    outboundTransfer@withrevert(e, l1Token, to, amount, maxGas, gasPriceBid, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = isOpen != 1;
    bool revert3 = l1ToL2TokenL1Token == 0;
    bool revert4 = amount > maxWithdrawsL2Token;
    bool revert5 = extraData.length > 0;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5, "Revert rules failed";
}

// Verify correct storage changes for non reverting finalizeInboundTransfer
rule finalizeInboundTransfer(address l1Token, address from, address to, uint256 amount, bytes data) {
    env e;

    address l1ToL2TokenL1Token = l1ToL2Token(l1Token);
    require l1ToL2TokenL1Token == gem;

    mathint l1TokenTotalSupplyBefore = gem.totalSupply();
    mathint l1TokenBalanceOfToBefore = gem.balanceOf(to);

    // ERC20 assumption
    require l1TokenTotalSupplyBefore >= l1TokenBalanceOfToBefore;

    finalizeInboundTransfer(e, l1Token, from, to, amount, data);

    mathint l1TokenTotalSupplyAfter = gem.totalSupply();
    mathint l1TokenBalanceOfToAfter = gem.balanceOf(to);

    assert l1TokenTotalSupplyAfter == l1TokenTotalSupplyBefore + amount, "Assert 1";
    assert l1TokenBalanceOfToAfter == l1TokenBalanceOfToBefore + amount, "Assert 2";
}

// Verify revert rules on finalizeInboundTransfer
rule finalizeInboundTransfer_revert(address l1Token, address from, address to, uint256 amount, bytes data) {
    env e;

    address l1ToL2TokenL1Token = l1ToL2Token(l1Token);
    require l1ToL2TokenL1Token == gem;

    address aliasCounterpartGateway = aux.applyL1ToL2Alias(counterpartGateway());

    mathint senderBalance = nativeBalances[e.msg.sender];

    // ERC20 assumption
    require gem.totalSupply() >= gem.balanceOf(to);
    // Set up assumption
    require gem.wards(currentContract) == 1;
    // Practical assumption
    require gem.totalSupply() + amount <= max_uint256;

    finalizeInboundTransfer@withrevert(e, l1Token, from, to, amount, data);

    bool revert1 = senderBalance < e.msg.value;
    bool revert2 = e.msg.sender != aliasCounterpartGateway;
    bool revert3 = l1ToL2TokenL1Token == 0;

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}
