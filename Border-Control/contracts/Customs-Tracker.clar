;; Decentralized Customs Clearance Smart Contract
;; This contract manages customs declarations, payments, approvals, and tracking

;; Constants
(define-constant contract-owner tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-UNAUTHORIZED-ACCESS (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u104))
(define-constant ERR-ALREADY-EXISTS (err u105))
(define-constant ERR-INVALID-INPUT (err u106))
(define-constant ERR-EXPIRED (err u107))
(define-constant ERR-INVALID-OFFICER (err u108))

;; Data Variables
(define-data-var next-declaration-id uint u1)
(define-data-var customs-fee uint u1000000) ;; 1 STX in microSTX
(define-data-var processing-time uint u2016) ;; ~2 weeks in blocks (10 min blocks)

;; Declaration Status Constants
(define-constant STATUS-PENDING u0)
(define-constant STATUS-UNDER-REVIEW u1)
(define-constant STATUS-APPROVED u2)
(define-constant STATUS-REJECTED u3)
(define-constant STATUS-RELEASED u4)
(define-constant STATUS-EXPIRED u5)

;; Maps
(define-map declarations
  { declaration-id: uint }
  {
    importer: principal,
    goods-description: (string-ascii 256),
    goods-value: uint,
    origin-country: (string-ascii 64),
    destination-country: (string-ascii 64),
    weight: uint,
    category: (string-ascii 64),
    status: uint,
    submitted-at: uint,
    reviewed-at: (optional uint),
    approved-at: (optional uint),
    customs-fee-paid: uint,
    reviewing-officer: (optional principal),
    rejection-reason: (optional (string-ascii 256)),
    tracking-number: (string-ascii 32),
    expiry-block: uint
  }
)

(define-map authorized-officers
  { officer: principal }
  {
    name: (string-ascii 64),
    department: (string-ascii 64),
    authorized-at: uint,
    is-active: bool
  }
)

(define-map importer-profiles
  { importer: principal }
  {
    name: (string-ascii 64),
    license-number: (string-ascii 32),
    registration-date: uint,
    total-declarations: uint,
    approved-declarations: uint,
    is-verified: bool
  }
)

(define-map country-tax-rates
  { country: (string-ascii 64) }
  {
    tax-rate: uint, ;; basis points (100 = 1%)
    is-restricted: bool
  }
)

(define-map category-restrictions
  { category: (string-ascii 64) }
  {
    requires-license: bool,
    additional-fee: uint,
    max-value: (optional uint)
  }
)

