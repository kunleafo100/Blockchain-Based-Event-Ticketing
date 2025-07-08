# 🎫 Blockchain-Based Event Ticketing

A decentralized event ticketing system built on Stacks blockchain that issues NFTs as event tickets with advanced features like resale limits, time restrictions, and refund conditions.

## ✨ Features

- 🎟️ **NFT Tickets**: Each ticket is a unique NFT with metadata
- 🔄 **Controlled Resales**: Set maximum number of resales per ticket
- ⏰ **Time Restrictions**: Tickets expire after event start time
- 💰 **Refund System**: Automatic refunds before deadline
- 👑 **Royalty System**: Organizers earn from resales
- 🚫 **Event Cancellation**: Emergency refunds for cancelled events
- 🔒 **Anti-Fraud**: Tickets can only be used once by organizers

## 🚀 Quick Start

### Deploy the Contract

```bash
clarinet deploy --testnet
```

### Create an Event

```clarity
(contract-call? .event-ticketing create-event 
  "Summer Music Festival" 
  "3-day outdoor music festival" 
  u1000000  ; start time (block height)
  u1000500  ; end time (block height)
  u1000     ; max tickets
  u1000000  ; ticket price (microSTX)
  u999000   ; refund deadline
  u3        ; max resales
  u10)      ; 10% royalty
```

### Buy a Ticket

```clarity
(contract-call? .event-ticketing buy-ticket u1)
```

### List Ticket for Resale

```clarity
(contract-call? .event-ticketing list-ticket-for-resale u1 u1200000)
```

### Buy Resale Ticket

```clarity
(contract-call? .event-ticketing buy-resale-ticket u1)
```

## 📋 Core Functions

### 🎪 Event Management

| Function | Description | Access |
|----------|-------------|---------|
| `create-event` | Create a new event | Anyone |
| `cancel-event` | Cancel an event | Organizer only |
| `get-event` | Get event details | Read-only |

### 🎫 Ticket Operations

| Function | Description | Access |
|----------|-------------|---------|
| `buy-ticket` | Purchase an event ticket | Anyone |
| `use-ticket` | Mark ticket as used | Organizer only |
| `request-refund` | Get refund before deadline | Ticket owner |
| `emergency-refund` | Refund for cancelled events | Ticket owner |

### 🔄 Resale Market

| Function | Description | Access |
|----------|-------------|---------|
| `list-ticket-for-resale` | List ticket for sale | Ticket owner |
| `buy-resale-ticket` | Buy listed ticket | Anyone |
| `cancel-ticket-listing` | Remove listing | Seller only |

## 🔧 Contract Structure

### Data Maps

- **events**: Store event information and settings
- **tickets**: Track ticket ownership and usage
- **ticket-listings**: Manage resale marketplace

### Key Features Explained

#### 🎯 Resale Limits
- Each event sets `max-resales` parameter
- Prevents ticket scalping by limiting transfers
- Tracks resale count per ticket

#### ⏱️ Time Restrictions
- Tickets expire when event starts
- Refunds only allowed before `refund-deadline`
- Events must be in future when created

#### 💸 Royalty System
- Organizers earn `resale-royalty-percent` on resales
- Automatic payment splitting on purchase
- Incentivizes legitimate event creation

#### 🛡️ Anti-Fraud Protection
- Tickets marked as used prevent double-entry
- Only organizers can mark tickets as used
- Original owners required for refunds

## 🎮 Usage Examples

### Event Organizer Workflow

1. **Create Event** 🎪
   ```clarity
   (contract-call? .event-ticketing create-event ...)
   ```

2. **Monitor Sales** 📊
   ```clarity
   (contract-call? .event-ticketing get-event u1)
   ```

3. **Check In Attendees** ✅
   ```clarity
   (contract-call? .event-ticketing use-ticket u1)
   ```

### Ticket Buyer Workflow

1. **Buy Ticket** 🛒
   ```clarity
   (contract-call? .event-ticketing buy-ticket u1)
   ```

2. **Resell if Needed** 💰
   ```clarity
   (contract-call? .event-ticketing list-ticket-for-resale u1 u1200000)
   ```

3. **Request Refund** 🔄
   ```clarity
   (contract-call? .event-ticketing request-refund u1)
   ```

## 🔍 Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u100 | err-owner-only | Action requires ownership |
| u101 | err-not-token-owner | Not ticket owner |
| u102 | err-listing-not-found | Resale listing doesn't exist |
| u103 | err-event-not-found | Event doesn't exist |
| u104 | err-insufficient-payment | Payment amount too low |
| u105 | err-event-expired | Event has expired |
| u106 | err-max-resales-exceeded | Too many resales |
| u107 | err-refund-not-allowed | Refund conditions not met |
| u108 | err-ticket-already-used | Ticket already used |
| u109 | err-invalid-price | Invalid price value |
| u110 | err-event-cancelled | Event was cancelled |

## 📝 Testing

Run the included tests:

```bash
clarinet test
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License.

---

*Built with ❤️ using Stacks blockchain and Clarity smart contracts*
