include .env

deploy-sepolia:
	@echo "Deploying to Sepolia..."
	@forge script script/DeployClvrHookOnSepolia.s.sol:DeployClvrHookOnSepolia --rpc-url $(SEPOLIA_RPC_URL) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) --sender $(DEPLOYER_ADDRESS) --private-key $(PRIVATE_KEY)
