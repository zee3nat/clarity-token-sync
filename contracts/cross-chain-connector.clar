;; cross-chain-connector
;; 
;; This contract enables asset state synchronization across multiple blockchain networks.
;; It establishes a verifiable bridge that maintains the integrity of asset states
;; when represented on other chains. Users can "project" their assets onto supported 
;; networks while maintaining a single source of truth for ownership and state.

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-CHAIN-ID (err u101))
(define-constant ERR-ASSET-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-PROJECTED (err u103))
(define-constant ERR-NOT-PROJECTED (err u104))
(define-constant ERR-INVALID-ASSET-ID (err u105))
(define-constant ERR-INVALID-SIGNATURE (err u106))
(define-constant ERR-PROJECTION-LOCKED (err u107))
(define-constant ERR-INVALID-VALIDATOR (err u108))

;; Data space definitions

;; Manage supported blockchain networks
(define-map supported-chains
  { chain-id: uint }
  { 
    chain-name: (string-ascii 64),
    active: bool 
  }
)

;; Track assets that have been projected to other chains
;; Maps (asset-id, chain-id) -> projection data
(define-map asset-projections
  { 
    asset-id: uint,
    chain-id: uint 
  }
  {
    owner: principal,
    projected-at: uint,
    is-active: bool,
    projection-lock-until: uint,
    external-reference: (string-ascii 128)
  }
)

;; Track each asset's projections across all chains
;; Maps asset-id -> list of chain-ids where it's been projected
(define-map asset-projection-chains
  { asset-id: uint }
  { chain-ids: (list 20 uint) }
)

;; Cross-chain validators who can verify states
(define-map validators
  { validator-address: principal }
  { active: bool, added-at: uint }
)

;; Aggregate validation threshold
(define-data-var validation-threshold uint u3)

;; Contract administrator
(define-data-var contract-admin principal tx-sender)

;; Private functions

;; Helper function to validate that a chain is supported
(define-private (is-valid-chain (chain-id uint))
  (match (map-get? supported-chains { chain-id: chain-id })
    chain-data (and (get active chain-data) true)
    false
  )
)

;; Helper function to verify if caller is contract admin
(define-private (is-contract-admin)
  (is-eq tx-sender (var-get contract-admin))
)

;; Helper function to check if an asset is already projected to a chain
(define-private (is-asset-projected (asset-id uint) (chain-id uint))
  (match (map-get? asset-projections { asset-id: asset-id, chain-id: chain-id })
    projection-data (get is-active projection-data)
    false
  )
)

;; Helper function to check if the caller owns the asset
(define-private (owns-asset (asset-id uint))
  ;; This function would integrate with your specific asset contract
  ;; For example, by calling a read-only function on a NFT or FT contract
  ;; Simplified placeholder implementation:
  true
)

;; Helper function to add a chain to an asset's projection list
(define-private (add-chain-to-asset-projections (asset-id uint) (chain-id uint))
  (let (
    (current-chains (default-to { chain-ids: (list) } 
                     (map-get? asset-projection-chains { asset-id: asset-id })))
    (updated-chains (unwrap-panic 
                     (as-max-len? 
                      (append (get chain-ids current-chains) chain-id)
                      u20)))
  )
    (map-set asset-projection-chains 
      { asset-id: asset-id }
      { chain-ids: updated-chains })
  )
)

;; Helper function to remove a chain from an asset's projection list
(define-private (remove-chain-from-projections (asset-id uint) (chain-id uint))
  (let (
    (current-chains (default-to { chain-ids: (list) } 
                     (map-get? asset-projection-chains { asset-id: asset-id })))
    (filtered-chains (filter (lambda (id) (not (is-eq id chain-id))) 
                             (get chain-ids current-chains)))
  )
    (map-set asset-projection-chains 
      { asset-id: asset-id }
      { chain-ids: filtered-chains })
  )
)

;; Read-only functions

;; Check if a chain is supported
(define-read-only (is-chain-supported (chain-id uint))
  (is-valid-chain chain-id)
)

;; Get all chains where an asset is currently projected
(define-read-only (get-asset-projections (asset-id uint))
  (default-to { chain-ids: (list) } 
    (map-get? asset-projection-chains { asset-id: asset-id }))
)

;; Get details of an asset's projection on a specific chain
(define-read-only (get-projection-details (asset-id uint) (chain-id uint))
  (map-get? asset-projections { asset-id: asset-id, chain-id: chain-id })
)

;; Check if a given principal is a validator
(define-read-only (is-validator (validator-address principal))
  (match (map-get? validators { validator-address: validator-address })
    validator-data (get active validator-data)
    false
  )
)

;; Get current validation threshold
(define-read-only (get-validation-threshold)
  (var-get validation-threshold)
)

;; Public functions

;; Add a new supported blockchain network
(define-public (add-supported-chain (chain-id uint) (chain-name (string-ascii 64)))
  (begin
    (asserts! (is-contract-admin) ERR-UNAUTHORIZED)
    (asserts! (not (is-valid-chain chain-id)) (err u109)) ;; Chain ID already exists
    
    (map-set supported-chains
      { chain-id: chain-id }
      { chain-name: chain-name, active: true })
    
    (ok true)
  )
)

