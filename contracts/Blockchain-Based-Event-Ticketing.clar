(define-non-fungible-token event-ticket uint)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-listing-not-found (err u102))
(define-constant err-event-not-found (err u103))
(define-constant err-insufficient-payment (err u104))
(define-constant err-event-expired (err u105))
(define-constant err-max-resales-exceeded (err u106))
(define-constant err-refund-not-allowed (err u107))
(define-constant err-ticket-already-used (err u108))
(define-constant err-invalid-price (err u109))
(define-constant err-event-cancelled (err u110))

(define-constant reputation-cancelled-penalty u20)
(define-constant reputation-completed-bonus u10)
(define-constant reputation-base-score u100)

(define-constant err-discount-not-found (err u111))
(define-constant err-discount-expired (err u112))
(define-constant err-discount-used-up (err u113))
(define-constant err-invalid-discount-code (err u114))

(define-constant err-insufficient-rewards (err u115))
(define-constant err-reward-already-claimed (err u116))
(define-constant default-attendance-reward u50)
(define-constant default-premium-reward u100)

(define-constant err-tier-not-found (err u117))
(define-constant err-tier-sold-out (err u118))
(define-constant err-invalid-tier-config (err u119))

(define-constant err-escrow-not-found (err u120))
(define-constant err-escrow-already-active (err u121))
(define-constant err-escrow-expired (err u122))
(define-constant err-escrow-not-expired (err u123))
(define-constant err-unauthorized-resolver (err u124))

(define-data-var escrow-id-nonce uint u1)

(define-data-var ticket-id-nonce uint u1)

(define-map events 
  { event-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    organizer: principal,
    start-time: uint,
    end-time: uint,
    max-tickets: uint,
    ticket-price: uint,
    refund-deadline: uint,
    max-resales: uint,
    resale-royalty-percent: uint,
    is-cancelled: bool,
    tickets-sold: uint
  }
)

(define-map tickets
  { ticket-id: uint }
  {
    event-id: uint,
    original-owner: principal,
    current-owner: principal,
    purchase-price: uint,
    resale-count: uint,
    is-used: bool,
    purchase-block: uint
  }
)

(define-map ticket-listings
  { ticket-id: uint }
  {
    seller: principal,
    price: uint,
    listed-at: uint
  }
)

(define-map event-id-nonce { dummy: bool } { value: uint })

(define-read-only (get-last-token-id)
  (- (var-get ticket-id-nonce) u1)
)

(define-read-only (get-token-uri (token-id uint))
  (ok none)
)

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? event-ticket token-id))
)

(define-read-only (get-event (event-id uint))
  (map-get? events { event-id: event-id })
)

(define-read-only (get-ticket (ticket-id uint))
  (map-get? tickets { ticket-id: ticket-id })
)

(define-read-only (get-ticket-listing (ticket-id uint))
  (map-get? ticket-listings { ticket-id: ticket-id })
)

(define-private (get-next-event-id)
  (let ((current-id (default-to u0 (get value (map-get? event-id-nonce { dummy: true })))))
    (map-set event-id-nonce { dummy: true } { value: (+ current-id u1) })
    (+ current-id u1)
  )
)

(define-public (create-event 
  (name (string-ascii 100))
  (description (string-ascii 500))
  (start-time uint)
  (end-time uint)
  (max-tickets uint)
  (ticket-price uint)
  (refund-deadline uint)
  (max-resales uint)
  (resale-royalty-percent uint)
)
  (let ((event-id (get-next-event-id)))
    (asserts! (< resale-royalty-percent u100) err-invalid-price)
    (asserts! (< start-time end-time) err-invalid-price)
    (asserts! (< stacks-block-height start-time) err-invalid-price)
    (map-set events 
      { event-id: event-id }
      {
        name: name,
        description: description,
        organizer: tx-sender,
        start-time: start-time,
        end-time: end-time,
        max-tickets: max-tickets,
        ticket-price: ticket-price,
        refund-deadline: refund-deadline,
        max-resales: max-resales,
        resale-royalty-percent: resale-royalty-percent,
        is-cancelled: false,
        tickets-sold: u0
      }
    )
    (ok event-id)
  )
)

