# Decentralized Customs Clearance Smart Contract

A comprehensive blockchain-based solution for managing customs declarations, payments, approvals, and tracking built on the Stacks blockchain using Clarity smart contracts.

## Overview

This smart contract digitizes and decentralizes the customs clearance process, enabling importers to submit declarations, pay fees, and track their shipments while allowing authorized customs officers to review and approve declarations transparently on the blockchain.

## Features

### Core Functionality
- **Declaration Management**: Submit, review, approve, reject, and track customs declarations
- **Payment Processing**: Automated fee calculation and payment in STX
- **Officer Authorization**: Role-based access control for customs officers
- **Importer Registration**: Verified importer profiles with license tracking
- **Expiration Handling**: Automatic declaration expiry with partial refunds
- **Multi-Country Support**: Configurable tax rates and restrictions by country
- **Category Restrictions**: Goods categorization with specific requirements

### Security Features
- Owner-only administrative functions
- Officer authorization verification
- Importer verification system
- Automatic expiration handling
- Emergency withdrawal capabilities

## Contract Structure

### Constants
- `STATUS-PENDING` (0): Initial declaration state
- `STATUS-UNDER-REVIEW` (1): Officer reviewing declaration
- `STATUS-APPROVED` (2): Declaration approved for release
- `STATUS-REJECTED` (3): Declaration rejected with reason
- `STATUS-RELEASED` (4): Goods physically released
- `STATUS-EXPIRED` (5): Declaration expired due to timeout

### Key Data Structures

#### Declarations
```clarity
{
  importer: principal,
  goods-description: string,
  goods-value: uint,
  origin-country: string,
  destination-country: string,
  weight: uint,
  category: string,
  status: uint,
  tracking-number: string,
  customs-fee-paid: uint,
  // ... additional fields
}
```

#### Authorized Officers
```clarity
{
  name: string,
  department: string,
  authorized-at: uint,
  is-active: bool
}
```

#### Importer Profiles
```clarity
{
  name: string,
  license-number: string,
  registration-date: uint,
  total-declarations: uint,
  approved-declarations: uint,
  is-verified: bool
}
```

## Usage

### For Contract Owners

#### Setup Officers
```clarity
(add-customs-officer .officer-wallet "John Doe" "Port Authority")
(verify-importer .importer-wallet)
```

#### Configure Fees and Restrictions
```clarity
(set-customs-fee u2000000) ;; 2 STX
(set-country-tax-rate "CN" u500 false) ;; 5% tax, not restricted
(set-category-restriction "electronics" true u100000 (some u1000000))
```

### For Importers

#### Register Profile
```clarity
(register-importer "ABC Trading Co" "LIC123456")
```

#### Submit Declaration
```clarity
(submit-declaration 
  "Electronic Components - Smartphones" 
  u500000 ;; $500 worth
  "China" 
  "USA" 
  u1000 ;; 1kg
  "electronics"
  "TRK123456789"
)
```

### For Customs Officers

#### Review and Approve
```clarity
(review-declaration u1)
(approve-declaration u1)
(release-goods u1)
```

#### Reject with Reason
```clarity
(reject-declaration u1 "Missing required documentation")
```

## Fee Structure

### Base Fee Calculation
```
Total Fee = Base Fee + Tax Amount + Category Fee
```

Where:
- **Base Fee**: Configurable base processing fee (default: 1 STX)
- **Tax Amount**: `(goods-value × tax-rate) / 10000` (tax-rate in basis points)
- **Category Fee**: Additional fee based on goods category

### Refund Policy
- **Rejected Declarations**: 80% refund
- **Expired Declarations**: 60% refund
- **Processing Fee**: Always retained by the contract

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u100 | ERR-OWNER-ONLY | Action restricted to contract owner |
| u101 | ERR-NOT-FOUND | Requested resource not found |
| u102 | ERR-UNAUTHORIZED-ACCESS | Insufficient permissions |
| u103 | ERR-INVALID-STATUS | Invalid declaration status for action |
| u104 | ERR-INSUFFICIENT-PAYMENT | Payment amount insufficient |
| u105 | ERR-ALREADY-EXISTS | Resource already exists |
| u106 | ERR-INVALID-INPUT | Invalid input parameters |
| u107 | ERR-EXPIRED | Declaration has expired |
| u108 | ERR-INVALID-OFFICER | Officer not authorized |

## Read-Only Functions

### Query Functions
- `get-declaration(uint)`: Get declaration details
- `get-officer-info(principal)`: Get officer information
- `get-importer-profile(principal)`: Get importer profile
- `get-country-info(string)`: Get country tax rates and restrictions
- `get-category-info(string)`: Get category restrictions
- `calculate-fee(uint, string, string)`: Calculate total fees
- `is-declaration-expired(uint)`: Check if declaration expired
- `get-declaration-status(uint)`: Get current declaration status
- `can-officer-review(principal, uint)`: Check officer review permissions

### System State
- `get-customs-fee()`: Current base fee
- `get-processing-time()`: Processing time limit in blocks
- `get-next-declaration-id()`: Next available declaration ID

## Deployment

### Prerequisites
- Stacks blockchain node or access to Stacks testnet/mainnet
- Clarity CLI tools for testing
- STX tokens for contract deployment and testing

### Deployment Steps
1. Deploy contract to Stacks blockchain
2. Set initial configuration (fees, processing time)
3. Add authorized customs officers
4. Configure country tax rates and category restrictions
5. Begin accepting declarations

## Security Considerations

### Best Practices
- Always verify officer authorization before processing
- Implement proper access controls for sensitive functions
- Use time-based expiration to prevent indefinite pending states
- Maintain audit trails for all state changes
- Implement emergency procedures for contract pausing

### Known Limitations
- No native oracles for real-time exchange rates
- Manual officer management (no automated verification)
- Fixed processing times (no dynamic adjustment)
- Single currency support (STX only)