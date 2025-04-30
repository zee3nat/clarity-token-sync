```clarity
;; Token Sync Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-permission (err u103))
(define-constant err-batch-operation-failed (err u104))

;; Permission types
(define-constant permission-none u0)
(define-constant permission-update u1)
(define-constant permission-transfer u2)
(define-constant permission-full u3)

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

(define-map asset-metadata
  { asset-id: uint }
  {
    name: (string-ascii 64),
    description: (string-utf8 256),
    uri: (string-utf8 256),
    properties: (list 20 (tuple (key (string-ascii 32)) (value (string-utf8 128))))
  }
)

(define-map asset-permissions
  { asset-id: uint, delegate: principal }
  {
    permission-type: uint
  }
)

(define-map cross-chain-refs
  { asset-id: uint, chain-id: (string-ascii 32) }
  {
    external-id: (string-ascii 64)
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

(define-public (create-asset-with-metadata (initial-state uint) (name (string-ascii 64)) (description (string-utf8 256)) (uri (string-utf8 256)) (properties (list 20 (tuple (key (string-ascii 32)) (value (string-utf8 128))))))
  (let
    (
      (asset-id (unwrap! (create-asset initial-state) (err err-unauthorized)))
    )
    (map-set asset-metadata
      { asset-id: asset-id }
      {
        name: name,
        description: description,
        uri: uri,
        properties: properties
      }
    )
    (ok asset-id)
  )
)

(define-public (batch-create-assets (initial-states (list 50 uint)))
  (let
    (
      (result (fold create-asset-fold initial-states (list)))
    )
    (ok result)
  )
)

(define-private (create-asset-fold (initial-state uint) (result-list (list 50 uint)))
  (match (create-asset initial-state)
    asset-id (append result-list asset-id)
    error result-list
  )
)

(define-public (transfer-asset (asset-id uint) (new-owner principal))
  (let
    (
      (asset (unwrap! (map-get? assets {asset-id: asset-id}) (err err-not-found)))
    )
    (asserts! (or 
      (is-eq (get owner asset) tx-sender)
      (has-permission asset-id tx-sender permission-transfer)
      (has-permission asset-id tx-sender permission-full)
    ) (err err-unauthorized))
    
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

(define-public (batch-transfer-assets (asset-ids (list 50 uint)) (new-owner principal))
  (fold batch-transfer-fold (map package-transfer asset-ids (list 50 principal true)) true)
)

(define-private (package-transfer (asset-id uint) (result-list (list 50 principal)))
  tx-sender
)

(define-private (batch-transfer-fold (args (tuple (asset-id uint) (recipient principal))) (previous-result bool))
  (if previous-result
    (match (transfer-asset (get asset-id args) (get recipient args))
      success previous-result
      error false
    )
    previous-result
  )
)

(define-public (update-state (asset-id uint) (new-state uint))
  (let
    (
      (asset (unwrap! (map-get? assets {asset-id: asset-id}) (err err-not-found)))
      (seq (+ (var-get last-sequence) u1))
    )
    (asserts! (or 
      (is-eq (get owner asset) tx-sender)
      (has-permission asset-id tx-sender permission-update)
      (has-permission asset-id tx-sender permission-full)
    ) (err err-unauthorized))
    
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

(define-public (batch-update-states (asset-ids (list 50 uint)) (new-states (list 50 uint)))
  (let
    (
      (combined-list (zip asset-ids new-states))
    )
    (ok (fold batch-update-fold combined-list true))
  )
)

(define-private (batch-update-fold (args (tuple (id uint) (state uint))) (previous-result bool))
  (if previous-result
    (match (update-state (get id args) (get state args))
      success true
      error false
    )
    previous-result
  )
)

(define-public (grant-permission (asset-id uint) (delegate principal) (permission-type uint))
  (let
    (
      (asset (unwrap! (map-get? assets {asset-id: asset-id}) (err err-not-found)))
    )
    (asserts! (is-eq (get owner asset) tx-sender) (err err-unauthorized))
    (asserts! (or 
      (is-eq permission-type permission-none)
      (is-eq permission-type permission-update)
      (is-eq permission-type permission-transfer)
      (is-eq permission-type permission-full)
    ) (err err-invalid-permission))
    
    (map-set asset-permissions
      { asset-id: asset-id, delegate: delegate }
      {
        permission-type: permission-type
      }
    )
    (ok true)
  )
)

(define-public (revoke-permission (asset-id uint) (delegate principal))
  (grant-permission asset-id delegate permission-none)
)

(define-public (set-metadata (asset-id uint) (name (string-ascii 64)) (description (string-utf8 256)) (uri (string-utf8 256)) (properties (list 20 (tuple (key (string-ascii 32)) (value (string-utf8 128))))))
  (let
    (
      (asset (unwrap! (map-get? assets {asset-id: asset-id}) (err err-not-found)))
    )
    (asserts! (or 
      (is-eq (get owner asset) tx-sender)
      (has-permission asset-id tx-sender permission-update)
      (has-permission asset-id tx-sender permission-full)
    ) (err err-unauthorized))
    
    (map-set asset-metadata
      { asset-id: asset-id }
      {
        name: name,
        description: description,
        uri: uri,
        properties: properties
      }
    )
    (ok true)
  )
)

(define-public (set-cross-chain-ref (asset-id uint) (chain-id (string-ascii 32)) (external-id (string-ascii 64)))
  (let
    (
      (asset (unwrap! (map-get? assets {asset-id: asset-id}) (err err-not-found)))
    )
    (asserts! (is-eq (get owner asset) tx-sender) (err err-unauthorized))
    (map-set cross-chain-refs
      { asset-id: asset-id, chain-id: chain-id }
      {
        external-id: external-id
      }
    )
    (ok true)
  )
)

;; Permission helper functions
(define-private (has-permission (asset-id uint) (principal principal) (required-permission uint))
  (let
    (
      (current-permission (default-to { permission-type: permission-none } 
                           (map-get? asset-permissions { asset-id: asset-id, delegate: principal })))
    )
    (is-eq (get permission-type current-permission) required-permission)
  )
)

;; Read functions
(define-read-only (get-asset (asset-id uint))
  (ok (map-get? assets {asset-id: asset-id}))
)

(define-read-only (get-history (asset-id uint) (seq uint))
  (ok (map-get? asset-history {asset-id: asset-id, seq: seq}))
)

(define-read-only (get-metadata (asset-id uint))
  (ok (map-get? asset-metadata {asset-id: asset-id}))
)

(define-read-only (get-permission (asset-id uint) (delegate principal))
  (ok (map-get? asset-permissions {asset-id: asset-id, delegate: delegate}))
)

(define-read-only (get-cross-chain-ref (asset-id uint) (chain-id (string-ascii 32)))
  (ok (map-get? cross-chain-refs {asset-id: asset-id, chain-id: chain-id}))
)
```