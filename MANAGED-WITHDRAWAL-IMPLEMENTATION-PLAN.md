# Managed Withdrawal Implementation Plan

## Overview
The managed withdrawal system replaces direct on-chain redemptions with a signature-based request system where users sign EIP-712 withdrawal requests off-chain, and managers process them in batches on-chain.

## Architecture

### Smart Contract Changes (✅ Completed)
- ManagedWithdrawRWA vault contract deployed
- ManagedWithdrawMultiCollateralStrategy deployed  
- EIP-712 signature verification implemented
- Batch redemption functions added
- All contracts verified on Optimism Sepolia

### Frontend Implementation Plan

## 1. User Redemption Request Flow

### A. Redemption Request UI Component (`/src/components/RedemptionRequest.tsx`)
```typescript
interface RedemptionRequestProps {
  vaultBalance: string;
  onSuccess: () => void;
}

Features:
- Amount input with max button
- Estimated redemption value in SovaBTC
- Fee display (if applicable)
- Signature request button
- Transaction status tracking
```

### B. Request Signature Generation
```typescript
// Update /src/lib/signatures/eip712.ts
export const WITHDRAWAL_DOMAIN: TypedDataDomain = {
  name: 'MWMCS', // Shortened for optimized contract
  version: '1',
  chainId: 11155420,
  verifyingContract: '0xf85E2681274eF80Daf3065083E8545590415AF80', // Strategy address
};

export const WITHDRAWAL_TYPES = {
  WithdrawalRequest: [
    { name: 'owner', type: 'address' },
    { name: 'to', type: 'address' },
    { name: 'shares', type: 'uint256' },
    { name: 'minAssets', type: 'uint256' },
    { name: 'nonce', type: 'uint96' },
    { name: 'expirationTime', type: 'uint96' },
  ],
};
```

### C. Request Status Tracking Component (`/src/components/RedemptionStatus.tsx`)
```typescript
Features:
- List of pending requests with status
- Estimated processing time
- Queue position indicator
- Cancel request option (before processing)
- Historical redemptions view
```

## 2. Backend API Implementation

### A. Redemption Request Storage (`fountfi-open-ts`)

#### Database Schema
```sql
CREATE TABLE withdrawal_requests (
  id UUID PRIMARY KEY,
  user_address VARCHAR(42) NOT NULL,
  vault_address VARCHAR(42) NOT NULL,
  shares VARCHAR NOT NULL,
  min_assets VARCHAR DEFAULT '0',
  nonce INTEGER NOT NULL,
  expiration_time TIMESTAMP NOT NULL,
  signature JSON NOT NULL,
  status VARCHAR(20) DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW(),
  processed_at TIMESTAMP,
  transaction_hash VARCHAR(66),
  batch_id UUID,
  UNIQUE(user_address, nonce, vault_address)
);

CREATE TABLE redemption_batches (
  id UUID PRIMARY KEY,
  manager_address VARCHAR(42) NOT NULL,
  transaction_hash VARCHAR(66),
  status VARCHAR(20) DEFAULT 'pending',
  total_shares VARCHAR NOT NULL,
  total_assets VARCHAR NOT NULL,
  request_count INTEGER NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  executed_at TIMESTAMP
);
```

#### API Endpoints
```typescript
// User endpoints
POST   /api/redemptions/request      - Submit signed withdrawal request
GET    /api/redemptions/user/:address - Get user's redemption history
GET    /api/redemptions/status/:id   - Get specific request status
DELETE /api/redemptions/cancel/:id   - Cancel pending request

// Admin endpoints  
GET    /api/admin/redemptions/pending - Get all pending requests
POST   /api/admin/redemptions/batch   - Create redemption batch
POST   /api/admin/redemptions/execute - Execute batch on-chain
GET    /api/admin/redemptions/history - Get batch processing history

// WebSocket events
ws://api/redemptions/subscribe
- Events: request_submitted, request_processed, batch_created, batch_executed
```