(define-public (buy-ticket (event-id uint))
  (let (
    (event-data (unwrap! (get-event event-id) err-event-not-found))
    (ticket-id (var-get ticket-id-nonce))
  )
    (asserts! (not (get is-cancelled event-data)) err-event-cancelled)
    (asserts! (< stacks-block-height (get start-time event-data)) err-event-expired)
    (asserts! (< (get tickets-sold event-data) (get max-tickets event-data)) err-insufficient-payment)
    
    (try! (stx-transfer? (get ticket-price event-data) tx-sender (get organizer event-data)))
    (try! (nft-mint? event-ticket ticket-id tx-sender))
    
    (map-set tickets
      { ticket-id: ticket-id }
      {
        event-id: event-id,
        original-owner: tx-sender,
        current-owner: tx-sender,
        purchase-price: (get ticket-price event-data),
        resale-count: u0,
        is-used: false,
        purchase-block: stacks-block-height
      }
    )
    
    (map-set events
      { event-id: event-id }
      (merge event-data { tickets-sold: (+ (get tickets-sold event-data) u1) })
    )
    
    (var-set ticket-id-nonce (+ ticket-id u1))
    (ok ticket-id)
  )
)

(define-public (list-ticket-for-resale (ticket-id uint) (price uint))
  (let (
    (ticket-data (unwrap! (get-ticket ticket-id) err-not-token-owner))
    (event-data (unwrap! (get-event (get event-id ticket-data)) err-event-not-found))
  )
    (asserts! (is-eq tx-sender (get current-owner ticket-data)) err-not-token-owner)
    (asserts! (not (get is-used ticket-data)) err-ticket-already-used)
    (asserts! (not (get is-cancelled event-data)) err-event-cancelled)
    (asserts! (< (get resale-count ticket-data) (get max-resales event-data)) err-max-resales-exceeded)
    (asserts! (< stacks-block-height (get start-time event-data)) err-event-expired)
    (asserts! (> price u0) err-invalid-price)
    
    (map-set ticket-listings
      { ticket-id: ticket-id }
      {
        seller: tx-sender,
        price: price,
        listed-at: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-public (buy-resale-ticket (ticket-id uint))
  (let (
    (listing-data (unwrap! (get-ticket-listing ticket-id) err-listing-not-found))
    (ticket-data (unwrap! (get-ticket ticket-id) err-not-token-owner))
    (event-data (unwrap! (get-event (get event-id ticket-data)) err-event-not-found))
    (royalty-amount (/ (* (get price listing-data) (get resale-royalty-percent event-data)) u100))
    (seller-amount (- (get price listing-data) royalty-amount))
  )
    (asserts! (not (get is-cancelled event-data)) err-event-cancelled)
    (asserts! (< stacks-block-height (get start-time event-data)) err-event-expired)
    (asserts! (not (get is-used ticket-data)) err-ticket-already-used)
    
    (try! (stx-transfer? seller-amount tx-sender (get seller listing-data)))
    (try! (stx-transfer? royalty-amount tx-sender (get organizer event-data)))
    (try! (nft-transfer? event-ticket ticket-id (get current-owner ticket-data) tx-sender))
    
    (map-set tickets
      { ticket-id: ticket-id }
      (merge ticket-data {
        current-owner: tx-sender,
        resale-count: (+ (get resale-count ticket-data) u1)
      })
    )
    
    (map-delete ticket-listings { ticket-id: ticket-id })
    (ok true)
  )
)

(define-public (cancel-ticket-listing (ticket-id uint))
  (let ((listing-data (unwrap! (get-ticket-listing ticket-id) err-listing-not-found)))
    (asserts! (is-eq tx-sender (get seller listing-data)) err-not-token-owner)
    (map-delete ticket-listings { ticket-id: ticket-id })
    (ok true)
  )
)

(define-public (request-refund (ticket-id uint))
  (let (
    (ticket-data (unwrap! (get-ticket ticket-id) err-not-token-owner))
    (event-data (unwrap! (get-event (get event-id ticket-data)) err-event-not-found))
  )
    (asserts! (is-eq tx-sender (get current-owner ticket-data)) err-not-token-owner)
    (asserts! (not (get is-used ticket-data)) err-ticket-already-used)
    (asserts! (< stacks-block-height (get refund-deadline event-data)) err-refund-not-allowed)
    (asserts! (is-eq (get current-owner ticket-data) (get original-owner ticket-data)) err-refund-not-allowed)
    
    (try! (as-contract (stx-transfer? (get purchase-price ticket-data) tx-sender (get current-owner ticket-data))))
    (try! (nft-burn? event-ticket ticket-id (get current-owner ticket-data)))
    
    (map-set events
      { event-id: (get event-id ticket-data) }
      (merge event-data { tickets-sold: (- (get tickets-sold event-data) u1) })
    )
    
    (map-delete tickets { ticket-id: ticket-id })
    (ok true)
  )
)

(define-public (use-ticket (ticket-id uint))
  (let (
    (ticket-data (unwrap! (get-ticket ticket-id) err-not-token-owner))
    (event-data (unwrap! (get-event (get event-id ticket-data)) err-event-not-found))
  )
    (asserts! (is-eq tx-sender (get organizer event-data)) err-owner-only)
    (asserts! (not (get is-used ticket-data)) err-ticket-already-used)
    (asserts! (not (get is-cancelled event-data)) err-event-cancelled)
    (asserts! (>= stacks-block-height (get start-time event-data)) err-event-expired)
    (asserts! (<= stacks-block-height (get end-time event-data)) err-event-expired)
    
    (map-set tickets
      { ticket-id: ticket-id }
      (merge ticket-data { is-used: true })
    )
    (ok true)
  )
)

(define-public (cancel-event (event-id uint))
  (let ((event-data (unwrap! (get-event event-id) err-event-not-found)))
    (asserts! (is-eq tx-sender (get organizer event-data)) err-owner-only)
    (asserts! (not (get is-cancelled event-data)) err-event-cancelled)
    (asserts! (< stacks-block-height (get start-time event-data)) err-event-expired)
    
    (map-set events
      { event-id: event-id }
      (merge event-data { is-cancelled: true })
    )
    (ok true)
  )
)

(define-public (emergency-refund (ticket-id uint))
  (let (
    (ticket-data (unwrap! (get-ticket ticket-id) err-not-token-owner))
    (event-data (unwrap! (get-event (get event-id ticket-data)) err-event-not-found))
  )
    (asserts! (get is-cancelled event-data) err-refund-not-allowed)
    (asserts! (is-eq tx-sender (get current-owner ticket-data)) err-not-token-owner)
    (asserts! (not (get is-used ticket-data)) err-ticket-already-used)
    
    (try! (as-contract (stx-transfer? (get purchase-price ticket-data) tx-sender (get current-owner ticket-data))))
    (try! (nft-burn? event-ticket ticket-id (get current-owner ticket-data))) 
    (map-delete tickets { ticket-id: ticket-id })
    (ok true)
  )
)

(define-map organizer-reputation
  { organizer: principal }
  {
    total-events: uint,
    completed-events: uint,
    cancelled-events: uint,
    reputation-score: uint,
    last-updated: uint
  }
)

(define-read-only (get-organizer-reputation (organizer principal))
  (default-to 
    {
      total-events: u0,
      completed-events: u0,
      cancelled-events: u0,
      reputation-score: reputation-base-score,
      last-updated: u0
    }
    (map-get? organizer-reputation { organizer: organizer })
  )
)

(define-read-only (calculate-reputation-score (completed uint) (cancelled uint) (total uint))
  (if (is-eq total u0)
    reputation-base-score
    (let (
      (completion-rate (/ (* completed u100) total))
      (cancellation-penalty (* cancelled reputation-cancelled-penalty))
      (completion-bonus (* completed reputation-completed-bonus))
    )
      (if (>= (+ reputation-base-score completion-bonus) cancellation-penalty)
        (- (+ reputation-base-score completion-bonus) cancellation-penalty)
        u0
      )
    )
  )
)

(define-private (update-organizer-reputation (organizer principal) (event-completed bool) (event-cancelled bool))
  (let (
    (current-rep (get-organizer-reputation organizer))
    (new-total (+ (get total-events current-rep) u1))
    (new-completed (if event-completed (+ (get completed-events current-rep) u1) (get completed-events current-rep)))
    (new-cancelled (if event-cancelled (+ (get cancelled-events current-rep) u1) (get cancelled-events current-rep)))
    (new-score (calculate-reputation-score new-completed new-cancelled new-total))
  )
    (map-set organizer-reputation
      { organizer: organizer }
      {
        total-events: new-total,
        completed-events: new-completed,
        cancelled-events: new-cancelled,
        reputation-score: new-score,
        last-updated: stacks-block-height
      }
    )
  )
)

(define-public (finalize-event (event-id uint))
  (let ((event-data (unwrap! (get-event event-id) err-event-not-found)))
    (asserts! (is-eq tx-sender (get organizer event-data)) err-owner-only)
    (asserts! (not (get is-cancelled event-data)) err-event-cancelled)
    (asserts! (> stacks-block-height (get end-time event-data)) err-event-expired)
    
    (update-organizer-reputation (get organizer event-data) true false)
    (ok true)
  )
)



(define-map discount-codes
  { event-id: uint, code: (string-ascii 20) }
  {
    discount-percent: uint,
    max-uses: uint,
    current-uses: uint,
    expiry-block: uint,
    is-active: bool
  }
)

(define-read-only (get-discount-code (event-id uint) (code (string-ascii 20)))
  (map-get? discount-codes { event-id: event-id, code: code })
)

(define-public (create-discount-code 
  (event-id uint) 
  (code (string-ascii 20)) 
  (discount-percent uint) 
  (max-uses uint) 
  (expiry-block uint)
)
  (let ((event-data (unwrap! (get-event event-id) err-event-not-found)))
    (asserts! (is-eq tx-sender (get organizer event-data)) err-owner-only)
    (asserts! (< discount-percent u100) err-invalid-price)
    (asserts! (> max-uses u0) err-invalid-price)
    (asserts! (> expiry-block stacks-block-height) err-event-expired)
    (asserts! (< expiry-block (get start-time event-data)) err-event-expired)
    
    (map-set discount-codes
      { event-id: event-id, code: code }
      {
        discount-percent: discount-percent,
        max-uses: max-uses,
        current-uses: u0,
        expiry-block: expiry-block,
        is-active: true
      }
    )
    (ok true)
  )
)

(define-public (buy-ticket-with-discount (event-id uint) (discount-code (string-ascii 20)))
  (let (
    (event-data (unwrap! (get-event event-id) err-event-not-found))
    (discount-data (unwrap! (get-discount-code event-id discount-code) err-discount-not-found))
    (ticket-id (var-get ticket-id-nonce))
    (discounted-price (- (get ticket-price event-data) 
                        (/ (* (get ticket-price event-data) (get discount-percent discount-data)) u100)))
  )
    (asserts! (not (get is-cancelled event-data)) err-event-cancelled)
    (asserts! (< stacks-block-height (get start-time event-data)) err-event-expired)
    (asserts! (< (get tickets-sold event-data) (get max-tickets event-data)) err-insufficient-payment)
    (asserts! (get is-active discount-data) err-invalid-discount-code)
    (asserts! (< stacks-block-height (get expiry-block discount-data)) err-discount-expired)
    (asserts! (< (get current-uses discount-data) (get max-uses discount-data)) err-discount-used-up)
    
    (try! (stx-transfer? discounted-price tx-sender (get organizer event-data)))
    (try! (nft-mint? event-ticket ticket-id tx-sender))
    
    (map-set tickets
      { ticket-id: ticket-id }
      {
        event-id: event-id,
        original-owner: tx-sender,
        current-owner: tx-sender,
        purchase-price: discounted-price,
        resale-count: u0,
        is-used: false,
        purchase-block: stacks-block-height
      }
    )
    
    (map-set events
      { event-id: event-id }
      (merge event-data { tickets-sold: (+ (get tickets-sold event-data) u1) })
    )
    
    (map-set discount-codes
      { event-id: event-id, code: discount-code }
      (merge discount-data { current-uses: (+ (get current-uses discount-data) u1) })
    )
    
    (var-set ticket-id-nonce (+ ticket-id u1))
    (ok ticket-id)
  )
)


(define-map attendee-rewards
  { attendee: principal }
  {
    total-points: uint,
    events-attended: uint,
    last-updated: uint
  }
)

(define-map event-reward-claims
  { ticket-id: uint }
  {
    claimed: bool,
    reward-amount: uint,
    claim-block: uint
  }
)

(define-read-only (get-attendee-rewards (attendee principal))
  (default-to 
    { total-points: u0, events-attended: u0, last-updated: u0 }
    (map-get? attendee-rewards { attendee: attendee })
  )
)

(define-read-only (get-reward-claim-status (ticket-id uint))
  (map-get? event-reward-claims { ticket-id: ticket-id })
)

(define-read-only (calculate-event-reward (ticket-price uint))
  (if (>= ticket-price u5000000)
    default-premium-reward
    default-attendance-reward
  )
)

(define-public (claim-attendance-reward (ticket-id uint))
  (let (
    (ticket-data (unwrap! (get-ticket ticket-id) err-not-token-owner))
    (event-data (unwrap! (get-event (get event-id ticket-data)) err-event-not-found))
    (current-rewards (get-attendee-rewards (get current-owner ticket-data)))
    (reward-amount (calculate-event-reward (get purchase-price ticket-data)))
  )
    (asserts! (is-eq tx-sender (get current-owner ticket-data)) err-not-token-owner)
    (asserts! (get is-used ticket-data) err-ticket-already-used)
    (asserts! (is-none (get-reward-claim-status ticket-id)) err-reward-already-claimed)
    (asserts! (> stacks-block-height (get end-time event-data)) err-event-expired)
    
    (map-set attendee-rewards
      { attendee: (get current-owner ticket-data) }
      {
        total-points: (+ (get total-points current-rewards) reward-amount),
        events-attended: (+ (get events-attended current-rewards) u1),
        last-updated: stacks-block-height
      }
    )
    
    (map-set event-reward-claims
      { ticket-id: ticket-id }
      {
        claimed: true,
        reward-amount: reward-amount,
        claim-block: stacks-block-height
      }
    )
    (ok reward-amount)
  )
)

(define-public (redeem-rewards-for-discount (event-id uint) (points-to-redeem uint))
  (let (
    (event-data (unwrap! (get-event event-id) err-event-not-found))
    (current-rewards (get-attendee-rewards tx-sender))
    (discount-percent (/ points-to-redeem u10))
    (max-discount u50)
    (final-discount (if (> discount-percent max-discount) max-discount discount-percent))
    (ticket-id (var-get ticket-id-nonce))
    (discounted-price (- (get ticket-price event-data) 
                        (/ (* (get ticket-price event-data) final-discount) u100)))
  )
    (asserts! (not (get is-cancelled event-data)) err-event-cancelled)
    (asserts! (< stacks-block-height (get start-time event-data)) err-event-expired)
    (asserts! (< (get tickets-sold event-data) (get max-tickets event-data)) err-insufficient-payment)
    (asserts! (>= (get total-points current-rewards) points-to-redeem) err-insufficient-rewards)
    (asserts! (> points-to-redeem u0) err-invalid-price)
    
    (try! (stx-transfer? discounted-price tx-sender (get organizer event-data)))
    (try! (nft-mint? event-ticket ticket-id tx-sender))
    
    (map-set tickets
      { ticket-id: ticket-id }
      {
        event-id: event-id,
        original-owner: tx-sender,
        current-owner: tx-sender,
        purchase-price: discounted-price,
        resale-count: u0,
        is-used: false,
        purchase-block: stacks-block-height
      }
    )
    
    (map-set events
      { event-id: event-id }
      (merge event-data { tickets-sold: (+ (get tickets-sold event-data) u1) })
    )
    
    (map-set attendee-rewards
      { attendee: tx-sender }
      (merge current-rewards { 
        total-points: (- (get total-points current-rewards) points-to-redeem),
        last-updated: stacks-block-height
      })
    )
    
    (var-set ticket-id-nonce (+ ticket-id u1))
    (ok { ticket-id: ticket-id, discount-applied: final-discount })
  )
)


(define-map event-tiers
  { event-id: uint, tier-id: uint }
  {
    tier-name: (string-ascii 50),
    tier-price: uint,
    max-tier-tickets: uint,
    tier-tickets-sold: uint,
    tier-active: bool
  }
)

(define-map ticket-tier-info
  { ticket-id: uint }
  { tier-id: uint }
)

(define-read-only (get-event-tier (event-id uint) (tier-id uint))
  (map-get? event-tiers { event-id: event-id, tier-id: tier-id })
)

(define-read-only (get-ticket-tier (ticket-id uint))
  (map-get? ticket-tier-info { ticket-id: ticket-id })
)

(define-public (create-event-tier
  (event-id uint)
  (tier-id uint)
  (tier-name (string-ascii 50))
  (tier-price uint)
  (max-tier-tickets uint)
)
  (let ((event-data (unwrap! (get-event event-id) err-event-not-found)))
    (asserts! (is-eq tx-sender (get organizer event-data)) err-owner-only)
    (asserts! (not (get is-cancelled event-data)) err-event-cancelled)
    (asserts! (< stacks-block-height (get start-time event-data)) err-event-expired)
    (asserts! (> tier-price u0) err-invalid-price)
    (asserts! (> max-tier-tickets u0) err-invalid-tier-config)
    
    (map-set event-tiers
      { event-id: event-id, tier-id: tier-id }
      {
        tier-name: tier-name,
        tier-price: tier-price,
        max-tier-tickets: max-tier-tickets,
        tier-tickets-sold: u0,
        tier-active: true
      }
    )
    (ok true)
  )
)

(define-public (buy-tiered-ticket (event-id uint) (tier-id uint))
  (let (
    (event-data (unwrap! (get-event event-id) err-event-not-found))
    (tier-data (unwrap! (get-event-tier event-id tier-id) err-tier-not-found))
    (ticket-id (var-get ticket-id-nonce))
  )
    (asserts! (not (get is-cancelled event-data)) err-event-cancelled)
    (asserts! (< stacks-block-height (get start-time event-data)) err-event-expired)
    (asserts! (get tier-active tier-data) err-tier-not-found)
    (asserts! (< (get tier-tickets-sold tier-data) (get max-tier-tickets tier-data)) err-tier-sold-out)
    
    (try! (stx-transfer? (get tier-price tier-data) tx-sender (get organizer event-data)))
    (try! (nft-mint? event-ticket ticket-id tx-sender))
    
    (map-set tickets
      { ticket-id: ticket-id }
      {
        event-id: event-id,
        original-owner: tx-sender,
        current-owner: tx-sender,
        purchase-price: (get tier-price tier-data),
        resale-count: u0,
        is-used: false,
        purchase-block: stacks-block-height
      }
    )
    
    (map-set ticket-tier-info
      { ticket-id: ticket-id }
      { tier-id: tier-id }
    )
    
    (map-set event-tiers
      { event-id: event-id, tier-id: tier-id }
      (merge tier-data { tier-tickets-sold: (+ (get tier-tickets-sold tier-data) u1) })
    )
    
    (var-set ticket-id-nonce (+ ticket-id u1))
    (ok { ticket-id: ticket-id, tier-id: tier-id })
  )
)

(define-map ticket-escrows
  { escrow-id: uint }
  {
    buyer: principal,
    seller: principal,
    ticket-id: uint,
    escrow-amount: uint,
    deadline-block: uint,
    is-fulfilled: bool,
    is-cancelled: bool,
    created-at: uint
  }
)

(define-read-only (get-escrow (escrow-id uint))
  (map-get? ticket-escrows { escrow-id: escrow-id })
)

(define-public (initiate-escrow (ticket-id uint) (seller principal) (deadline-blocks uint))
  (let (
    (ticket-data (unwrap! (get-ticket ticket-id) err-not-token-owner))
    (event-data (unwrap! (get-event (get event-id ticket-data)) err-event-not-found))
    (listing-data (unwrap! (get-ticket-listing ticket-id) err-listing-not-found))
    (escrow-id (var-get escrow-id-nonce))
    (deadline (+ stacks-block-height deadline-blocks))
  )
    (asserts! (is-eq seller (get seller listing-data)) err-not-token-owner)
    (asserts! (< deadline (get start-time event-data)) err-event-expired)
    (asserts! (> deadline-blocks u0) err-invalid-price)
    
    (try! (stx-transfer? (get price listing-data) tx-sender (as-contract tx-sender)))
    
    (map-set ticket-escrows
      { escrow-id: escrow-id }
      {
        buyer: tx-sender,
        seller: seller,
        ticket-id: ticket-id,
        escrow-amount: (get price listing-data),
        deadline-block: deadline,
        is-fulfilled: false,
        is-cancelled: false,
        created-at: stacks-block-height
      }
    )
    (var-set escrow-id-nonce (+ escrow-id u1))
    (ok escrow-id)
  )
)

(define-public (fulfill-escrow (escrow-id uint))
  (let (
    (escrow-data (unwrap! (get-escrow escrow-id) err-escrow-not-found))
    (ticket-data (unwrap! (get-ticket (get ticket-id escrow-data)) err-not-token-owner))
    (event-data (unwrap! (get-event (get event-id ticket-data)) err-event-not-found))
    (royalty-amount (/ (* (get escrow-amount escrow-data) (get resale-royalty-percent event-data)) u100))
    (seller-amount (- (get escrow-amount escrow-data) royalty-amount))
  )
    (asserts! (is-eq tx-sender (get seller escrow-data)) err-not-token-owner)
    (asserts! (not (get is-fulfilled escrow-data)) err-escrow-already-active)
    (asserts! (not (get is-cancelled escrow-data)) err-escrow-already-active)
    (asserts! (<= stacks-block-height (get deadline-block escrow-data)) err-escrow-expired)
    
    (try! (as-contract (stx-transfer? seller-amount tx-sender (get seller escrow-data))))
    (try! (as-contract (stx-transfer? royalty-amount tx-sender (get organizer event-data))))
    (try! (nft-transfer? event-ticket (get ticket-id escrow-data) (get current-owner ticket-data) (get buyer escrow-data)))
    
    (map-set tickets
      { ticket-id: (get ticket-id escrow-data) }
      (merge ticket-data {
        current-owner: (get buyer escrow-data),
        resale-count: (+ (get resale-count ticket-data) u1)
      })
    )
    (map-delete ticket-listings { ticket-id: (get ticket-id escrow-data) })
    (map-set ticket-escrows { escrow-id: escrow-id } (merge escrow-data { is-fulfilled: true }))
    (ok true)
  )
)

(define-public (cancel-escrow (escrow-id uint))
  (let ((escrow-data (unwrap! (get-escrow escrow-id) err-escrow-not-found)))
    (asserts! (is-eq tx-sender (get buyer escrow-data)) err-not-token-owner)
    (asserts! (not (get is-fulfilled escrow-data)) err-escrow-already-active)
    (asserts! (not (get is-cancelled escrow-data)) err-escrow-already-active)
    (asserts! (> stacks-block-height (get deadline-block escrow-data)) err-escrow-not-expired)
    
    (try! (as-contract (stx-transfer? (get escrow-amount escrow-data) tx-sender (get buyer escrow-data))))
    (map-set ticket-escrows { escrow-id: escrow-id } (merge escrow-data { is-cancelled: true }))
    (ok true)
  )
)

(define-public (resolve-escrow-dispute (escrow-id uint) (refund-buyer bool))
  (let (
    (escrow-data (unwrap! (get-escrow escrow-id) err-escrow-not-found))
    (ticket-data (unwrap! (get-ticket (get ticket-id escrow-data)) err-not-token-owner))
    (event-data (unwrap! (get-event (get event-id ticket-data)) err-event-not-found))
  )
    (asserts! (is-eq tx-sender (get organizer event-data)) err-unauthorized-resolver)
    (asserts! (not (get is-fulfilled escrow-data)) err-escrow-already-active)
    (asserts! (not (get is-cancelled escrow-data)) err-escrow-already-active)
    
    (if refund-buyer
      (try! (as-contract (stx-transfer? (get escrow-amount escrow-data) tx-sender (get buyer escrow-data))))
      (try! (as-contract (stx-transfer? (get escrow-amount escrow-data) tx-sender (get seller escrow-data))))
    )
    (map-set ticket-escrows { escrow-id: escrow-id } (merge escrow-data { is-cancelled: true }))
    (ok true)
  )
)