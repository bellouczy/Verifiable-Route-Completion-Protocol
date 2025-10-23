# 🚚 Verifiable Route Completion Protocol

> A blockchain-based delivery verification system using GPS checkpoints and automatic payments

## 📋 Overview

The Verifiable Route Completion Protocol enables trustless delivery verification through GPS-verified checkpoints. Shippers create routes with predefined checkpoints, transporters prove successful delivery by submitting GPS proofs, and payments are automatically released upon route completion.

## ✨ Features

- 🗺️ **GPS-Verified Checkpoints** - Define precise locations with tolerance margins
- 💰 **Automatic Payments** - Escrow funds released upon completion
- ⏱️ **Time-Based Deadlines** - Checkpoints must be verified within deadline
- 📊 **Transporter Statistics** - Track completed routes and earnings
- 🔒 **Trustless Verification** - On-chain proof of delivery

## 🎯 Core Functions

### Creating Routes

```clarity
(create-route transporter payment-amount total-checkpoints)
```

Creates a new delivery route with escrow payment.

**Parameters:**
- `transporter` (principal) - Address of the transporter
- `payment-amount` (uint) - STX amount locked in escrow
- `total-checkpoints` (uint) - Number of checkpoints required

**Returns:** Route ID

### Adding Checkpoints

```clarity
(add-checkpoint route-id latitude longitude tolerance deadline-blocks)
```

Adds a GPS checkpoint to an active route.

**Parameters:**
- `route-id` (uint) - The route identifier
- `latitude` (int) - GPS latitude (-90000000 to 90000000)
- `longitude` (int) - GPS longitude (-180000000 to 180000000)
- `tolerance` (uint) - Acceptable distance variance
- `deadline-blocks` (uint) - Blocks until checkpoint expires

**Returns:** Checkpoint ID

### Verifying Checkpoints

```clarity
(verify-checkpoint route-id checkpoint-id actual-lat actual-lon)
```

Submit GPS proof to verify checkpoint arrival.

**Parameters:**
- `route-id` (uint) - The route identifier
- `checkpoint-id` (uint) - The checkpoint identifier
- `actual-lat` (int) - Actual GPS latitude
- `actual-lon` (int) - Actual GPS longitude

**Returns:** Success boolean (triggers automatic payment if route completed)

### Canceling Routes

```clarity
(cancel-route route-id)
```

Cancel an active route with no verified checkpoints (shipper only).

**Returns:** Success boolean

## 📖 Read-Only Functions

### Get Route Information

```clarity
(get-route route-id)
```

Returns complete route details including status and progress.

### Get Checkpoint Details

```clarity
(get-checkpoint route-id checkpoint-id)
```

Returns checkpoint coordinates, verification status, and deadline.

### Get Payment Information

```clarity
(get-payment-info route-id)
```

Returns escrow amount and release status.

### Get Transporter Statistics

```clarity
(get-transporter-stats transporter)
```

Returns total routes completed, earnings, and success rate.

### Get Route Progress

```clarity
(get-route-progress route-id)
```

Returns verified vs total checkpoints and completion percentage.

### Validate Coordinates

```clarity
(is-checkpoint-valid route-id checkpoint-id actual-lat actual-lon)
```

Check if coordinates fall within checkpoint tolerance (before submitting).

## 🚀 Usage Example

### 1. Shipper Creates Route

```clarity
(contract-call? .Verifiable-Route-Completion-Protocol create-route 
    'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 
    u1000000 
    u3)
```

### 2. Shipper Adds Checkpoints

```clarity
(contract-call? .Verifiable-Route-Completion-Protocol add-checkpoint 
    u0 
    40748817 
    -73985428 
    u100000 
    u144)
```

### 3. Transporter Verifies Checkpoint

```clarity
(contract-call? .Verifiable-Route-Completion-Protocol verify-checkpoint 
    u0 
    u0 
    40748850 
    -73985400)
```

### 4. Automatic Payment

When all checkpoints are verified, payment automatically transfers to transporter.

## 🔐 Security Features

- **Escrow Protection** - Payments locked in contract until completion
- **Coordinate Validation** - GPS bounds checking prevents invalid data
- **Authorization Checks** - Only authorized parties can perform actions
- **Deadline Enforcement** - Time-bound checkpoint verification
- **Double-Verification Prevention** - Checkpoints can only be verified once

## 📊 Route Statuses

- `active` - Route in progress
- `completed` - All checkpoints verified, payment released
- `cancelled` - Route cancelled by shipper

## 🧪 Testing

Run the test suite:

```bash
clarinet test
```

Check contract validity:

```bash
clarinet check
```

## 📝 Error Codes

| Code | Description |
|------|-------------|
| u100 | Owner only action |
| u101 | Route/checkpoint not found |
| u102 | Unauthorized action |
| u103 | Resource already exists |
| u104 | Invalid checkpoint |
| u105 | Route not active |
| u106 | Insufficient payment |
| u107 | Already verified |
| u108 | Route completed |
| u109 | Invalid coordinates |
| u110 | Checkpoint expired |

## 🏗️ Technical Details

**Coordinate Format:** Coordinates are stored as integers (multiplied by 10^6 for precision)
- Example: 40.748817° → 40748817
- Valid latitude range: -90000000 to 90000000
- Valid longitude range: -180000000 to 180000000

**Tolerance:** Distance variance in coordinate units (higher = more flexible)

**Deadlines:** Measured in Stacks blocks from checkpoint creation

## 📄 License

MIT

## 🤝 Contributing

Contributions welcome! Please open an issue or submit a pull request.

---

Built with ❤️ on Stacks
