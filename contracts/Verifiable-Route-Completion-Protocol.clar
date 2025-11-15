;; title: Verifiable-Route-Completion-Protocol

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-checkpoint (err u104))
(define-constant err-route-not-active (err u105))
(define-constant err-insufficient-payment (err u106))
(define-constant err-already-verified (err u107))
(define-constant err-route-completed (err u108))
(define-constant err-invalid-coordinates (err u109))
(define-constant err-checkpoint-expired (err u110))
(define-constant err-invalid-dispute (err u111))
(define-constant err-dispute-exists (err u112))
(define-constant err-no-expired-checkpoints (err u113))

(define-data-var route-nonce uint u0)
(define-data-var checkpoint-nonce uint u0)

(define-map routes
    uint
    {
        shipper: principal,
        transporter: principal,
        payment-amount: uint,
        created-at: uint,
        completed-at: (optional uint),
        status: (string-ascii 20),
        total-checkpoints: uint,
        verified-checkpoints: uint
    }
)

(define-map checkpoints
    {route-id: uint, checkpoint-id: uint}
    {
        latitude: int,
        longitude: int,
        tolerance: uint,
        verified: bool,
        verified-at: (optional uint),
        verified-by: (optional principal),
        deadline: uint
    }
)

(define-map route-payments
    uint
    {
        amount: uint,
        amount-released: uint,
        fully-released: bool,
        released-at: (optional uint)
    }
)

(define-map transporter-stats
    principal
    {
        routes-completed: uint,
        total-earned: uint,
        success-rate: uint
    }
)

(define-map route-disputes
    uint
    {
        disputed-by: principal,
        disputed-at: uint,
        expired-checkpoints: uint,
        refund-amount: uint,
        processed: bool
    }
)

(define-public (create-route (transporter principal) (payment-amount uint) (total-checkpoints uint))
    (let
        (
            (route-id (var-get route-nonce))
            (current-height stacks-block-height)
        )
        (asserts! (> payment-amount u0) err-insufficient-payment)
        (asserts! (> total-checkpoints u0) err-invalid-checkpoint)
        (try! (stx-transfer? payment-amount tx-sender (as-contract tx-sender)))
        (map-set routes route-id {
            shipper: tx-sender,
            transporter: transporter,
            payment-amount: payment-amount,
            created-at: current-height,
            completed-at: none,
            status: "active",
            total-checkpoints: total-checkpoints,
            verified-checkpoints: u0
        })
        (map-set route-payments route-id {
            amount: payment-amount,
            amount-released: u0,
            fully-released: false,
            released-at: none
        })
        (var-set route-nonce (+ route-id u1))
        (ok route-id)
    )
)

(define-public (add-checkpoint (route-id uint) (latitude int) (longitude int) (tolerance uint) (deadline-blocks uint))
    (let
        (
            (route (unwrap! (map-get? routes route-id) err-not-found))
            (checkpoint-id (var-get checkpoint-nonce))
            (current-height stacks-block-height)
        )
        (asserts! (is-eq tx-sender (get shipper route)) err-unauthorized)
        (asserts! (is-eq (get status route) "active") err-route-not-active)
        (asserts! (and (>= latitude -90000000) (<= latitude 90000000)) err-invalid-coordinates)
        (asserts! (and (>= longitude -180000000) (<= longitude 180000000)) err-invalid-coordinates)
        (map-set checkpoints {route-id: route-id, checkpoint-id: checkpoint-id} {
            latitude: latitude,
            longitude: longitude,
            tolerance: tolerance,
            verified: false,
            verified-at: none,
            verified-by: none,
            deadline: (+ current-height deadline-blocks)
        })
        (var-set checkpoint-nonce (+ checkpoint-id u1))
        (ok checkpoint-id)
    )
)

