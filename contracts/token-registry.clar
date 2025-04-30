;; token-registry
;; 
;; A centralized registry for asset discovery and verification on the Stacks blockchain.
;; This contract maintains a directory of tokenized assets, providing searching and 
;; verification capabilities to help users discover and validate legitimate assets.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TOKEN-ALREADY-EXISTS (err u101))
(define-constant ERR-TOKEN-NOT-FOUND (err u102))
(define-constant ERR-INVALID-CATEGORY (err u103))
(define-constant ERR-ADMIN-ONLY (err u104))
(define-constant ERR-VERIFICATION-STATUS-INVALID (err u105))

;; Valid categories for tokens
(define-constant CATEGORY-ART u1)
(define-constant CATEGORY-COLLECTIBLE u2)
(define-constant CATEGORY-GAME u3)
(define-constant CATEGORY-DEFI u4)
(define-constant CATEGORY-UTILITY u5)
(define-constant CATEGORY-OTHER u6)

;; Verification statuses
(define-constant STATUS-UNVERIFIED u0)
(define-constant STATUS-VERIFIED u1)
(define-constant STATUS-REJECTED u2)

;; Contract administration
(define-data-var contract-owner principal tx-sender)

;; Data structures

;; Token registry map - stores token information
;; Indexed by [asset-contract, token-id]
(define-map tokens 
  { asset-contract: principal, token-id: (optional uint) }
  {
    name: (string-ascii 64),
    creator: principal,
    category: uint,
    verification-status: uint,
    metadata-url: (optional (string-utf8 256)),
    created-at: uint,
    updated-at: uint
  }
)

;; Secondary index for tokens by creator
(define-map tokens-by-creator
  { creator: principal }
  { token-keys: (list 100 { asset-contract: principal, token-id: (optional uint) }) }
)

;; Secondary index for tokens by category
(define-map tokens-by-category
  { category: uint }
  { token-keys: (list 100 { asset-contract: principal, token-id: (optional uint) }) }
)

;; Total number of registered tokens
(define-data-var total-tokens uint u0)

;; Private functions

;; Check if category is valid
(define-private (is-valid-category (category uint))
  (or
    (is-eq category CATEGORY-ART)
    (is-eq category CATEGORY-COLLECTIBLE)
    (is-eq category CATEGORY-GAME)
    (is-eq category CATEGORY-DEFI)
    (is-eq category CATEGORY-UTILITY)
    (is-eq category CATEGORY-OTHER)
  )
)

;; Check if verification status is valid
(define-private (is-valid-verification-status (status uint))
  (or
    (is-eq status STATUS-UNVERIFIED)
    (is-eq status STATUS-VERIFIED)
    (is-eq status STATUS-REJECTED)
  )
)

;; Check if caller is the contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Add token to creator index
(define-private (add-to-creator-index (token-key { asset-contract: principal, token-id: (optional uint) }) (creator principal))
  (let (
    (existing-entry (default-to { token-keys: (list) } (map-get? tokens-by-creator { creator: creator })))
    (updated-keys (unwrap-panic (as-max-len? (append (get token-keys existing-entry) token-key) u100)))
  )
    (map-set tokens-by-creator { creator: creator } { token-keys: updated-keys })
  )
)

;; Add token to category index
(define-private (add-to-category-index (token-key { asset-contract: principal, token-id: (optional uint) }) (category uint))
  (let (
    (existing-entry (default-to { token-keys: (list) } (map-get? tokens-by-category { category: category })))
    (updated-keys (unwrap-panic (as-max-len? (append (get token-keys existing-entry) token-key) u100)))
  )
    (map-set tokens-by-category { category: category } { token-keys: updated-keys })
  )
)

;; Read-only functions

;; Get token information
(define-read-only (get-token (asset-contract principal) (token-id (optional uint)))
  (map-get? tokens { asset-contract: asset-contract, token-id: token-id })
)

;; Get tokens by creator
(define-read-only (get-tokens-by-creator (creator principal))
  (let (
    (creator-entry (map-get? tokens-by-creator { creator: creator }))
  )
    (match creator-entry
      entry (ok (get token-keys entry))
      (ok (list))
    )
  )
)

