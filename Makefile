all             :; dapp build
clean           :; dapp clean
                    # Usage example: make test match=Close
test            :; make && ./test-cfm.sh $(match)
deploy          :; make && dapp create ClaimFee $(gate)

# Echidna Testing - Access Control Invariants
echidna-claimfee-access :; ./echidna/runner/echidna-access-invariants.sh

# Echidna Testing - Conditional Invariants
echidna-claimfee-conditional :; ./echidna/runner/echidna-conditional-invariants.sh

# Echidna Testing - Functional Invariants
echidna-claimfee-functional :; ./echidna/runner/echidna-functional-invariants.sh