(define-public (verify-checkpoint (route-id uint) (checkpoint-id uint) (actual-lat int) (actual-lon int))
    (let
        (
            (route (unwrap! (map-get? routes route-id) err-not-found))
            (checkpoint (unwrap! (map-get? checkpoints {route-id: route-id, checkpoint-id: checkpoint-id}) err-not-found))
            (current-height stacks-block-height)
            (lat-diff (if (>= actual-lat (get latitude checkpoint))
                         (- actual-lat (get latitude checkpoint))
                         (- (get latitude checkpoint) actual-lat)))
            (lon-diff (if (>= actual-lon (get longitude checkpoint))
                         (- actual-lon (get longitude checkpoint))
                         (- (get longitude checkpoint) actual-lon)))
        )
        (asserts! (is-eq tx-sender (get transporter route)) err-unauthorized)
        (asserts! (is-eq (get status route) "active") err-route-not-active)
        (asserts! (not (get verified checkpoint)) err-already-verified)
        (asserts! (<= current-height (get deadline checkpoint)) err-checkpoint-expired)
        (asserts! (<= (to-uint lat-diff) (get tolerance checkpoint)) err-invalid-coordinates)
        (asserts! (<= (to-uint lon-diff) (get tolerance checkpoint)) err-invalid-coordinates)
        (map-set checkpoints {route-id: route-id, checkpoint-id: checkpoint-id}
            (merge checkpoint {
                verified: true,
                verified-at: (some current-height),
                verified-by: (some tx-sender)
            })
        )
        (let
            (
                (updated-verified (+ (get verified-checkpoints route) u1))
                (payment-info (unwrap! (map-get? route-payments route-id) err-not-found))
                (partial-amount (/ (get payment-amount route) (get total-checkpoints route)))
            )
            (map-set routes route-id
                (merge route {verified-checkpoints: updated-verified})
            )
            (try! (as-contract (stx-transfer? partial-amount tx-sender (get transporter route))))
            (map-set route-payments route-id
                (merge payment-info {
                    amount-released: (+ (get amount-released payment-info) partial-amount)
                })
            )
            (if (is-eq updated-verified (get total-checkpoints route))
                (finalize-route route-id)
                (ok true)
            )
        )
    )
)

(define-private (finalize-route (route-id uint))
    (let
        (
            (route (unwrap! (map-get? routes route-id) err-not-found))
            (payment (unwrap! (map-get? route-payments route-id) err-not-found))
            (current-height stacks-block-height)
            (transporter (get transporter route))
            (remaining-amount (- (get amount payment) (get amount-released payment)))
        )
        (asserts! (not (get fully-released payment)) err-route-completed)
        (if (> remaining-amount u0)
            (begin
                (try! (as-contract (stx-transfer? remaining-amount tx-sender transporter)))
                true
            )
            true
        )
        (map-set routes route-id
            (merge route {
                status: "completed",
                completed-at: (some current-height)
            })
        )
        (map-set route-payments route-id
            (merge payment {
                amount-released: (get amount payment),
                fully-released: true,
                released-at: (some current-height)
            })
        )
        (unwrap-panic (update-transporter-stats transporter (get payment-amount route)))
        (ok true)
    )
)

(define-private (update-transporter-stats (transporter principal) (payment uint))
    (begin
        (map-set transporter-stats transporter 
            (let
                (
                    (stats (default-to 
                        {routes-completed: u0, total-earned: u0, success-rate: u100}
                        (map-get? transporter-stats transporter)
                    ))
                )
                {
                    routes-completed: (+ (get routes-completed stats) u1),
                    total-earned: (+ (get total-earned stats) payment),
                    success-rate: u100
                }
            )
        )
        (ok true)
    )
)

(define-public (cancel-route (route-id uint))
    (let
        (
            (route (unwrap! (map-get? routes route-id) err-not-found))
            (payment (unwrap! (map-get? route-payments route-id) err-not-found))
            (current-height stacks-block-height)
        )
        (asserts! (is-eq tx-sender (get shipper route)) err-unauthorized)
        (asserts! (is-eq (get status route) "active") err-route-not-active)
        (asserts! (is-eq (get verified-checkpoints route) u0) err-route-completed)
        (asserts! (not (get fully-released payment)) err-route-completed)
        (let
            (
                (refund-amount (- (get amount payment) (get amount-released payment)))
            )
            (try! (as-contract (stx-transfer? refund-amount tx-sender (get shipper route))))
        )
        (map-set routes route-id
            (merge route {status: "cancelled"})
        )
        (ok true)
    )
)

(define-read-only (get-route (route-id uint))
    (ok (map-get? routes route-id))
)

(define-read-only (get-checkpoint (route-id uint) (checkpoint-id uint))
    (ok (map-get? checkpoints {route-id: route-id, checkpoint-id: checkpoint-id}))
)

(define-read-only (get-payment-info (route-id uint))
    (ok (map-get? route-payments route-id))
)

(define-read-only (get-transporter-stats (transporter principal))
    (ok (map-get? transporter-stats transporter))
)

(define-read-only (get-route-progress (route-id uint))
    (let
        (
            (route (unwrap! (map-get? routes route-id) err-not-found))
        )
        (ok {
            verified: (get verified-checkpoints route),
            total: (get total-checkpoints route),
            percentage: (/ (* (get verified-checkpoints route) u100) (get total-checkpoints route))
        })
    )
)

