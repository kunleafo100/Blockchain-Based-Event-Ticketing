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
