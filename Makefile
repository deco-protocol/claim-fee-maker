all             :; dapp build
clean           :; dapp clean
                    # Usage example: make test match=SpellIsCast
test            :; ./test-cfm.sh
deploy-cfm      :; make && dapp create ClaimFee $(gate)