(define-read-only (get-payment-progress (route-id uint))
    (let
        (
            (payment (unwrap! (map-get? route-payments route-id) err-not-found))
        )
        (ok {
            total-amount: (get amount payment),
            released-amount: (get amount-released payment),
            remaining-amount: (- (get amount payment) (get amount-released payment)),
            percentage-released: (/ (* (get amount-released payment) u100) (get amount payment)),
            fully-released: (get fully-released payment)
        })
    )
)

(define-read-only (is-checkpoint-valid (route-id uint) (checkpoint-id uint) (actual-lat int) (actual-lon int))
    (let
        (
            (checkpoint (unwrap! (map-get? checkpoints {route-id: route-id, checkpoint-id: checkpoint-id}) err-not-found))
            (lat-diff (if (>= actual-lat (get latitude checkpoint))
                         (- actual-lat (get latitude checkpoint))
                         (- (get latitude checkpoint) actual-lat)))
            (lon-diff (if (>= actual-lon (get longitude checkpoint))
                         (- actual-lon (get longitude checkpoint))
                         (- (get longitude checkpoint) actual-lon)))
        )
        (ok (and 
            (<= (to-uint lat-diff) (get tolerance checkpoint))
            (<= (to-uint lon-diff) (get tolerance checkpoint))
        ))
    )
)

(define-public (dispute-route (route-id uint))
    (let
        (
            (route (unwrap! (map-get? routes route-id) err-not-found))
            (payment (unwrap! (map-get? route-payments route-id) err-not-found))
            (current-height stacks-block-height)
            (expired-count (count-expired-checkpoints route-id (get total-checkpoints route) current-height))
        )
        (asserts! (is-eq tx-sender (get shipper route)) err-unauthorized)
        (asserts! (is-eq (get status route) "active") err-route-not-active)
        (asserts! (is-none (map-get? route-disputes route-id)) err-dispute-exists)
        (asserts! (> expired-count u0) err-no-expired-checkpoints)
        (let
            (
                (refund-per-checkpoint (/ (get payment-amount route) (get total-checkpoints route)))
                (total-refund (* refund-per-checkpoint expired-count))
            )
            (map-set route-disputes route-id {
                disputed-by: tx-sender,
                disputed-at: current-height,
                expired-checkpoints: expired-count,
                refund-amount: total-refund,
                processed: false
            })
            (ok {expired-count: expired-count, refund-amount: total-refund})
        )
    )
)

(define-public (process-dispute (route-id uint))
    (let
        (
            (route (unwrap! (map-get? routes route-id) err-not-found))
            (dispute (unwrap! (map-get? route-disputes route-id) err-invalid-dispute))
            (payment (unwrap! (map-get? route-payments route-id) err-not-found))
        )
        (asserts! (is-eq tx-sender (get shipper route)) err-unauthorized)
        (asserts! (not (get processed dispute)) err-invalid-dispute)
        (let
            (
                (available-refund (- (get amount payment) (get amount-released payment)))
                (actual-refund (if (<= (get refund-amount dispute) available-refund)
                                  (get refund-amount dispute)
                                  available-refund))
            )
            (if (> actual-refund u0)
                (try! (as-contract (stx-transfer? actual-refund tx-sender (get shipper route))))
                true
            )
            (map-set route-disputes route-id
                (merge dispute {processed: true})
            )
            (map-set routes route-id
                (merge route {status: "disputed"})
            )
            (ok actual-refund)
        )
    )
)

(define-private (count-expired-checkpoints (route-id uint) (total uint) (current-height uint))
    (let
        (
            (result (fold check-checkpoint-expired (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9) {count: u0, route-id: route-id, total: total, height: current-height}))
        )
        (get count result)
    )
)

(define-private (check-checkpoint-expired (checkpoint-id uint) (acc {count: uint, route-id: uint, total: uint, height: uint}))
    (if (< checkpoint-id (get total acc))
        (let
            (
                (checkpoint-opt (map-get? checkpoints {route-id: (get route-id acc), checkpoint-id: checkpoint-id}))
            )
            (match checkpoint-opt
                checkpoint
                    (if (and (not (get verified checkpoint)) (> (get height acc) (get deadline checkpoint)))
                        (merge acc {count: (+ (get count acc) u1)})
                        acc
                    )
                acc
            )
        )
        acc
    )
)

(define-read-only (get-dispute-info (route-id uint))
    (ok (map-get? route-disputes route-id))
)
