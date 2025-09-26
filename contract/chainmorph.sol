// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ChainMorph
 * @dev A morphing token contract that allows dynamic transformation of token properties
 * @author ChainMorph Team
 */
contract ChainMorph is ERC20, Ownable, ReentrancyGuard {
    
    // Struct to define morph stages
    struct MorphStage {
        string name;
        string symbol;
        uint256 multiplier; // Token value multiplier (in basis points, 10000 = 1x)
        uint256 minHoldTime; // Minimum time to hold before morphing (in seconds)
        bool isActive;
    }
    
    // Struct to track user's morph data
    struct UserMorphData {
        uint256 currentStage;
        uint256 lastMorphTime;
        uint256 totalMorphs;
        uint256 lockedTokens;
    }
    
    // State variables
    mapping(uint256 => MorphStage) public morphStages;
    mapping(address => UserMorphData) public userMorphData;
    mapping(address => bool) public morphingEnabled;
    
    uint256 public totalStages;
    uint256 public constant MAX_STAGES = 10;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public morphingFee = 100; // 1% in basis points
    
    // Events
    event TokensMorphed(address indexed user, uint256 fromStage, uint256 toStage, uint256 amount);
    event StageAdded(uint256 indexed stageId, string name, string symbol, uint256 multiplier);
    event MorphingStatusChanged(address indexed user, bool enabled);
    event TokensLocked(address indexed user, uint256 amount, uint256 duration);
    
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        _mint(msg.sender, _initialSupply * 10**decimals());
        
        // Initialize default stage (Stage 0)
        morphStages[0] = MorphStage({
            name: _name,
            symbol: _symbol,
            multiplier: BASIS_POINTS, // 1x multiplier
            minHoldTime: 0,
            isActive: true
        });
        totalStages = 1;
    }
    
    /**
     * @dev Core Function 1: Morph tokens to next stage
     * @param _amount Amount of tokens to morph
     */
    function morphTokens(uint256 _amount) external nonReentrant {
        require(morphingEnabled[msg.sender], "Morphing not enabled for user");
        require(_amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");
        
        UserMorphData storage userData = userMorphData[msg.sender];
        uint256 currentStage = userData.currentStage;
        uint256 nextStage = currentStage + 1;
        
        require(nextStage < totalStages, "No next stage available");
        require(morphStages[nextStage].isActive, "Next stage not active");
        
        // Check minimum hold time
        if (userData.lastMorphTime > 0) {
            require(
                block.timestamp >= userData.lastMorphTime + morphStages[currentStage].minHoldTime,
                "Minimum hold time not met"
            );
        }
        
        // Calculate morphing fee
        uint256 fee = (_amount * morphingFee) / BASIS_POINTS;
        uint256 morphAmount = _amount - fee;
        
        // Apply stage multiplier
        uint256 newTokens = (morphAmount * morphStages[nextStage].multiplier) / BASIS_POINTS;
        
        // Burn original tokens and mint new tokens
        _burn(msg.sender, _amount);
        _mint(msg.sender, newTokens);
        
        // Transfer fee to owner
        if (fee > 0) {
            _mint(owner(), fee);
        }
        
        // Update user data
        userData.currentStage = nextStage;
        userData.lastMorphTime = block.timestamp;
        userData.totalMorphs++;
        
        emit TokensMorphed(msg.sender, currentStage, nextStage, newTokens);
    }
    
    /**
     * @dev Core Function 2: Lock tokens for enhanced morphing benefits
     * @param _amount Amount of tokens to lock
     * @param _duration Lock duration in seconds
     */
    function lockTokens(uint256 _amount, uint256 _duration) external nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        require(_duration >= 86400, "Minimum lock duration is 1 day"); // 24 hours
        require(_duration <= 31536000, "Maximum lock duration is 1 year"); // 365 days
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");
        
        UserMorphData storage userData = userMorphData[msg.sender];
        
        // Transfer tokens to contract (lock them)
        _transfer(msg.sender, address(this), _amount);
        
        // Update locked tokens
        userData.lockedTokens += _amount;
        
        // Enable morphing for user
        morphingEnabled[msg.sender] = true;
        
        emit TokensLocked(msg.sender, _amount, _duration);
        emit MorphingStatusChanged(msg.sender, true);
    }
    
    /**
     * @dev Core Function 3: Add new morph stage (Owner only)
     * @param _name Stage name
     * @param _symbol Stage symbol
     * @param _multiplier Token value multiplier in basis points
     * @param _minHoldTime Minimum hold time before morphing to this stage
     */
    function addMorphStage(
        string memory _name,
        string memory _symbol,
        uint256 _multiplier,
        uint256 _minHoldTime
    ) external onlyOwner {
        require(totalStages < MAX_STAGES, "Maximum stages reached");
        require(_multiplier > 0, "Multiplier must be greater than 0");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_symbol).length > 0, "Symbol cannot be empty");
        
        uint256 stageId = totalStages;
        
        morphStages[stageId] = MorphStage({
            name: _name,
            symbol: _symbol,
            multiplier: _multiplier,
            minHoldTime: _minHoldTime,
            isActive: true
        });
        
        totalStages++;
        
        emit StageAdded(stageId, _name, _symbol, _multiplier);
    }
    
    // View functions
    function getUserMorphData(address _user) external view returns (
        uint256 currentStage,
        uint256 lastMorphTime,
        uint256 totalMorphs,
        uint256 lockedTokens,
        bool canMorph
    ) {
        UserMorphData memory userData = userMorphData[_user];
        currentStage = userData.currentStage;
        lastMorphTime = userData.lastMorphTime;
        totalMorphs = userData.totalMorphs;
        lockedTokens = userData.lockedTokens;
        
        // Check if user can morph to next stage
        canMorph = false;
        if (morphingEnabled[_user] && userData.currentStage + 1 < totalStages) {
            if (userData.lastMorphTime == 0) {
                canMorph = true;
            } else {
                canMorph = block.timestamp >= userData.lastMorphTime + morphStages[userData.currentStage].minHoldTime;
            }
        }
    }
    
    function getMorphStage(uint256 _stageId) external view returns (
        string memory name,
        string memory symbol,
        uint256 multiplier,
        uint256 minHoldTime,
        bool isActive
    ) {
        require(_stageId < totalStages, "Invalid stage ID");
        MorphStage memory stage = morphStages[_stageId];
        return (stage.name, stage.symbol, stage.multiplier, stage.minHoldTime, stage.isActive);
    }
    
    // Admin functions
    function setMorphingFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Fee cannot exceed 10%"); // Max 10%
        morphingFee = _fee;
    }
    
    function toggleStageStatus(uint256 _stageId, bool _isActive) external onlyOwner {
        require(_stageId < totalStages, "Invalid stage ID");
        morphStages[_stageId].isActive = _isActive;
    }
    
    function enableMorphingForUser(address _user, bool _enabled) external onlyOwner {
        morphingEnabled[_user] = _enabled;
        emit MorphingStatusChanged(_user, _enabled);
    }
    
    // Emergency function to withdraw locked tokens (owner only)
    function emergencyWithdraw(address _to, uint256 _amount) external onlyOwner {
        require(_amount <= balanceOf(address(this)), "Insufficient contract balance");
        _transfer(address(this), _to, _amount);
    }
}
