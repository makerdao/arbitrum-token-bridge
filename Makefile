PATH := ~/.solc-select/artifacts/:~/.solc-select/artifacts/solc-0.8.21:$(PATH)
certora-l1-token-gateway :; PATH=${PATH} certoraRun certora/L1TokenGateway.conf$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)
certora-l2-token-gateway :; PATH=${PATH} certoraRun certora/L2TokenGateway.conf$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)
