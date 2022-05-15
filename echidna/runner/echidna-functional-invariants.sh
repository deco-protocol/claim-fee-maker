#!/usr/bin/env bash

set -e

# Solidity Compiler Version
SOLC=~/.nix-profile/bin/solc-0.8.1

# Validate if $SOLC is installed
# [[ -f "$SOLC" ]] || nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-static-versions.solc_0_6_12

# Echidna Fuzz Test Contract Name
readonly ECHIDNA_CLAIMFEE_CONTRACT_NAME=ClaimFeeEchidnaFunctionalInvariantTest

# Invoke Echidna FUNCTIONAL INVARIANT tests for claim fee maker contract
echidna-test echidna/"$ECHIDNA_CLAIMFEE_CONTRACT_NAME".sol --contract "$ECHIDNA_CLAIMFEE_CONTRACT_NAME" --config echidna.config.yml