;; Deactivate a supported blockchain network
(define-public (deactivate-chain (chain-id uint))
  (begin
    (asserts! (is-contract-admin) ERR-UNAUTHORIZED)
    (asserts! (is-valid-chain chain-id) ERR-INVALID-CHAIN-ID)
    
    (match (map-get? supported-chains { chain-id: chain-id })
      chain-data (map-set supported-chains
                   { chain-id: chain-id }
                   { chain-name: (get chain-name chain-data), active: false })
      (err u110) ;; Chain not found (shouldn't happen due to prior check)
    )
    
    (ok true)
  )
)

;; Project an asset to another chain
(define-public (project-asset (asset-id uint) (chain-id uint) (external-reference (string-ascii 128)))
  (begin
    (asserts! (is-valid-chain chain-id) ERR-INVALID-CHAIN-ID)
    (asserts! (owns-asset asset-id) ERR-UNAUTHORIZED)
    (asserts! (not (is-asset-projected asset-id chain-id)) ERR-ALREADY-PROJECTED)
    
    ;; Record the projection
    (map-set asset-projections
      { asset-id: asset-id, chain-id: chain-id }
      {
        owner: tx-sender,
        projected-at: block-height,
        is-active: true,
        projection-lock-until: u0,
        external-reference: external-reference
      }
    )
    
    ;; Update the asset's projection chains
    (add-chain-to-asset-projections asset-id chain-id)
    
    (ok true)
  )
)

;; Withdraw a projection from another chain
(define-public (withdraw-projection (asset-id uint) (chain-id uint))
  (begin
    (asserts! (is-valid-chain chain-id) ERR-INVALID-CHAIN-ID)
    
    (match (map-get? asset-projections { asset-id: asset-id, chain-id: chain-id })
      projection-data (begin
        (asserts! (is-eq tx-sender (get owner projection-data)) ERR-UNAUTHORIZED)
        (asserts! (get is-active projection-data) ERR-NOT-PROJECTED)
        (asserts! (< (get projection-lock-until projection-data) block-height) ERR-PROJECTION-LOCKED)
        
        ;; Update projection status
        (map-set asset-projections
          { asset-id: asset-id, chain-id: chain-id }
          (merge projection-data { is-active: false })
        )
        
        ;; Remove chain from asset projections
        (remove-chain-from-projections asset-id chain-id)
        
        (ok true)
      )
      ERR-ASSET-NOT-FOUND
    )
  )
)

;; Lock a projection for a period
(define-public (lock-projection (asset-id uint) (chain-id uint) (lock-period uint))
  (begin
    (match (map-get? asset-projections { asset-id: asset-id, chain-id: chain-id })
      projection-data (begin
        (asserts! (is-eq tx-sender (get owner projection-data)) ERR-UNAUTHORIZED)
        (asserts! (get is-active projection-data) ERR-NOT-PROJECTED)
        
        ;; Set the lock period
        (map-set asset-projections
          { asset-id: asset-id, chain-id: chain-id }
          (merge projection-data { projection-lock-until: (+ block-height lock-period) })
        )
        
        (ok true)
      )
      ERR-ASSET-NOT-FOUND
    )
  )
)

;; Update the external reference for a projection
(define-public (update-external-reference (asset-id uint) (chain-id uint) (new-reference (string-ascii 128)))
  (begin
    (match (map-get? asset-projections { asset-id: asset-id, chain-id: chain-id })
      projection-data (begin
        (asserts! (is-eq tx-sender (get owner projection-data)) ERR-UNAUTHORIZED)
        (asserts! (get is-active projection-data) ERR-NOT-PROJECTED)
        
        ;; Update the external reference
        (map-set asset-projections
          { asset-id: asset-id, chain-id: chain-id }
          (merge projection-data { external-reference: new-reference })
        )
        
        (ok true)
      )
      ERR-ASSET-NOT-FOUND
    )
  )
)

;; Add a new validator
(define-public (add-validator (validator-address principal))
  (begin
    (asserts! (is-contract-admin) ERR-UNAUTHORIZED)
    (asserts! (not (is-validator validator-address)) ERR-INVALID-VALIDATOR)
    
    (map-set validators
      { validator-address: validator-address }
      { active: true, added-at: block-height }
    )
    
    (ok true)
  )
)

;; Remove a validator
(define-public (remove-validator (validator-address principal))
  (begin
    (asserts! (is-contract-admin) ERR-UNAUTHORIZED)
    
    (match (map-get? validators { validator-address: validator-address })
      validator-data (map-set validators
                       { validator-address: validator-address }
                       (merge validator-data { active: false })
                     )
      (err u111) ;; Validator not found
    )
    
    (ok true)
  )
)

;; Update validation threshold
(define-public (set-validation-threshold (new-threshold uint))
  (begin
    (asserts! (is-contract-admin) ERR-UNAUTHORIZED)
    (asserts! (> new-threshold u0) (err u112)) ;; Threshold must be greater than zero
    
    (var-set validation-threshold new-threshold)
    
    (ok true)
  )
)

;; Transfer contract administration
(define-public (transfer-admin (new-admin principal))
  (begin
    (asserts! (is-contract-admin) ERR-UNAUTHORIZED)
    
    (var-set contract-admin new-admin)
    
    (ok true)
  )
)