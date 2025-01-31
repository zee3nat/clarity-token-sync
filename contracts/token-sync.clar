;; Token Sync Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))

;; Data structures
(define-map assets 
  { asset-id: uint }
  {
    owner: principal,
    state: uint,
    last-updated: uint
  }
)

(define-map asset-history
  { asset-id: uint, seq: uint }
  {
    prev-owner: principal,
    new-owner: principal,
    prev-state: uint,
    new-state: uint,
    timestamp: uint
  }
)

;; State tracking
(define-data-var last-asset-id uint u0)
(define-data-var last-sequence uint u0)

;; Core functions
(define-public (create-asset (initial-state uint))
  (let
    (
      (asset-id (+ (var-get last-asset-id) u1))
    )
    (map-set assets
      { asset-id: asset-id }
      {
        owner: tx-sender,
        state: initial-state,
        last-updated: block-height
      }
    )
    (var-set last-asset-id asset-id)
    (ok asset-id)
  )
)

(define-public (transfer-asset (asset-id uint) (new-owner principal))
  (let
    (
      (asset (unwrap! (map-get? assets {asset-id: asset-id}) (err err-not-found)))
    )
    (asserts! (is-eq (get owner asset) tx-sender) (err err-unauthorized))
    (map-set assets
      { asset-id: asset-id }
      {
        owner: new-owner,
        state: (get state asset),
        last-updated: block-height
      }
    )
    (ok true)
  )
)

(define-public (update-state (asset-id uint) (new-state uint))
  (let
    (
      (asset (unwrap! (map-get? assets {asset-id: asset-id}) (err err-not-found)))
      (seq (+ (var-get last-sequence) u1))
    )
    (asserts! (is-eq (get owner asset) tx-sender) (err err-unauthorized))
    (map-set asset-history
      { asset-id: asset-id, seq: seq }
      {
        prev-owner: (get owner asset),
        new-owner: (get owner asset),
        prev-state: (get state asset),
        new-state: new-state,
        timestamp: block-height
      }
    )
    (map-set assets
      { asset-id: asset-id }
      {
        owner: (get owner asset),
        state: new-state,
        last-updated: block-height
      }
    )
    (var-set last-sequence seq)
    (ok true)
  )
)

;; Read functions
(define-read-only (get-asset (asset-id uint))
  (ok (map-get? assets {asset-id: asset-id}))
)

(define-read-only (get-history (asset-id uint) (seq uint))
  (ok (map-get? asset-history {asset-id: asset-id, seq: seq}))
)
