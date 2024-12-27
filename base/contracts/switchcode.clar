;; Constants for contract configuration
(define-constant contract-owner tx-sender)
(define-constant PRECISION u10000)  ;; 4 decimal points precision for rates
(define-constant MIN-TIME-POOL u1000000) ;; Minimum time credits in pool
(define-constant MAX-TIME-USAGE u9000)  ;; 90% maximum pool usage
(define-constant MIN-BOOST-MULTIPLIER u50)  ;; Minimum 0.5x multiplier
(define-constant MAX-BOOST-MULTIPLIER u500) ;; Maximum 5x multiplier

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INSUFFICIENT-TIME (err u1001))
(define-constant ERR-TIME-EXCHANGE-ACTIVE (err u1002))
(define-constant ERR-RETURN-FAILED (err u1003))
(define-constant ERR-MIN-TIME-POOL (err u1004))
(define-constant ERR-MAX-TIME-USAGE (err u1005))
(define-constant ERR-INVALID-TIME (err u1006))

;; Pool state variables
(define-data-var total-time-pool uint u0)
(define-data-var active-exchange-amount uint u0)
(define-data-var total-exchanges-count uint u0)
(define-data-var total-bonus-earned uint u0)

;; Time exchange rate parameters
(define-data-var base-bonus-rate uint u10)  ;; 0.1% base bonus rate
(define-data-var bonus-multiplier uint u100)  ;; Bonus increase multiplier
(define-data-var exchange-in-progress bool false)

;; Bonus rate governance
(define-data-var max-bonus-rate uint u100)  ;; 1% maximum bonus rate
(define-data-var min-bonus-rate uint u5)    ;; 0.05% minimum bonus rate

;; Event tracking
(define-data-var event-counter uint u0)
(define-data-var last-event-id uint u0)

;; -------------------- Read-Only Functions --------------------

(define-read-only (get-timebank-details)
    (ok {
        total-time-pool: (var-get total-time-pool),
        active-exchange: (var-get active-exchange-amount),
        total-exchanges: (var-get total-exchanges-count),
        bonus-earned: (var-get total-bonus-earned),
        current-rate: (get-current-bonus-rate)
    }))

(define-read-only (get-current-bonus-rate)
    (let (
        (usage-rate (calculate-usage))
        (base (var-get base-bonus-rate))
        (multiplier (var-get bonus-multiplier))
    )
    (+ base (/ (* usage-rate multiplier) PRECISION))))

(define-read-only (calculate-usage)
    (if (is-eq (var-get total-time-pool) u0)
        u0
        (/ (* (var-get active-exchange-amount) PRECISION) (var-get total-time-pool))))

(define-read-only (get-return-amount (time-amount uint))
    (let (
        (bonus-rate (get-current-bonus-rate))
        (bonus-amount (/ (* time-amount bonus-rate) PRECISION))
    )
    (ok (+ time-amount bonus-amount))))

;; -------------------- Governance Functions --------------------

(define-public (update-bonus-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= new-rate (var-get min-bonus-rate)) 
                      (<= new-rate (var-get max-bonus-rate))) 
                 ERR-INVALID-TIME)
        (ok (var-set base-bonus-rate new-rate))))

(define-public (update-bonus-multiplier (new-multiplier uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= new-multiplier MIN-BOOST-MULTIPLIER)
                      (<= new-multiplier MAX-BOOST-MULTIPLIER))
                 ERR-INVALID-TIME)
        (ok (var-set bonus-multiplier new-multiplier))))

;; -------------------- Core Pool Functions --------------------

(define-public (deposit-time (amount uint))
    (begin
        (asserts! (> amount u0) ERR-INVALID-TIME)
        
        ;; Transfer STX to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update time pool
        (var-set total-time-pool (+ (var-get total-time-pool) amount))
        
        (ok true)))

(define-public (withdraw-time (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (<= amount (var-get total-time-pool)) ERR-INSUFFICIENT-TIME)
        (asserts! (>= (- (var-get total-time-pool) amount) MIN-TIME-POOL) ERR-MIN-TIME-POOL)
        
        ;; Transfer STX back to owner
        (try! (as-contract (stx-transfer? amount contract-owner tx-sender)))
        
        ;; Update time pool
        (var-set total-time-pool (- (var-get total-time-pool) amount))
        
        (ok true)))

;; -------------------- Time Exchange Functions --------------------

(define-public (time-exchange (amount uint))
    (let (
        (current-pool (var-get total-time-pool))
        (usage (calculate-usage))
    )
        (asserts! (not (var-get exchange-in-progress)) ERR-TIME-EXCHANGE-ACTIVE)
        (asserts! (>= current-pool amount) ERR-INSUFFICIENT-TIME)
        (asserts! (> amount u0) ERR-INVALID-TIME)
        (asserts! (<= usage MAX-TIME-USAGE) ERR-MAX-TIME-USAGE)
        
        ;; Set exchange as active
        (var-set exchange-in-progress true)
        (var-set active-exchange-amount amount)
        
        ;; Transfer time credits to user
        (try! (as-contract (stx-transfer? amount contract-owner tx-sender)))
        
        ;; Calculate required return
        (let (
            (return-amount (unwrap! (get-return-amount amount) ERR-RETURN-FAILED))
            (bonus-earned (- return-amount amount))
        )
            ;; Check if user has sufficient balance for return
            (asserts! (>= (stx-get-balance tx-sender) return-amount) 
                     ERR-INSUFFICIENT-TIME)
            
            ;; Process return
            (try! (stx-transfer? return-amount tx-sender (as-contract tx-sender)))
            
            ;; Update contract state
            (var-set total-exchanges-count (+ (var-get total-exchanges-count) u1))
            (var-set total-bonus-earned (+ (var-get total-bonus-earned) bonus-earned))
            (var-set exchange-in-progress false)
            (var-set active-exchange-amount u0)
            
            ;; Emit event
            (emit-time-exchange-event tx-sender amount bonus-earned)
            
            (ok return-amount))))

;; -------------------- Emergency Functions --------------------

(define-public (emergency-pause)
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (var-set exchange-in-progress false)
        (var-set active-exchange-amount u0)
        (ok true)))

;; -------------------- Events --------------------

(define-read-only (get-last-event-id) 
    (ok (var-get last-event-id)))

(define-private (emit-time-exchange-event (user principal) (amount uint) (bonus uint))
    (begin
        (var-set event-counter (+ (var-get event-counter) u1))
        (var-set last-event-id (var-get event-counter))
        (print {
            event: "time-exchange",
            id: (var-get event-counter),
            user: user,
            amount: amount,
            bonus: bonus
        })))