-include .env

.PHONY: all test clean deploy-sepolia deploy-anvil build

all: clean remove install update build

# Clean the repo
clean:; forge clean

# Remove modules
remove:; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

# Install the Modules
install:; forge install foundry-rs/forge-std --no-commit && forge install openzeppelin/openzeppelin-contracts --no-commit && forge install openzeppelin/openzeppelin-contracts-upgradeable --no-commit && forge install smartcontractkit/chainlink-brownie-contracts --no-commit && forge install Uniswap/v3-core --no-commit && forge install Uniswap/v3-periphery --no-commit

# Update Dependencies
update:; forge update

# Build
build:; forge build

# Test
test:; forge test

# Deploy to Sepolia
deploy-sepolia:
	forge script script/Deploy.s.sol:DeployGuardian --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

# Deploy to Anvil
deploy-anvil:
	forge script script/Deploy.s.sol:DeployGuardian --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast -vvvv
