//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Imports
// Relying on openezeppeling reentracy guard and access control, important security features
import "@openzeppelin/contracts/acccess/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


// Start the contract
contract SphereDAO is ReentracyGuard, AccessControl {

  bytes32 public constant CONTRIBUTOR_ROLE = keccak256("CONTRIBUTOR");
  bytes32 public constant STAKEHOLDER_ROLE = keccak256("STAKEHOLDER");

  // minimumVotingPeriod holds the number of days a proposal can be voted on in UNIX time
  uint32 constant minimumVotingPeriod = 1 minutes;

  // Incremented every time a new charityh proposal is added
  uint256 numOfProposals;

  //Sphere proposal is the charity DAO central object, makes up the necessary data that holds each proposal object
  struct CharityProposal {
    uint256 id;
    uint256 amount;
    uint256 livePeriod;
    uint256 votesFor;
    uint256 votesAgainst;
    string description;
    bool votingPassed;
    bool paid;
    address payable charityAddress;
    address proposer;
    address paidBy;
  }

  // Maps a uint256 value and a charity prposal as key and value,
  // holds the list of proposals in the DAO, usses the ID of the proposal
  // as key and the proposal itself as the value
  mapping(uint256 => CharityProposal) private charityProposals;
  // Maps the address of a stakeholder to a list of proposals the address has voted on
  mapping(address => uint256[]) private stakeholderVotes;
  // Maps the contributor adddresses and the amounts they have sent
  mapping(address => uint256) private contributors;
  // Maps the addresses and balances of stakeholders
  mapping(address => uint256) private stakeholders;


  // Events emitted for every new proposal, new contribution and new payment transfer
  event ContributionReceived(address indexed fromAddress, uint256 amount);
  event NewCharityProposal(address indexed proposer, uint256 amount);
  event PaymentTransfered(
    address indexed stakeholder,
    address indexed charityAddress,
    uint256 amount
);

  modifier onlyStakeholder(string memory message) {
    require(hasRole(STAKEHOLDER_ROLE, msg.sender), message);
    _;
  }

  modifier onlyContributor(string memory message) {
    require(hasRole(CONTRIBUTOR_ROLE, msg.sender), message);
    _;
  }

  function createProposal(
          string calldata description,
          address charityAddress,
          uint256 amount
      )
          external
          onlyStakeholder("Only contributors are allowed to make proposals")
      {
          uint256 proposalId = numOfProposals++;
          CharityProposal storage proposal = charityProposals[proposalId];
          proposal.id = proposalId;
          proposal.proposer = payable(msg.sender);
          proposal.description = description;
          proposal.charityAddress = payable(charityAddress);
          proposal.amount = amount;
          proposal.livePeriod = block.timestamp + minimumVotingPeriod;

          emit NewCharityProposal(msg.sender, amount);
      }

      function vote(uint256 proposalId, bool supportProposal)
          external
          onlyStakeholder("Only contributors are allowed to vote")
      {
          CharityProposal storage charityProposal = charityProposals[proposalId];

          votable(charityProposal);

          if (supportProposal) charityProposal.votesFor++;
          else charityProposal.votesAgainst++;

          stakeholderVotes[msg.sender].push(charityProposal.id);
      }

      function votable(CharityProposal storage charityProposal) private {
          if (
              charityProposal.votingPassed ||
              charityProposal.livePeriod <= block.timestamp
          ) {
              charityProposal.votingPassed = true;
              revert("Time is up voting on this proposal");
          }

          uint256[] memory tempVotes = stakeholderVotes[msg.sender];
          for (uint256 votes = 0; votes < tempVotes.length; votes++) {
              if (charityProposal.id == tempVotes[votes])
                  revert("You already voted on this proposal");
          }
      }

      function payCharity(uint256 proposalId)
          external
          onlyStakeholder("Only contributors are allowed to make payments")
      {
          CharityProposal storage charityProposal = charityProposals[proposalId];

          if (charityProposal.paid)
              revert("Payment has been made to the sphere");

          if (charityProposal.votesFor <= charityProposal.votesAgainst)
              revert(
                  "The proposal does not have the required amount of votes to pass"
              );

          charityProposal.paid = true;
          charityProposal.paidBy = msg.sender;

          emit PaymentTransfered(
              msg.sender,
              charityProposal.charityAddress,
              charityProposal.amount
          );

          return charityProposal.charityAddress.transfer(charityProposal.amount);
      }

      receive() external payable {
          emit ContributionReceived(msg.sender, msg.value);
      }

      function makeStakeholder(uint256 amount) external {
          address account = msg.sender;
          uint256 amountContributed = amount;
          if (!hasRole(STAKEHOLDER_ROLE, account)) {
              uint256 totalContributed =
                  contributors[account] + amountContributed;
              if (totalContributed >= 5 ether) {
                  stakeholders[account] = totalContributed;
                  contributors[account] += amountContributed;
                  _setupRole(STAKEHOLDER_ROLE, account);
                  _setupRole(CONTRIBUTOR_ROLE, account);
              } else {
                  contributors[account] += amountContributed;
                  _setupRole(CONTRIBUTOR_ROLE, account);
              }
          } else {
              contributors[account] += amountContributed;
              stakeholders[account] += amountContributed;
          }
      }

      function getProposals()
          public
          view
          returns (CharityProposal[] memory props)
      {
          props = new CharityProposal[](numOfProposals);

          for (uint256 index = 0; index < numOfProposals; index++) {
              props[index] = charityProposals[index];
          }
      }

      function getProposal(uint256 proposalId)
          public
          view
          returns (CharityProposal memory)
      {
          return charityProposals[proposalId];
      }

      function getStakeholderVotes()
          public
          view
          onlyStakeholder("User is not a stakeholder")
          returns (uint256[] memory)
      {
          return stakeholderVotes[msg.sender];
      }

      function getStakeholderBalance()
          public
          view
          onlyStakeholder("User is not a stakeholder")
          returns (uint256)
      {
          return stakeholders[msg.sender];
      }

      function isStakeholder() public view returns (bool) {
          return stakeholders[msg.sender] > 0;
      }

      function getContributorBalance()
          public
          view
          onlyContributor("User is not a contributor")
          returns (uint256)
      {
          return contributors[msg.sender];
      }

      function isContributor() public view returns (bool) {
          return contributors[msg.sender] > 0;
      }
  }
