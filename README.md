# Damn Vulnerable DeFi — Solutions & Auditor Write-ups

Solutions and auditor-grade write-ups for [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz)
**v4.1.0**, the Foundry-based smart-contract security wargame by
[@tinchoabbate](https://github.com/tinchoabbate) / [The Red Guild](https://github.com/theredguild).

This is a **security-practice / training** piece: each challenge is a deliberately
vulnerable DeFi protocol, and the goal is to write an exploit that satisfies the
challenge's on-chain success condition. For every challenge here there is:

- a **verified passing exploit** ([`solutions/`](./solutions)) — the actual test
  that drains/breaks the target, and
- a **write-up** ([`writeups/`](./writeups)) framed the way I'd report it in an
  audit: vulnerability class → root cause → exploit walkthrough → remediation →
  real-world parallel.

It's the offensive counterpart to my defensive work (see *Related*): breaking
these teaches exactly the failure modes I then harden against in my own contracts.

## Challenges solved (7)

| # | Challenge | Vulnerability class | Write-up |
|---|-----------|---------------------|----------|
| 01 | Unstoppable | ERC-4626 accounting invariant broken by a direct transfer (griefing/DoS) | [01-unstoppable.md](./writeups/01-unstoppable.md) |
| 02 | Naive Receiver | Missing initiator check + trusted-forwarder/multicall sender spoofing | [02-naive-receiver.md](./writeups/02-naive-receiver.md) |
| 03 | Truster | Arbitrary external call with attacker-controlled target & calldata | [03-truster.md](./writeups/03-truster.md) |
| 04 | Side Entrance | Flash-loan repaid through a side door that mints a free claim | [04-side-entrance.md](./writeups/04-side-entrance.md) |
| 05 | The Rewarder | Broken batch-claim idempotency → reward double-spend | [05-the-rewarder.md](./writeups/05-the-rewarder.md) |
| 06 | Selfie | Flash-loan governance capture via spot voting power | [06-selfie.md](./writeups/06-selfie.md) |
| 07 | Puppet | Spot-price oracle manipulation on a thin Uniswap V1 pair | [07-puppet.md](./writeups/07-puppet.md) |

These seven cover the foundational DeFi attack surface — flash loans, arbitrary
calls, oracle manipulation, governance capture, meta-tx spoofing and reward
accounting. The remaining v4 challenges (Compromised, Puppet V2/V3, Free Rider,
Backdoor, Climber, Wallet Mining, ABI Smuggling, Shards, Curvy Puppet, Withdrawal)
are **not yet done** and will be added as I work through them — this README tracks
real progress, not aspiration.

## Evidence

All seven exploits pass against a clean v4.1.0 checkout (Foundry `forge 1.7.1`,
`solc 0.8.25`):

```
Ran 7 test suites: 7 tests passed, 0 failed, 0 skipped (7 total tests)

[PASS] test_unstoppable()    (gas: 66,791)
[PASS] test_naiveReceiver()  (gas: 398,237)
[PASS] test_truster()        (gas: 102,157)
[PASS] test_sideEntrance()   (gas: 234,332)
[PASS] test_theRewarder()    (gas: 34,954,186)
[PASS] test_selfie()         (gas: 685,520)
[PASS] test_puppet()         (gas: 218,209)
```

## Reproduce

This repo does **not** vendor the upstream challenge code (out of respect for the
author's request not to mirror solutions wholesale, and to keep this repo focused
on *my* work). Instead it ships only the solution test files and a script that
clones upstream and drops them in:

```bash
git clone https://github.com/guillemustafa-ux/dvdefi-writeups.git
cd dvdefi-writeups
bash scripts/reproduce.sh          # clones DVDeFi v4, copies solutions in, runs forge test
```

Or manually: clone [`theredguild/damn-vulnerable-defi`](https://github.com/theredguild/damn-vulnerable-defi)
at `v4.1.0`, `git submodule update --init --recursive`, copy each file from
[`solutions/`](./solutions) over the matching `test/<challenge>/<Challenge>.t.sol`,
and run `forge test`.

Each solution keeps the challenge's `setUp`/`_isSolved` harness **untouched** — the
success conditions are the author's, not mine; only the `CODE YOUR SOLUTION HERE`
region (and any helper exploit contract) is my work.

## Related work

Defensive counterparts in my portfolio (self-audited, hardened, deployed):

- **rwa-yield-protocol** — flagship RWA yield protocol (ERC-7540 + Chainlink
  Automation/CCIP + UUPS), full `SECURITY.md` threat model.
- **yield-vault** — ERC-4626 + ERC-7540 vaults with invariant tests.
- **botpass**, **aa-smart-wallet** — on-chain subscriptions (ERC-721) and ERC-4337
  smart accounts.

## Credits & license

- Challenges © [@tinchoabbate](https://github.com/tinchoabbate) / The Red Guild —
  [Damn Vulnerable DeFi](https://github.com/theredguild/damn-vulnerable-defi), MIT.
- Solutions and write-ups in this repo are my own work, released under MIT.