## 3. Admin Panel Implementation

### A. Batch Processing Dashboard (`/src/app/admin/redemptions/page.tsx`)
```typescript
Features:
- Pending requests table with filtering/sorting
- Batch creation interface
  - Select requests to include
  - Calculate total SovaBTC needed
  - Estimate gas costs
- One-click batch execution
- Real-time status updates
- Processing history and analytics
```

### B. Liquidity Management View
```typescript
Features:
- Current SovaBTC balance in strategy
- Pending redemption volume
- Liquidity alerts and warnings
- Deposit redemption funds interface
```

## 4. User Experience Improvements

### A. Withdrawal Request Flow
1. User enters withdrawal amount in vBTC shares
2. System shows:
   - Estimated SovaBTC to receive
   - Current queue length
   - Estimated processing time (e.g., "Usually processed within 24-48 hours")
3. User signs EIP-712 message (no gas required)
4. Request submitted to backend
5. User receives confirmation with tracking ID
6. Real-time updates via WebSocket

### B. Status Tracking Page (`/src/app/portfolio/redemptions`)
```typescript
Features:
- Active requests with live status
- Queue position updates
- Estimated time to processing
- Historical redemptions with tx links
- Export functionality for tax purposes
```

## 5. Implementation Steps

### Phase 1: Core Infrastructure (Week 1)
- [ ] Update EIP-712 types for new contract
- [ ] Create redemption request component
- [ ] Implement signature generation flow
- [ ] Set up backend API endpoints
- [ ] Create database schema

### Phase 2: User Interface (Week 2)
- [ ] Build redemption request UI
- [ ] Create status tracking component
- [ ] Add portfolio redemptions page
- [ ] Implement WebSocket notifications
- [ ] Add request cancellation

### Phase 3: Admin Panel (Week 3)
- [ ] Build batch processing dashboard
- [ ] Create liquidity management view
- [ ] Implement batch execution flow
- [ ] Add processing analytics
- [ ] Create admin notifications

### Phase 4: Testing & Polish (Week 4)
- [ ] End-to-end testing
- [ ] Error handling improvements
- [ ] Performance optimization
- [ ] Documentation
- [ ] Deployment to production

## 6. Security Considerations

### Frontend
- Validate all inputs before signing
- Clear signature display for user verification
- Implement request rate limiting
- Add CAPTCHA for spam prevention

### Backend
- Verify signatures before storage
- Implement nonce management
- Add request expiration checks
- Rate limit API endpoints
- Audit trail for all operations

### Smart Contract Integration
- Use multicall for batch operations
- Implement slippage protection
- Add emergency pause mechanism
- Monitor for failed transactions

## 7. Monitoring & Analytics

### Metrics to Track
- Average processing time
- Queue length over time
- Redemption volume trends
- Success/failure rates
- Gas costs per batch
- User satisfaction scores

### Alerting
- High queue length warnings
- Low liquidity alerts
- Failed transaction notifications
- Unusual activity detection

## 8. User Communication

### In-App Notifications
- Request submitted confirmation
- Processing started notification
- Completion with tx link
- Failed request alerts

### Email Notifications (Optional)
- Weekly summary of pending requests
- Processing completion confirmations
- Important system updates

## 9. Migration Strategy

### Transition Period
1. Deploy new contracts (✅ Done)
2. Update frontend with new flow
3. Disable direct redemptions
4. Communicate changes to users
5. Process any pending direct redemptions
6. Full cutover to managed system

### User Education
- In-app tutorial for new flow
- FAQ section
- Video walkthrough
- Support documentation

## 10. Success Metrics

### KPIs
- Redemption processing time < 48 hours
- Batch efficiency > 10 requests per batch
- User satisfaction > 4.5/5
- Zero failed redemptions due to system errors
- Gas cost reduction > 50% vs individual redemptions

### Monitoring Dashboard
- Real-time queue metrics
- Processing time trends
- Volume analytics
- User feedback scores
- System health indicators