;; Authorization Functions
(define-public (add-customs-officer (officer principal) (name (string-ascii 64)) (department (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
    (asserts! (is-none (map-get? authorized-officers { officer: officer })) ERR-ALREADY-EXISTS)
    (ok (map-set authorized-officers
      { officer: officer }
      {
        name: name,
        department: department,
        authorized-at: block-height,
        is-active: true
      }
    ))
  )
)

(define-public (deactivate-officer (officer principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
    (match (map-get? authorized-officers { officer: officer })
      officer-data (ok (map-set authorized-officers
        { officer: officer }
        (merge officer-data { is-active: false })
      ))
      ERR-NOT-FOUND
    )
  )
)

(define-public (register-importer (name (string-ascii 64)) (license-number (string-ascii 32)))
  (begin
    (asserts! (is-none (map-get? importer-profiles { importer: tx-sender })) ERR-ALREADY-EXISTS)
    (ok (map-set importer-profiles
      { importer: tx-sender }
      {
        name: name,
        license-number: license-number,
        registration-date: block-height,
        total-declarations: u0,
        approved-declarations: u0,
        is-verified: false
      }
    ))
  )
)

;; Configuration Functions
(define-public (set-customs-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
    (ok (var-set customs-fee new-fee))
  )
)

(define-public (set-processing-time (new-time uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
    (ok (var-set processing-time new-time))
  )
)

(define-public (set-country-tax-rate (country (string-ascii 64)) (tax-rate uint) (is-restricted bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
    (ok (map-set country-tax-rates
      { country: country }
      {
        tax-rate: tax-rate,
        is-restricted: is-restricted
      }
    ))
  )
)

(define-public (set-category-restriction (category (string-ascii 64)) (requires-license bool) (additional-fee uint) (max-value (optional uint)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
    (ok (map-set category-restrictions
      { category: category }
      {
        requires-license: requires-license,
        additional-fee: additional-fee,
        max-value: max-value
      }
    ))
  )
)

;; Core Declaration Functions
(define-public (submit-declaration 
  (goods-description (string-ascii 256))
  (goods-value uint)
  (origin-country (string-ascii 64))
  (destination-country (string-ascii 64))
  (weight uint)
  (category (string-ascii 64))
  (tracking-number (string-ascii 32))
)
  (let
    (
      (declaration-id (var-get next-declaration-id))
      (total-fee (calculate-total-fee goods-value origin-country category))
      (expiry-block (+ block-height (var-get processing-time)))
    )
    (asserts! (> (len goods-description) u0) ERR-INVALID-INPUT)
    (asserts! (> goods-value u0) ERR-INVALID-INPUT)
    (asserts! (> weight u0) ERR-INVALID-INPUT)
    (asserts! (> (len tracking-number) u0) ERR-INVALID-INPUT)
    
    ;; Check if country is restricted
    (match (map-get? country-tax-rates { country: origin-country })
      country-data (asserts! (not (get is-restricted country-data)) ERR-INVALID-INPUT)
      true ;; Country not in map, allow
    )
    
    ;; Check category restrictions
    (match (map-get? category-restrictions { category: category })
      category-data (begin
        (match (get max-value category-data)
          max-val (asserts! (<= goods-value max-val) ERR-INVALID-INPUT)
          true
        )
        (if (get requires-license category-data)
          (match (map-get? importer-profiles { importer: tx-sender })
            profile (asserts! (get is-verified profile) ERR-UNAUTHORIZED-ACCESS)
            (asserts! false ERR-UNAUTHORIZED-ACCESS)
          )
          true
        )
      )
      true ;; Category not restricted
    )
    
    ;; Transfer payment
    (try! (stx-transfer? total-fee tx-sender (as-contract tx-sender)))
    
    ;; Create declaration
    (map-set declarations
      { declaration-id: declaration-id }
      {
        importer: tx-sender,
        goods-description: goods-description,
        goods-value: goods-value,
        origin-country: origin-country,
        destination-country: destination-country,
        weight: weight,
        category: category,
        status: STATUS-PENDING,
        submitted-at: block-height,
        reviewed-at: none,
        approved-at: none,
        customs-fee-paid: total-fee,
        reviewing-officer: none,
        rejection-reason: none,
        tracking-number: tracking-number,
        expiry-block: expiry-block
      }
    )
    
    ;; Update importer profile
    (match (map-get? importer-profiles { importer: tx-sender })
      profile (map-set importer-profiles
        { importer: tx-sender }
        (merge profile { total-declarations: (+ (get total-declarations profile) u1) })
      )
      true ;; Profile doesn't exist, that's ok
    )
    
    ;; Increment declaration ID
    (var-set next-declaration-id (+ declaration-id u1))
    
    (ok declaration-id)
  )
)

(define-public (review-declaration (declaration-id uint))
  (let
    (
      (declaration (unwrap! (map-get? declarations { declaration-id: declaration-id }) ERR-NOT-FOUND))
      (officer-data (unwrap! (map-get? authorized-officers { officer: tx-sender }) ERR-UNAUTHORIZED-ACCESS))
    )
    (asserts! (get is-active officer-data) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (get status declaration) STATUS-PENDING) ERR-INVALID-STATUS)
    (asserts! (< block-height (get expiry-block declaration)) ERR-EXPIRED)
    
    (ok (map-set declarations
      { declaration-id: declaration-id }
      (merge declaration {
        status: STATUS-UNDER-REVIEW,
        reviewed-at: (some block-height),
        reviewing-officer: (some tx-sender)
      })
    ))
  )
)

(define-public (approve-declaration (declaration-id uint))
  (let
    (
      (declaration (unwrap! (map-get? declarations { declaration-id: declaration-id }) ERR-NOT-FOUND))
      (officer-data (unwrap! (map-get? authorized-officers { officer: tx-sender }) ERR-UNAUTHORIZED-ACCESS))
    )
    (asserts! (get is-active officer-data) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (get status declaration) STATUS-UNDER-REVIEW) ERR-INVALID-STATUS)
    (asserts! (< block-height (get expiry-block declaration)) ERR-EXPIRED)
    (asserts! (is-eq (some tx-sender) (get reviewing-officer declaration)) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Update declaration
    (map-set declarations
      { declaration-id: declaration-id }
      (merge declaration {
        status: STATUS-APPROVED,
        approved-at: (some block-height)
      })
    )
    
    ;; Update importer profile
    (match (map-get? importer-profiles { importer: (get importer declaration) })
      profile (map-set importer-profiles
        { importer: (get importer declaration) }
        (merge profile { approved-declarations: (+ (get approved-declarations profile) u1) })
      )
      true
    )
    
    (ok true)
  )
)

(define-public (reject-declaration (declaration-id uint) (reason (string-ascii 256)))
  (let
    (
      (declaration (unwrap! (map-get? declarations { declaration-id: declaration-id }) ERR-NOT-FOUND))
      (officer-data (unwrap! (map-get? authorized-officers { officer: tx-sender }) ERR-UNAUTHORIZED-ACCESS))
    )
    (asserts! (get is-active officer-data) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (get status declaration) STATUS-UNDER-REVIEW) ERR-INVALID-STATUS)
    (asserts! (< block-height (get expiry-block declaration)) ERR-EXPIRED)
    (asserts! (is-eq (some tx-sender) (get reviewing-officer declaration)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (> (len reason) u0) ERR-INVALID-INPUT)
    
    ;; Refund partial fee (keep processing fee)
    (let ((refund-amount (/ (* (get customs-fee-paid declaration) u80) u100))) ;; 80% refund
      (try! (as-contract (stx-transfer? refund-amount tx-sender (get importer declaration))))
    )
    
    (ok (map-set declarations
      { declaration-id: declaration-id }
      (merge declaration {
        status: STATUS-REJECTED,
        rejection-reason: (some reason)
      })
    ))
  )
)

(define-public (release-goods (declaration-id uint))
  (let
    (
      (declaration (unwrap! (map-get? declarations { declaration-id: declaration-id }) ERR-NOT-FOUND))
      (officer-data (unwrap! (map-get? authorized-officers { officer: tx-sender }) ERR-UNAUTHORIZED-ACCESS))
    )
    (asserts! (get is-active officer-data) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (get status declaration) STATUS-APPROVED) ERR-INVALID-STATUS)
    
    (ok (map-set declarations
      { declaration-id: declaration-id }
      (merge declaration { status: STATUS-RELEASED })
    ))
  )
)

(define-public (expire-declaration (declaration-id uint))
  (let
    (
      (declaration (unwrap! (map-get? declarations { declaration-id: declaration-id }) ERR-NOT-FOUND))
    )
    (asserts! (>= block-height (get expiry-block declaration)) ERR-INVALID-STATUS)
    (asserts! (or (is-eq (get status declaration) STATUS-PENDING) 
                  (is-eq (get status declaration) STATUS-UNDER-REVIEW)) ERR-INVALID-STATUS)
    
    ;; Refund partial fee
    (let ((refund-amount (/ (* (get customs-fee-paid declaration) u60) u100))) ;; 60% refund for expired
      (try! (as-contract (stx-transfer? refund-amount tx-sender (get importer declaration))))
    )
    
    (ok (map-set declarations
      { declaration-id: declaration-id }
      (merge declaration { status: STATUS-EXPIRED })
    ))
  )
)

;; Helper Functions
(define-private (calculate-total-fee (goods-value uint) (origin-country (string-ascii 64)) (category (string-ascii 64)))
  (let
    (
      (base-fee (var-get customs-fee))
      (tax-rate (default-to u0 (get tax-rate (map-get? country-tax-rates { country: origin-country }))))
      (category-fee (default-to u0 (get additional-fee (map-get? category-restrictions { category: category }))))
      (tax-amount (/ (* goods-value tax-rate) u10000)) ;; Convert from basis points
    )
    (+ base-fee tax-amount category-fee)
  )
)

(define-public (verify-importer (importer principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
    (match (map-get? importer-profiles { importer: importer })
      profile (ok (map-set importer-profiles
        { importer: importer }
        (merge profile { is-verified: true })
      ))
      ERR-NOT-FOUND
    )
  )
)

;; Read-only Functions
(define-read-only (get-declaration (declaration-id uint))
  (map-get? declarations { declaration-id: declaration-id })
)

(define-read-only (get-officer-info (officer principal))
  (map-get? authorized-officers { officer: officer })
)

(define-read-only (get-importer-profile (importer principal))
  (map-get? importer-profiles { importer: importer })
)

(define-read-only (get-country-info (country (string-ascii 64)))
  (map-get? country-tax-rates { country: country })
)

(define-read-only (get-category-info (category (string-ascii 64)))
  (map-get? category-restrictions { category: category })
)

(define-read-only (get-customs-fee)
  (var-get customs-fee)
)

(define-read-only (get-processing-time)
  (var-get processing-time)
)

(define-read-only (get-next-declaration-id)
  (var-get next-declaration-id)
)

(define-read-only (calculate-fee (goods-value uint) (origin-country (string-ascii 64)) (category (string-ascii 64)))
  (calculate-total-fee goods-value origin-country category)
)

(define-read-only (is-declaration-expired (declaration-id uint))
  (match (map-get? declarations { declaration-id: declaration-id })
    declaration (>= block-height (get expiry-block declaration))
    false
  )
)

(define-read-only (get-declaration-status (declaration-id uint))
  (match (map-get? declarations { declaration-id: declaration-id })
    declaration (some (get status declaration))
    none
  )
)

(define-read-only (can-officer-review (officer principal) (declaration-id uint))
  (match (map-get? authorized-officers { officer: officer })
    officer-data (if (get is-active officer-data)
      (match (map-get? declarations { declaration-id: declaration-id })
        declaration (and (is-eq (get status declaration) STATUS-PENDING)
                        (< block-height (get expiry-block declaration)))
        false
      )
      false
    )
    false
  )
)

;; Emergency Functions
(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
    (as-contract (stx-transfer? amount tx-sender contract-owner))
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
    (ok true)
  )
)