pragma solidity ^0.5.0;
import "./ERC20.sol";
import "../token/IERC20.sol";
import "../mimo/IMimoFactory.sol";
import "../mimo/IMimoExchange.sol";

contract MimoExchange is ERC20 {
    /***********************************|
    |        Variables && Events        |
    |__________________________________*/

    // Variables
    string public name; // name of the exchange
    string public symbol; // symbol of the exchange
    uint256 public decimals; // 18
    IERC20 token; // address of the ERC20 token traded on this contract
    IMimoFactory factory; // interface for the factory that created this contract

    // Events
    event TokenPurchase(
        address indexed buyer,
        uint256 indexed iotx_sold,
        uint256 indexed tokens_bought
    );
    event IotxPurchase(
        address indexed buyer,
        uint256 indexed tokens_sold,
        uint256 indexed iotx_bought
    );
    event AddLiquidity(
        address indexed provider,
        uint256 indexed iotx_amount,
        uint256 indexed token_amount
    );
    event RemoveLiquidity(
        address indexed provider,
        uint256 indexed iotx_amount,
        uint256 indexed token_amount
    );

    /***********************************|
    |            Constsructor           |
    |__________________________________*/

        /**
        * @dev This function acts as a contract constructor which is not currently supported in contracts deployed
        *      using create_with_code_of(). It is called once by the factory during contract creation.
        */
        function setup(address token_addr) public {
            require(
                address(factory) == address(0) &&
                    address(token) == address(0) &&
                    token_addr != address(0),
                "INVALID_ADDRESS"
            );
            factory = IMimoFactory(msg.sender);
            token = IERC20(token_addr);
            name = string(abi.encodePacked("mimo LP Token: ", token.symbol(), "-IOTX"));
            symbol = string(abi.encodePacked("MLP:", token.symbol(), "-IOTX"));
            decimals = 18;
        }

    /***********************************|
    |        Exchange Functions         |
    |__________________________________*/

    /**
     * @notice Convert IOTX to Tokens.
     * @dev User specifies exact input (msg.value).
     * @dev User cannot specify minimum output or deadline.
     */
    function() external payable {
        iotxToTokenInput(msg.value, 1, block.timestamp, msg.sender, msg.sender);
    }

    /**
     * @dev Pricing function for converting between IOTX && Tokens.
     * @param input_amount Amount of IOTX or Tokens being sold.
     * @param input_reserve Amount of IOTX or Tokens (input type) in exchange reserves.
     * @param output_reserve Amount of IOTX or Tokens (output type) in exchange reserves.
     * @return Amount of IOTX or Tokens bought.
     */
    function getInputPrice(
        uint256 input_amount,
        uint256 input_reserve,
        uint256 output_reserve
    ) public pure returns (uint256) {
        require(input_reserve > 0 && output_reserve > 0, "INVALID_VALUE");
        uint256 input_amount_with_fee = input_amount.mul(997);
        uint256 numerator = input_amount_with_fee.mul(output_reserve);
        uint256 denominator = input_reserve.mul(1000).add(
            input_amount_with_fee
        );
        return numerator / denominator;
    }

    /**
     * @dev Pricing function for converting between IOTX && Tokens.
     * @param output_amount Amount of IOTX or Tokens being bought.
     * @param input_reserve Amount of IOTX or Tokens (input type) in exchange reserves.
     * @param output_reserve Amount of IOTX or Tokens (output type) in exchange reserves.
     * @return Amount of IOTX or Tokens sold.
     */
    function getOutputPrice(
        uint256 output_amount,
        uint256 input_reserve,
        uint256 output_reserve
    ) public pure returns (uint256) {
        require(input_reserve > 0 && output_reserve > 0);
        uint256 numerator = input_reserve.mul(output_amount).mul(1000);
        uint256 denominator = (output_reserve.sub(output_amount)).mul(997);
        return (numerator / denominator).add(1);
    }

    function iotxToTokenInput(
        uint256 iotx_sold,
        uint256 min_tokens,
        uint256 deadline,
        address buyer,
        address recipient
    ) private returns (uint256) {
        require(deadline >= block.timestamp && iotx_sold > 0 && min_tokens > 0);
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 tokens_bought = getInputPrice(
            iotx_sold,
            address(this).balance.sub(iotx_sold),
            token_reserve
        );
        require(tokens_bought >= min_tokens);
        require(token.transfer(recipient, tokens_bought));
        emit TokenPurchase(buyer, iotx_sold, tokens_bought);
        return tokens_bought;
    }

    /**
     * @notice Convert IOTX to Tokens.
     * @dev User specifies exact input (msg.value) && minimum output.
     * @param min_tokens Minimum Tokens bought.
     * @param deadline Time after which this transaction can no longer be executed.
     * @return Amount of Tokens bought.
     */

    function iotxToTokenSwapInput(uint256 min_tokens, uint256 deadline)
        public
        payable
        returns (uint256)
    {
        return
            iotxToTokenInput(
                msg.value,
                min_tokens,
                deadline,
                msg.sender,
                msg.sender
            );
    }

    /**
     * @notice Convert IOTX to Tokens && transfers Tokens to recipient.
     * @dev User specifies exact input (msg.value) && minimum output
     * @param min_tokens Minimum Tokens bought.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param recipient The address that receives output Tokens.
     * @return  Amount of Tokens bought.
     */
    function iotxToTokenTransferInput(
        uint256 min_tokens,
        uint256 deadline,
        address recipient
    ) public payable returns (uint256) {
        require(recipient != address(this) && recipient != address(0));
        return
            iotxToTokenInput(
                msg.value,
                min_tokens,
                deadline,
                msg.sender,
                recipient
            );
    }

    function iotxToTokenOutput(
        uint256 tokens_bought,
        uint256 max_iotx,
        uint256 deadline,
        address payable buyer,
        address recipient
    ) private returns (uint256) {
        require(
            deadline >= block.timestamp && tokens_bought > 0 && max_iotx > 0
        );
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 iotx_sold = getOutputPrice(
            tokens_bought,
            address(this).balance.sub(max_iotx),
            token_reserve
        );
        // Throws if iotx_sold > max_iotx
        uint256 iotx_refund = max_iotx.sub(iotx_sold);
        if (iotx_refund > 0) {
            buyer.transfer(iotx_refund);
        }
        require(token.transfer(recipient, tokens_bought));
        emit TokenPurchase(buyer, iotx_sold, tokens_bought);
        return iotx_sold;
    }

    /**
     * @notice Convert IOTX to Tokens.
     * @dev User specifies maximum input (msg.value) && exact output.
     * @param tokens_bought Amount of tokens bought.
     * @param deadline Time after which this transaction can no longer be executed.
     * @return Amount of IOTX sold.
     */
    function iotxToTokenSwapOutput(uint256 tokens_bought, uint256 deadline)
        public
        payable
        returns (uint256)
    {
        return
            iotxToTokenOutput(
                tokens_bought,
                msg.value,
                deadline,
                msg.sender,
                msg.sender
            );
    }

    /**
     * @notice Convert IOTX to Tokens && transfers Tokens to recipient.
     * @dev User specifies maximum input (msg.value) && exact output.
     * @param tokens_bought Amount of tokens bought.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param recipient The address that receives output Tokens.
     * @return Amount of IOTX sold.
     */
    function iotxToTokenTransferOutput(
        uint256 tokens_bought,
        uint256 deadline,
        address recipient
    ) public payable returns (uint256) {
        require(recipient != address(this) && recipient != address(0));
        return
            iotxToTokenOutput(
                tokens_bought,
                msg.value,
                deadline,
                msg.sender,
                recipient
            );
    }

    function tokenToIotxInput(
        uint256 tokens_sold,
        uint256 min_iotx,
        uint256 deadline,
        address buyer,
        address payable recipient
    ) private returns (uint256) {
        require(deadline >= block.timestamp && tokens_sold > 0 && min_iotx > 0);
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 iotx_bought = getInputPrice(
            tokens_sold,
            token_reserve,
            address(this).balance
        );
        uint256 wei_bought = iotx_bought;
        require(wei_bought >= min_iotx);
        recipient.transfer(wei_bought);
        require(token.transferFrom(buyer, address(this), tokens_sold));
        emit IotxPurchase(buyer, tokens_sold, wei_bought);
        return wei_bought;
    }

    /**
     * @notice Convert Tokens to IOTX.
     * @dev User specifies exact input && minimum output.
     * @param tokens_sold Amount of Tokens sold.
     * @param min_iotx Minimum IOTX purchased.
     * @param deadline Time after which this transaction can no longer be executed.
     * @return Amount of IOTX bought.
     */
    function tokenToIotxSwapInput(
        uint256 tokens_sold,
        uint256 min_iotx,
        uint256 deadline
    ) public returns (uint256) {
        return
            tokenToIotxInput(
                tokens_sold,
                min_iotx,
                deadline,
                msg.sender,
                msg.sender
            );
    }

    /**
     * @notice Convert Tokens to IOTX && transfers IOTX to recipient.
     * @dev User specifies exact input && minimum output.
     * @param tokens_sold Amount of Tokens sold.
     * @param min_iotx Minimum IOTX purchased.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param recipient The address that receives output IOTX.
     * @return  Amount of IOTX bought.
     */
    function tokenToIotxTransferInput(
        uint256 tokens_sold,
        uint256 min_iotx,
        uint256 deadline,
        address payable recipient
    ) public returns (uint256) {
        require(recipient != address(this) && recipient != address(0));
        return
            tokenToIotxInput(
                tokens_sold,
                min_iotx,
                deadline,
                msg.sender,
                recipient
            );
    }

    function tokenToIotxOutput(
        uint256 iotx_bought,
        uint256 max_tokens,
        uint256 deadline,
        address buyer,
        address payable recipient
    ) private returns (uint256) {
        require(deadline >= block.timestamp && iotx_bought > 0);
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 tokens_sold = getOutputPrice(
            iotx_bought,
            token_reserve,
            address(this).balance
        );
        // tokens sold is always > 0
        require(max_tokens >= tokens_sold);
        recipient.transfer(iotx_bought);
        require(token.transferFrom(buyer, address(this), tokens_sold));
        emit IotxPurchase(buyer, tokens_sold, iotx_bought);
        return tokens_sold;
    }

    /**
     * @notice Convert Tokens to IOTX.
     * @dev User specifies maximum input && exact output.
     * @param iotx_bought Amount of IOTX purchased.
     * @param max_tokens Maximum Tokens sold.
     * @param deadline Time after which this transaction can no longer be executed.
     * @return Amount of Tokens sold.
     */
    function tokenToIotxSwapOutput(
        uint256 iotx_bought,
        uint256 max_tokens,
        uint256 deadline
    ) public returns (uint256) {
        return
            tokenToIotxOutput(
                iotx_bought,
                max_tokens,
                deadline,
                msg.sender,
                msg.sender
            );
    }

    /**
     * @notice Convert Tokens to IOTX && transfers IOTX to recipient.
     * @dev User specifies maximum input && exact output.
     * @param iotx_bought Amount of IOTX purchased.
     * @param max_tokens Maximum Tokens sold.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param recipient The address that receives output IOTX.
     * @return Amount of Tokens sold.
     */
    function tokenToIotxTransferOutput(
        uint256 iotx_bought,
        uint256 max_tokens,
        uint256 deadline,
        address payable recipient
    ) public returns (uint256) {
        require(recipient != address(this) && recipient != address(0));
        return
            tokenToIotxOutput(
                iotx_bought,
                max_tokens,
                deadline,
                msg.sender,
                recipient
            );
    }

    function tokenToTokenInput(
        uint256 tokens_sold,
        uint256 min_tokens_bought,
        uint256 min_iotx_bought,
        uint256 deadline,
        address buyer,
        address recipient,
        address payable exchange_addr
    ) private returns (uint256) {
        require(
            deadline >= block.timestamp &&
                tokens_sold > 0 &&
                min_tokens_bought > 0 &&
                min_iotx_bought > 0
        );
        require(exchange_addr != address(this) && exchange_addr != address(0));
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 iotx_bought = getInputPrice(
            tokens_sold,
            token_reserve,
            address(this).balance
        );
        uint256 wei_bought = iotx_bought;
        require(wei_bought >= min_iotx_bought);
        require(token.transferFrom(buyer, address(this), tokens_sold));
        uint256 tokens_bought = IMimoExchange(exchange_addr)
            .iotxToTokenTransferInput
            .value(wei_bought)(min_tokens_bought, deadline, recipient);
        emit IotxPurchase(buyer, tokens_sold, wei_bought);
        return tokens_bought;
    }

    /**
     * @notice Convert Tokens (token) to Tokens (token_addr).
     * @dev User specifies exact input && minimum output.
     * @param tokens_sold Amount of Tokens sold.
     * @param min_tokens_bought Minimum Tokens (token_addr) purchased.
     * @param min_iotx_bought Minimum IOTX purchased as intermediary.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param token_addr The address of the token being purchased.
     * @return Amount of Tokens (token_addr) bought.
     */
    function tokenToTokenSwapInput(
        uint256 tokens_sold,
        uint256 min_tokens_bought,
        uint256 min_iotx_bought,
        uint256 deadline,
        address token_addr
    ) public returns (uint256) {
        address payable exchange_addr = factory.getExchange(token_addr);
        return
            tokenToTokenInput(
                tokens_sold,
                min_tokens_bought,
                min_iotx_bought,
                deadline,
                msg.sender,
                msg.sender,
                exchange_addr
            );
    }

    /**
     * @notice Convert Tokens (token) to Tokens (token_addr) && transfers
     *         Tokens (token_addr) to recipient.
     * @dev User specifies exact input && minimum output.
     * @param tokens_sold Amount of Tokens sold.
     * @param min_tokens_bought Minimum Tokens (token_addr) purchased.
     * @param min_iotx_bought Minimum IOTX purchased as intermediary.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param recipient The address that receives output IOTX.
     * @param token_addr The address of the token being purchased.
     * @return Amount of Tokens (token_addr) bought.
     */
    function tokenToTokenTransferInput(
        uint256 tokens_sold,
        uint256 min_tokens_bought,
        uint256 min_iotx_bought,
        uint256 deadline,
        address recipient,
        address token_addr
    ) public returns (uint256) {
        address payable exchange_addr = factory.getExchange(token_addr);
        return
            tokenToTokenInput(
                tokens_sold,
                min_tokens_bought,
                min_iotx_bought,
                deadline,
                msg.sender,
                recipient,
                exchange_addr
            );
    }

    function tokenToTokenOutput(
        uint256 tokens_bought,
        uint256 max_tokens_sold,
        uint256 max_iotx_sold,
        uint256 deadline,
        address buyer,
        address recipient,
        address payable exchange_addr
    ) private returns (uint256) {
        require(
            deadline >= block.timestamp &&
                (tokens_bought > 0 && max_iotx_sold > 0)
        );
        require(exchange_addr != address(this) && exchange_addr != address(0));
        uint256 iotx_bought = IMimoExchange(exchange_addr)
            .getIotxToTokenOutputPrice(tokens_bought);
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 tokens_sold = getOutputPrice(
            iotx_bought,
            token_reserve,
            address(this).balance
        );
        // tokens sold is always > 0
        require(max_tokens_sold >= tokens_sold && max_iotx_sold >= iotx_bought);
        require(token.transferFrom(buyer, address(this), tokens_sold));
        uint256 iotx_sold = IMimoExchange(exchange_addr)
            .iotxToTokenTransferOutput
            .value(iotx_bought)(tokens_bought, deadline, recipient);
        emit IotxPurchase(buyer, tokens_sold, iotx_bought);
        return tokens_sold;
    }

    /**
     * @notice Convert Tokens (token) to Tokens (token_addr).
     * @dev User specifies maximum input && exact output.
     * @param tokens_bought Amount of Tokens (token_addr) bought.
     * @param max_tokens_sold Maximum Tokens (token) sold.
     * @param max_iotx_sold Maximum IOTX purchased as intermediary.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param token_addr The address of the token being purchased.
     * @return Amount of Tokens (token) sold.
     */
    function tokenToTokenSwapOutput(
        uint256 tokens_bought,
        uint256 max_tokens_sold,
        uint256 max_iotx_sold,
        uint256 deadline,
        address token_addr
    ) public returns (uint256) {
        address payable exchange_addr = factory.getExchange(token_addr);
        return
            tokenToTokenOutput(
                tokens_bought,
                max_tokens_sold,
                max_iotx_sold,
                deadline,
                msg.sender,
                msg.sender,
                exchange_addr
            );
    }

    /**
     * @notice Convert Tokens (token) to Tokens (token_addr) && transfers
     *         Tokens (token_addr) to recipient.
     * @dev User specifies maximum input && exact output.
     * @param tokens_bought Amount of Tokens (token_addr) bought.
     * @param max_tokens_sold Maximum Tokens (token) sold.
     * @param max_iotx_sold Maximum IOTX purchased as intermediary.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param recipient The address that receives output IOTX.
     * @param token_addr The address of the token being purchased.
     * @return Amount of Tokens (token) sold.
     */
    function tokenToTokenTransferOutput(
        uint256 tokens_bought,
        uint256 max_tokens_sold,
        uint256 max_iotx_sold,
        uint256 deadline,
        address recipient,
        address token_addr
    ) public returns (uint256) {
        address payable exchange_addr = factory.getExchange(token_addr);
        return
            tokenToTokenOutput(
                tokens_bought,
                max_tokens_sold,
                max_iotx_sold,
                deadline,
                msg.sender,
                recipient,
                exchange_addr
            );
    }

    /**
     * @notice Convert Tokens (token) to Tokens (exchange_addr.token).
     * @dev Allows trades through contracts that were not deployed from the same factory.
     * @dev User specifies exact input && minimum output.
     * @param tokens_sold Amount of Tokens sold.
     * @param min_tokens_bought Minimum Tokens (token_addr) purchased.
     * @param min_iotx_bought Minimum IOTX purchased as intermediary.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param exchange_addr The address of the exchange for the token being purchased.
     * @return Amount of Tokens (exchange_addr.token) bought.
     */
    function tokenToExchangeSwapInput(
        uint256 tokens_sold,
        uint256 min_tokens_bought,
        uint256 min_iotx_bought,
        uint256 deadline,
        address payable exchange_addr
    ) public returns (uint256) {
        return
            tokenToTokenInput(
                tokens_sold,
                min_tokens_bought,
                min_iotx_bought,
                deadline,
                msg.sender,
                msg.sender,
                exchange_addr
            );
    }

    /**
     * @notice Convert Tokens (token) to Tokens (exchange_addr.token) && transfers
     *         Tokens (exchange_addr.token) to recipient.
     * @dev Allows trades through contracts that were not deployed from the same factory.
     * @dev User specifies exact input && minimum output.
     * @param tokens_sold Amount of Tokens sold.
     * @param min_tokens_bought Minimum Tokens (token_addr) purchased.
     * @param min_iotx_bought Minimum IOTX purchased as intermediary.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param recipient The address that receives output IOTX.
     * @param exchange_addr The address of the exchange for the token being purchased.
     * @return Amount of Tokens (exchange_addr.token) bought.
     */
    function tokenToExchangeTransferInput(
        uint256 tokens_sold,
        uint256 min_tokens_bought,
        uint256 min_iotx_bought,
        uint256 deadline,
        address recipient,
        address payable exchange_addr
    ) public returns (uint256) {
        require(recipient != address(this));
        return
            tokenToTokenInput(
                tokens_sold,
                min_tokens_bought,
                min_iotx_bought,
                deadline,
                msg.sender,
                recipient,
                exchange_addr
            );
    }

    /**
     * @notice Convert Tokens (token) to Tokens (exchange_addr.token).
     * @dev Allows trades through contracts that were not deployed from the same factory.
     * @dev User specifies maximum input && exact output.
     * @param tokens_bought Amount of Tokens (token_addr) bought.
     * @param max_tokens_sold Maximum Tokens (token) sold.
     * @param max_iotx_sold Maximum IOTX purchased as intermediary.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param exchange_addr The address of the exchange for the token being purchased.
     * @return Amount of Tokens (token) sold.
     */
    function tokenToExchangeSwapOutput(
        uint256 tokens_bought,
        uint256 max_tokens_sold,
        uint256 max_iotx_sold,
        uint256 deadline,
        address payable exchange_addr
    ) public returns (uint256) {
        return
            tokenToTokenOutput(
                tokens_bought,
                max_tokens_sold,
                max_iotx_sold,
                deadline,
                msg.sender,
                msg.sender,
                exchange_addr
            );
    }

    /**
     * @notice Convert Tokens (token) to Tokens (exchange_addr.token) && transfers
     *         Tokens (exchange_addr.token) to recipient.
     * @dev Allows trades through contracts that were not deployed from the same factory.
     * @dev User specifies maximum input && exact output.
     * @param tokens_bought Amount of Tokens (token_addr) bought.
     * @param max_tokens_sold Maximum Tokens (token) sold.
     * @param max_iotx_sold Maximum IOTX purchased as intermediary.
     * @param deadline Time after which this transaction can no longer be executed.
     * @param recipient The address that receives output IOTX.
     * @param exchange_addr The address of the exchange for the token being purchased.
     * @return Amount of Tokens (token) sold.
     */
    function tokenToExchangeTransferOutput(
        uint256 tokens_bought,
        uint256 max_tokens_sold,
        uint256 max_iotx_sold,
        uint256 deadline,
        address recipient,
        address payable exchange_addr
    ) public returns (uint256) {
        require(recipient != address(this));
        return
            tokenToTokenOutput(
                tokens_bought,
                max_tokens_sold,
                max_iotx_sold,
                deadline,
                msg.sender,
                recipient,
                exchange_addr
            );
    }

    /***********************************|
  |         Getter Functions          |
  |__________________________________*/

    /**
     * @notice Public price function for IOTX to Token trades with an exact input.
     * @param iotx_sold Amount of IOTX sold.
     * @return Amount of Tokens that can be bought with input IOTX.
     */
    function getIotxToTokenInputPrice(uint256 iotx_sold)
        public
        view
        returns (uint256)
    {
        require(iotx_sold > 0);
        uint256 token_reserve = token.balanceOf(address(this));
        return getInputPrice(iotx_sold, address(this).balance, token_reserve);
    }

    /**
     * @notice Public price function for IOTX to Token trades with an exact output.
     * @param tokens_bought Amount of Tokens bought.
     * @return Amount of IOTX needed to buy output Tokens.
     */
    function getIotxToTokenOutputPrice(uint256 tokens_bought)
        public
        view
        returns (uint256)
    {
        require(tokens_bought > 0);
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 iotx_sold = getOutputPrice(
            tokens_bought,
            address(this).balance,
            token_reserve
        );
        return iotx_sold;
    }

    /**
     * @notice Public price function for Token to IOTX trades with an exact input.
     * @param tokens_sold Amount of Tokens sold.
     * @return Amount of IOTX that can be bought with input Tokens.
     */
    function getTokenToIotxInputPrice(uint256 tokens_sold)
        public
        view
        returns (uint256)
    {
        require(tokens_sold > 0);
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 iotx_bought = getInputPrice(
            tokens_sold,
            token_reserve,
            address(this).balance
        );
        return iotx_bought;
    }

    /**
     * @notice Public price function for Token to IOTX trades with an exact output.
     * @param iotx_bought Amount of output IOTX.
     * @return Amount of Tokens needed to buy output IOTX.
     */
    function getTokenToIotxOutputPrice(uint256 iotx_bought)
        public
        view
        returns (uint256)
    {
        require(iotx_bought > 0);
        uint256 token_reserve = token.balanceOf(address(this));
        return
            getOutputPrice(iotx_bought, token_reserve, address(this).balance);
    }

    /**
     * @return Address of Token that is sold on this exchange.
     */
    function tokenAddress() public view returns (address) {
        return address(token);
    }

    /**
     * @return Address of factory that created this exchange.
     */
    function factoryAddress() public view returns (address) {
        return address(factory);
    }

    /***********************************|
  |        Liquidity Functions        |
  |__________________________________*/

    /**
     * @notice Deposit IOTX && Tokens (token) at current ratio to mint MLP tokens.
     * @dev min_liquidity does nothing when total MLP supply is 0.
     * @param min_liquidity Minimum number of MLP sender will mint if total MLP supply is greater than 0.
     * @param max_tokens Maximum number of tokens deposited. Deposits max amount if total MLP supply is 0.
     * @param deadline Time after which this transaction can no longer be executed.
     * @return The amount of MLP minted.
     */
    function addLiquidity(
        uint256 min_liquidity,
        uint256 max_tokens,
        uint256 deadline
    ) public payable returns (uint256) {
        require(
            deadline > block.timestamp && max_tokens > 0 && msg.value > 0,
            "MimoExchange#addLiquidity: INVALID_ARGUMENT"
        );
        uint256 total_liquidity = _totalSupply;

        if (total_liquidity > 0) {
            require(min_liquidity > 0);
            uint256 iotx_reserve = address(this).balance.sub(msg.value);
            uint256 token_reserve = token.balanceOf(address(this));
            uint256 token_amount = (msg.value.mul(token_reserve) / iotx_reserve)
                .add(1);
            uint256 liquidity_minted = msg.value.mul(total_liquidity) /
                iotx_reserve;
            require(
                max_tokens >= token_amount && liquidity_minted >= min_liquidity
            );
            _balances[msg.sender] = _balances[msg.sender].add(liquidity_minted);
            _totalSupply = total_liquidity.add(liquidity_minted);
            require(
                token.transferFrom(msg.sender, address(this), token_amount)
            );
            emit AddLiquidity(msg.sender, msg.value, token_amount);
            emit Transfer(address(0), msg.sender, liquidity_minted);
            return liquidity_minted;
        } else {
            require(
                address(factory) != address(0) &&
                    address(token) != address(0) &&
                    msg.value >= 1000000000,
                "INVALID_VALUE"
            );
            require(factory.getExchange(address(token)) == address(this));
            uint256 token_amount = max_tokens;
            uint256 initial_liquidity = address(this).balance;
            _totalSupply = initial_liquidity;
            _balances[msg.sender] = initial_liquidity;
            require(
                token.transferFrom(msg.sender, address(this), token_amount)
            );
            emit AddLiquidity(msg.sender, msg.value, token_amount);
            emit Transfer(address(0), msg.sender, initial_liquidity);
            return initial_liquidity;
        }
    }

    /**
     * @dev Burn MLP tokens to withdraw IOTX && Tokens at current ratio.
     * @param amount Amount of MLP burned.
     * @param min_iotx Minimum IOTX withdrawn.
     * @param min_tokens Minimum Tokens withdrawn.
     * @param deadline Time after which this transaction can no longer be executed.
     * @return The amount of IOTX && Tokens withdrawn.
     */
    function removeLiquidity(
        uint256 amount,
        uint256 min_iotx,
        uint256 min_tokens,
        uint256 deadline
    ) public returns (uint256, uint256) {
        require(
            amount > 0 &&
                deadline > block.timestamp &&
                min_iotx > 0 &&
                min_tokens > 0
        );
        uint256 total_liquidity = _totalSupply;
        require(total_liquidity > 0);
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 iotx_amount = amount.mul(address(this).balance) /
            total_liquidity;
        uint256 token_amount = amount.mul(token_reserve) / total_liquidity;
        require(iotx_amount >= min_iotx && token_amount >= min_tokens);

        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        _totalSupply = total_liquidity.sub(amount);
        msg.sender.transfer(iotx_amount);
        require(token.transfer(msg.sender, token_amount));
        emit RemoveLiquidity(msg.sender, iotx_amount, token_amount);
        emit Transfer(msg.sender, address(0), amount);
        return (iotx_amount, token_amount);
    }
}
