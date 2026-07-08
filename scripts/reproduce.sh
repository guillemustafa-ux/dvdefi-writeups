#!/usr/bin/env bash
#
# Reproduce all seven solved challenges against a fresh Damn Vulnerable DeFi v4.1.0
# checkout. This repo intentionally does NOT vendor the upstream challenge code —
# it only ships the solution test files (solutions/) and the writeups. This script
# clones upstream, drops the solutions in, and runs the exploits.
#
# Requires: git and foundry (forge) on PATH.
set -euo pipefail

WORK="${1:-_work}"
REPO="https://github.com/theredguild/damn-vulnerable-defi.git"

if [ ! -d "$WORK" ]; then
  git clone "$REPO" "$WORK"
  git -C "$WORK" submodule update --init --recursive
fi

# Map each solution file to its challenge directory in the upstream test tree.
declare -A MAP=(
  [Unstoppable.t.sol]=unstoppable
  [NaiveReceiver.t.sol]=naive-receiver
  [Truster.t.sol]=truster
  [SideEntrance.t.sol]=side-entrance
  [TheRewarder.t.sol]=the-rewarder
  [Selfie.t.sol]=selfie
  [Puppet.t.sol]=puppet
)

for f in "${!MAP[@]}"; do
  cp "solutions/$f" "$WORK/test/${MAP[$f]}/$f"
done

cd "$WORK"
forge test \
  --match-path "test/{unstoppable,naive-receiver,truster,side-entrance,the-rewarder,selfie,puppet}/*" \
  -vv
