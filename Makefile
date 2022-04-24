all             :; dapp build
clean           :; dapp clean
                    # Usage example: make test match=Close
test            :; make && ./test-cfm.sh $(match)
deploy          :; make && dapp create ClaimFee $(gate)