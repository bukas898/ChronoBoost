;; Constants for contract configuration
(define-constant contract-owner tx-sender)
(define-constant PRECISION u10000)  ;; 4 decimal points precision for rates
(define-constant MIN-TIME-POOL u1000000) ;; Minimum time credits in pool

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INSUFFICIENT-TIME (err u1001))
(define-constant ERR-INVALID-TIME (err u1006))
(define-constant ERR-MIN-TIME-POOL (err u1004))
(define-constant ERR-RETURN-FAILED (err u1003))

;; Pool state variables
(define-data-var total-time-pool uint u0)
(define-data-var total-exchanges-count uint u0)
(define-data-var total-bonus-earned uint u0)

;; Time exchange rate parameters
(define-data-var base-bonus-rate uint u10)  ;; 0.1% base bonus rate

;; -------------------- Read-Only Functions --------------------

(define-read-only (get-timebank-details)
    (ok {
        total-time-pool: (var-get total-time-pool),
        total-exchanges: (var-get total-exchanges-count),
        bonus-earned: (var-get total-bonus-earned),
        current-rate: (var-get base-bonus-rate)
    }))

(define-read-only (get-return-amount (time-amount uint))
    (let (
        (bonus-rate (var-get base-bonus-rate))
        (bonus-amount (/ (* time-amount bonus-rate) PRECISION))
    )
    (ok (+ time-amount bonus-amount))))

;; -------------------- Governance Functions --------------------

(define-public (update-bonus-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (ok (var-set base-bonus-rate new-rate))))

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
    (begin
        (asserts! (>= (var-get total-time-pool) amount) ERR-INSUFFICIENT-TIME)
        (asserts! (> amount u0) ERR-INVALID-TIME)
        
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
            
            (ok return-amount))))