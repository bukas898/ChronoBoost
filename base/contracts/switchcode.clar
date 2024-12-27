;; Constants for contract configuration
(define-constant contract-owner tx-sender)
(define-constant PRECISION u10000)  ;; 4 decimal points precision for rates

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INSUFFICIENT-TIME (err u1001))
(define-constant ERR-INVALID-TIME (err u1006))

;; Pool state variables
(define-data-var total-time-pool uint u0)
(define-data-var total-exchanges-count uint u0)

;; -------------------- Read-Only Functions --------------------

(define-read-only (get-timebank-details)
    (ok {
        total-time-pool: (var-get total-time-pool),
        total-exchanges: (var-get total-exchanges-count)
    }))

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
        
        ;; Transfer STX back to owner
        (try! (as-contract (stx-transfer? amount contract-owner tx-sender)))
        
        ;; Update time pool
        (var-set total-time-pool (- (var-get total-time-pool) amount))
        
        (ok true)))

;; -------------------- Time Exchange Functions --------------------

(define-public (time-exchange (amount uint))
    (begin
        (asserts! (>= (var-get total-time-pool) amount) ERR-INSUFFICIENT-TIME)
        (asserts! (> amount u0) ERR-INVALID-TIME)
        
        ;; Transfer time credits to user
        (try! (as-contract (stx-transfer? amount contract-owner tx-sender)))
        
        ;; Process return
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update contract state
        (var-set total-exchanges-count (+ (var-get total-exchanges-count) u1))
        
        (ok amount)))