// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import {DSTest} from "ds-test/test.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {CheatCodes} from "src/test/utils/Cheatcodes.sol";

import {AlchemistV2} from "src/AlchemistV2.sol";
import {AlchemicTokenV2} from "src/AlchemicTokenV2.sol";
import {TransmuterV2} from  "src/TransmuterV2.sol";
import {TransmuterBuffer} from "src/TransmuterBuffer.sol";
import {Whitelist} from "src/utils/Whitelist.sol";

import {TestERC20} from "src/test/TestERC20.sol";
import {TestYieldToken} from "src/test/TestYieldToken.sol";
import {TestYieldTokenAdapter} from "src/test/TestYieldTokenAdapter.sol";

import {IERC20Mintable} from "src/interfaces/IERC20Mintable.sol";
import {ITokenAdapter} from "src/interfaces/ITokenAdapter.sol";

import {IAlchemistV2AdminActions} from "src/interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IAlchemistV2} from "src/interfaces/IAlchemistV2.sol";

contract Functionalities is DSTest {

    // Callable contract variables
    AlchemistV2      alchemist;
    TransmuterV2     transmuter;
    TransmuterBuffer transmuterBuffer;

    // Proxy variables
    TransparentUpgradeableProxy proxyAlchemist;
    TransparentUpgradeableProxy proxyTransmuter;
    TransparentUpgradeableProxy proxyTransmuterBuffer;

    // Contract variables
    CheatCodes            cheats = CheatCodes(HEVM_ADDRESS);
    AlchemistV2           alchemistLogic;
    TransmuterV2          transmuterLogic;
    TransmuterBuffer      transmuterBufferLogic;
    AlchemicTokenV2       alToken;
    TestYieldTokenAdapter tokenAdapter;
    Whitelist             whitelist;

    // Token addresses
    address fakeUnderlying;
    address fakeYield;

    // Parameters for AlchemicTokenV2
    string  public _name;
    string  public _symbol;
    uint256 public _flashFee;

    address public alOwner;

    function turnOn(address caller, address proxyOwner) public {
        cheats.assume(caller     != address(0));
        cheats.assume(proxyOwner != address(0));
        cheats.assume(caller     != proxyOwner);
        cheats.startPrank(caller);

        // Fake tokens
        TestERC20 testToken = new TestERC20(0, 18);
        fakeUnderlying = address(testToken);
        TestYieldToken testYieldToken = new TestYieldToken(fakeUnderlying);
        fakeYield = address(testYieldToken);

        // Contracts and logic contracts
        alOwner               = caller;
        alToken               = new AlchemicTokenV2(_name, _symbol, _flashFee);
        tokenAdapter          = new TestYieldTokenAdapter(fakeYield);
        transmuterBufferLogic = new TransmuterBuffer();
        transmuterLogic       = new TransmuterV2();
        alchemistLogic        = new AlchemistV2();
        whitelist             = new Whitelist();

        // Proxy contracts
        // TransmuterBuffer proxy
        bytes memory transBufParams = abi.encodeWithSelector(TransmuterBuffer.initialize.selector,
                                                             alOwner,
                                                             address(alToken));

        proxyTransmuterBuffer = new TransparentUpgradeableProxy(address(transmuterBufferLogic),
                                                                proxyOwner,
                                                                transBufParams);

        transmuterBuffer = TransmuterBuffer(address(proxyTransmuterBuffer));

        // TransmuterV2 proxy
        bytes memory transParams = abi.encodeWithSelector(TransmuterV2.initialize.selector,
                                                          address(alToken),
                                                          fakeUnderlying,
                                                          address(transmuterBuffer),
                                                          whitelist);

        proxyTransmuter = new TransparentUpgradeableProxy(address(transmuterLogic),
                                                          proxyOwner,
                                                          transParams);

        transmuter = TransmuterV2(address(proxyTransmuter));

        // AlchemistV2 proxy
        IAlchemistV2AdminActions.InitializationParams memory params =
            IAlchemistV2AdminActions.InitializationParams({
                admin                    : alOwner,
                debtToken                : address(alToken),
                transmuter               : address(transmuterBuffer),
                minimumCollateralization : 2 * 1e18,
                protocolFee              : 1000,
                protocolFeeReceiver      : address(10),
                mintingLimitMinimum      : 1,
                mintingLimitMaximum      : uint256(type(uint160).max),
                mintingLimitBlocks       : 300,
                whitelist                : address(whitelist)
                });

        bytes memory alchemParams = abi.encodeWithSelector(AlchemistV2.initialize.selector, params);

        proxyAlchemist = new TransparentUpgradeableProxy(address(alchemistLogic), proxyOwner, alchemParams);

        alchemist = AlchemistV2(address(proxyAlchemist));

        // Whitelist alchemist proxy for minting tokens
        alToken.setWhitelist(address(proxyAlchemist), true);
        // Set the alchemist for the transmuterBuffer
        transmuterBuffer.setAlchemist(address(proxyAlchemist));
        // Set the transmuter buffer's transmuter
        transmuterBuffer.setTransmuter(fakeUnderlying, address(transmuter));
        // Set alOwner as a keeper
        alchemist.setKeeper(alOwner, true);
        // Set flow rate for transmuter buffer
        transmuterBuffer.setFlowRate(fakeUnderlying, 325e18);

        cheats.stopPrank();

        // Address labels
        cheats.label(alOwner, "Owner address");
        cheats.label(address(tokenAdapter), "Token adapter");
        cheats.label(fakeYield, "Yield token");
        cheats.label(fakeUnderlying, "Underlying token");
        cheats.label(address(whitelist), "Whitelist contract");
        cheats.label(address(alchemist), "Alchemist proxy");
        cheats.label(address(alchemistLogic), "Alchemist logic");
        cheats.label(address(transmuterBuffer), "Transmuter buffer");
        cheats.label(address(transmuter), "Transmuter");
    }

    function addYieldToken (
		address yieldToken,
		address adapter
	) public {
        IAlchemistV2AdminActions.YieldTokenConfig memory config =
            IAlchemistV2AdminActions.YieldTokenConfig({
            adapter              : adapter,
            maximumLoss          : 1,
            maximumExpectedValue : 1e50,
            creditUnlockBlocks   : 1
        });

        alchemist.addYieldToken(yieldToken, config);
    }

    function addUnderlyingToken (
		address underlyingToken
	) public {
        IAlchemistV2AdminActions.UnderlyingTokenConfig memory config =
            IAlchemistV2AdminActions.UnderlyingTokenConfig({
                repayLimitMinimum       : 1,
                repayLimitMaximum       : 1000,
                repayLimitBlocks        : 10,
                liquidationLimitMinimum : 1,
                liquidationLimitMaximum : 1000,
                liquidationLimitBlocks  : 7200
			});

        alchemist.addUnderlyingToken(underlyingToken, config);
    }

	/*
	 * Initializes a scenario with a CDP for each user
	 */
    function setScenario(
		address caller,
		address proxyOwner,
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList
	) public {
		// Deploy the Alchemix contracts and underlying and yield tokens
        turnOn(caller, proxyOwner);

		// Register underlying and yield token in Alchemist and TransmuterBuffer
		registerTokens(proxyOwner);

		// Creates a CDP for each address userList[i] with enough collateral
		// to mint debtList[i] debt tokens, plus overCollateralList[i] extra
		// collateral
		createCDPs(userList, debtList, overCollateralList);

		// Mint debtList[i] debt tokens from userList[i]'s CDP
		mintDebts(userList, debtList);
    }

    /*
	 * Adds pre-initialized tokens as underlying and yield tokens
	 */
    function registerTokens(address proxyOwner) public {
        cheats.startPrank(alOwner);

		// Register underlying and yield tokens in Alchemist
        addUnderlyingToken(fakeUnderlying);
        alchemist.setUnderlyingTokenEnabled(fakeUnderlying, true);
        addYieldToken(fakeYield, address(tokenAdapter));
        alchemist.setYieldTokenEnabled(fakeYield, true);
		
        // Register underlying token in TransmuterBuffer
        transmuterBuffer.registerAsset(fakeUnderlying, address(transmuter));

        cheats.stopPrank();
    }
	
	/*
	 * Ensure fuzzed arguments are consistent with what we want
	 */
	function ensureConsistency(
		address proxyOwner,
	    address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList
	) public {
		// Ensure there is at least one user
		cheats.assume(1 < userList.length);

		// Ensure there is a debt and a collateral for every user
		// Not == because it would lead to too many inputs being discarded
		// (can just ignore extra debt and collateral entries)
		cheats.assume(userList.length <= debtList.length);
		cheats.assume(debtList.length <= overCollateralList.length);

		// Ensure the user addresses are valid
		for (uint256 i; i < userList.length; ++i) {
			ensureValidUser(proxyOwner, userList[i]);
		}
	}

	/*
	 * Ensure the user is not the 0 address nor the proxy owner
	 */
	function ensureValidUser(address proxyOwner, address user) public {
		cheats.assume(user != address(0));
		cheats.assume(user != proxyOwner);
	}

	/*
	 * Create CDPs for multiple users
	 */
	function createCDPs(
		address[] calldata userList,
		uint96[] calldata debtList,
		uint96[] calldata overCollateralList
	) public {
        for (uint256 i = 0; i < userList.length; ++i) {
			// Label as a user address, to help debugging
            cheats.label(userList[i], "User");

			createCDP(userList[i], debtList[i], overCollateralList[i]);
        }
    }

	/*
	 * Create a CDP for the user with a balance equal to
	 * minimum collateralization * debt + overCollateral
	 */
	function createCDP(
		address user,
		uint96 debt,
		uint96 overCollateral
	) public {
		// Start prank with tx.origin = msg.sender
		cheats.startPrank(user, user);

		// User total balance in underlying tokens =
		// minimum collateralization * debt + overCollateral
		uint256 underlyingBalance = calculateBalance(
			debt, overCollateral, fakeUnderlying
		);

		// Mint underlying tokens to deposit
		assignToUser(user, fakeUnderlying, underlyingBalance);

		// Deposit underlying tokens into the Alchemist
		if (underlyingBalance > 0) {
			alchemist.depositUnderlying(
				fakeYield,
				underlyingBalance,
				user,
				minimumAmountOut(underlyingBalance, fakeYield)
			);
		}
			
		cheats.stopPrank();
    }

	/*
	 * Calculates balance = minimum collateralization * debt + overCollateral
	 */
	function calculateBalance(
		uint256 debt,
		uint256 overCollateral,
		address underlyingToken
	) public returns (uint256)	{
		IAlchemistV2.UnderlyingTokenParams memory params =
			alchemist.getUnderlyingTokenParameters(underlyingToken);

		assert(params.conversionFactor != 0);
		
		// Conversion factor used to normalize debt token amount
		uint256 normalizedDebt = debt / params.conversionFactor;

		uint256 minimumCollateralization =
			alchemist.minimumCollateralization();

		uint256 fixedPointScalar = alchemist.FIXED_POINT_SCALAR();
		uint256 minimumCollateral =
			minimumCollateralization * normalizedDebt / fixedPointScalar;
		
		return minimumCollateral + overCollateral;
	}

	/*
	 * Mints amount tokens to user and approves the Alchemist for spending them
	 */
	function assignToUser(address user, address token, uint256 amount) public {
		IERC20Mintable(token).mint(user, amount);
		IERC20Mintable(token).approve(address(alchemist), amount);
	}

	/*
	 * Returns the minimum amount of yield tokens accepted for a given amount
	 * of underlying tokens
	 */
	function minimumAmountOut(uint256 amount, address yieldToken)
		public view returns (uint256)
	{
		// No slippage accepted
		return amount / yieldTokenPrice(yieldToken);
	}

	/*
	 * Retrieves the current price of the yield token from the adapter
	 */
	function yieldTokenPrice(address yieldToken)
		internal view returns (uint256)
	{
		address adapter = alchemist.getYieldTokenParameters(yieldToken).adapter;

		return ITokenAdapter(adapter).price();
	}

	/*
	 * Mint debt from all users' CDPs
	 */
    function mintDebts(address[] calldata userList,	uint96[] calldata debtList)
		public
	{
        for (uint256 i = 0; i < userList.length; ++i) {
			mintDebt(userList[i], debtList[i]);
        }
    }

	/*
	 * Mint debt from a single user's CDP
	 */
    function mintDebt(address user, uint256 debt) public {
		if (debt > 0) {
			// msg.sender = tx.origin
			cheats.startPrank(user, user);
			
			alchemist.mint(debt, user);
			alToken.approve(address(alchemist), debt);
			
			cheats.stopPrank();
		}
	}
}