;; Get tokens by category
(define-read-only (get-tokens-by-category (category uint))
  (if (is-valid-category category)
    (let (
      (category-entry (map-get? tokens-by-category { category: category }))
    )
      (match category-entry
        entry (ok (get token-keys entry))
        (ok (list))
      )
    )
    ERR-INVALID-CATEGORY
  )
)

;; Get token count
(define-read-only (get-total-tokens)
  (var-get total-tokens)
)

;; Check if a token is verified
(define-read-only (is-token-verified (asset-contract principal) (token-id (optional uint)))
  (match (map-get? tokens { asset-contract: asset-contract, token-id: token-id })
    token-data (is-eq (get verification-status token-data) STATUS-VERIFIED)
    false
  )
)

;; Public functions

;; Register a new token
(define-public (register-token 
  (asset-contract principal) 
  (token-id (optional uint)) 
  (name (string-ascii 64)) 
  (category uint) 
  (metadata-url (optional (string-utf8 256)))
)
  (let (
    (token-key { asset-contract: asset-contract, token-id: token-id })
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Check if token already exists
    (asserts! (is-none (map-get? tokens token-key)) ERR-TOKEN-ALREADY-EXISTS)
    
    ;; Check if category is valid
    (asserts! (is-valid-category category) ERR-INVALID-CATEGORY)
    
    ;; Add token to registry
    (map-set tokens token-key {
      name: name,
      creator: tx-sender,
      category: category,
      verification-status: STATUS-UNVERIFIED,
      metadata-url: metadata-url,
      created-at: current-time,
      updated-at: current-time
    })
    
    ;; Update indices
    (add-to-creator-index token-key tx-sender)
    (add-to-category-index token-key category)
    
    ;; Increment total token count
    (var-set total-tokens (+ (var-get total-tokens) u1))
    
    (ok true)
  )
)

;; Update token information (only by creator)
(define-public (update-token 
  (asset-contract principal) 
  (token-id (optional uint)) 
  (name (string-ascii 64)) 
  (category uint) 
  (metadata-url (optional (string-utf8 256)))
)
  (let (
    (token-key { asset-contract: asset-contract, token-id: token-id })
    (current-time (unwrap-panic (get-block-info? time u0)))
    (token-data (map-get? tokens token-key))
  )
    ;; Check if token exists
    (asserts! (is-some token-data) ERR-TOKEN-NOT-FOUND)
    
    ;; Check if caller is the creator
    (asserts! (is-eq tx-sender (get creator (unwrap-panic token-data))) ERR-NOT-AUTHORIZED)
    
    ;; Check if category is valid
    (asserts! (is-valid-category category) ERR-INVALID-CATEGORY)
    
    ;; Update token information
    (map-set tokens token-key {
      name: name,
      creator: (get creator (unwrap-panic token-data)),
      category: category,
      verification-status: (get verification-status (unwrap-panic token-data)),
      metadata-url: metadata-url,
      created-at: (get created-at (unwrap-panic token-data)),
      updated-at: current-time
    })
    
    (ok true)
  )
)

;; Verify or reject a token (admin only)
(define-public (set-verification-status 
  (asset-contract principal) 
  (token-id (optional uint)) 
  (status uint)
)
  (let (
    (token-key { asset-contract: asset-contract, token-id: token-id })
    (token-data (map-get? tokens token-key))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Check if caller is the contract owner
    (asserts! (is-contract-owner) ERR-ADMIN-ONLY)
    
    ;; Check if token exists
    (asserts! (is-some token-data) ERR-TOKEN-NOT-FOUND)
    
    ;; Check if status is valid
    (asserts! (is-valid-verification-status status) ERR-VERIFICATION-STATUS-INVALID)
    
    ;; Update token verification status
    (map-set tokens token-key {
      name: (get name (unwrap-panic token-data)),
      creator: (get creator (unwrap-panic token-data)),
      category: (get category (unwrap-panic token-data)),
      verification-status: status,
      metadata-url: (get metadata-url (unwrap-panic token-data)),
      created-at: (get created-at (unwrap-panic token-data)),
      updated-at: current-time
    })
    
    (ok true)
  )
)

;; Transfer contract ownership (admin only)
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-ADMIN-ONLY)
    (var-set contract-owner new-owner)
    (ok true)
  )
)