;; charter-dao.clar
;; On-chain organizational governance. Members amend a charter, assign roles,
;; and pass resolutions through a one-member-one-vote motion system.

;; STORAGE

(define-map members
    { addr: principal }
    { display-name: (string-utf8 60), joined-at: uint, active: bool }
)

(define-map charter-sections
    { sec-id: uint }
    { title: (string-utf8 80), body: (string-utf8 500), last-amended: uint, version: uint }
)

(define-map role-assignments
    { role: (string-ascii 30) }
    { holder: principal, assigned-at: uint }
)

(define-map motions
    { mid: uint }
    {
        proposer: principal,
        motion-type: (string-ascii 16),  ;; amend-section | assign-role | admit-member | resolution
        payload-a: (string-utf8 80),     ;; section title | role name   | nominee name  | memo
        payload-b: (string-utf8 500),    ;; section body  | nominee     | principal-str | ""
        ref-id: uint,                    ;; section-id | 0 | 0 | 0
        target-principal: (optional principal),
        yes-votes: uint,
        no-votes: uint,
        deadline: uint,
        status: (string-ascii 10)        ;; open | passed | defeated | applied
    }
)

(define-map ballots
    { mid: uint, voter: principal }
    { yea: bool }
)

(define-data-var member-count uint u0)
(define-data-var motion-nonce uint u0)
(define-data-var bootstrapped bool false)

;; CONSTANTS

(define-constant MOTION-WINDOW       u1008)   ;; ~7 days
(define-constant ERR-NOT-MEMBER      u110)
(define-constant ERR-ALREADY-MEMBER  u111)
(define-constant ERR-BOOTSTRAP-DONE  u112)
(define-constant ERR-NO-MOTION       u113)
(define-constant ERR-MOTION-CLOSED   u114)
(define-constant ERR-ALREADY-VOTED   u115)
(define-constant ERR-DEADLINE-OPEN   u116)
(define-constant ERR-NOT-PASSED      u117)
(define-constant ERR-NO-SECTION      u118)
(define-constant ERR-WRONG-TYPE      u119)
(define-constant ERR-SELF-NOMINATE   u120)
(define-constant ERR-EMPTY-NAME      u121)

;; PRIVATE HELPERS

(define-private (is-active-member (who principal))
    (match (map-get? members { addr: who })
        m (get active m)
        false
    )
)

(define-private (majority (yes uint))
    (> (* yes u2) (var-get member-count))
)

(define-private (open-motion
    (mtype (string-ascii 16))
    (pa (string-utf8 80))
    (pb (string-utf8 500))
    (ref uint)
    (target (optional principal)))

    (let ((mid (+ (var-get motion-nonce) u1)))
        (map-set motions { mid: mid }
            {
                proposer: tx-sender,
                motion-type: mtype,
                payload-a: pa,
                payload-b: pb,
                ref-id: ref,
                target-principal: target,
                yes-votes: u0,
                no-votes: u0,
                deadline: (+ block-height MOTION-WINDOW),
                status: "open"
            }
        )
        (var-set motion-nonce mid)
        mid
    )
)

;; BOOTSTRAP

;; One-time founding member self-registration when no members exist
(define-public (bootstrap (name (string-utf8 60)))
    (begin
        (asserts! (not (var-get bootstrapped)) (err ERR-BOOTSTRAP-DONE))
        (asserts! (> (len name) u0) (err ERR-EMPTY-NAME))

        (map-set members { addr: tx-sender }
            { display-name: name, joined-at: block-height, active: true }
        )
        (var-set member-count u1)
        (var-set bootstrapped true)
        (ok true)
    )
)

;; Founding member writes initial charter sections before governance begins
(define-public (add-section (sec-id uint) (title (string-utf8 80)) (body (string-utf8 500)))
    (begin
        (asserts! (is-active-member tx-sender) (err ERR-NOT-MEMBER))
        (asserts! (is-none (map-get? charter-sections { sec-id: sec-id })) (err ERR-NO-SECTION))
        (asserts! (> (len title) u0) (err ERR-EMPTY-NAME))

        (map-set charter-sections { sec-id: sec-id }
            { title: title, body: body, last-amended: block-height, version: u1 }
        )
        (ok true)
    )
)

;; MOTION PROPOSALS

(define-public (propose-amendment (sec-id uint) (new-title (string-utf8 80)) (new-body (string-utf8 500)))
    (begin
        (asserts! (is-active-member tx-sender) (err ERR-NOT-MEMBER))
        (asserts! (is-some (map-get? charter-sections { sec-id: sec-id })) (err ERR-NO-SECTION))
        (ok (open-motion "amend-section" new-title new-body sec-id none))
    )
)

(define-public (propose-role-assignment (role (string-ascii 30)) (nominee principal))
    (begin
        (asserts! (is-active-member tx-sender) (err ERR-NOT-MEMBER))
        (asserts! (is-active-member nominee) (err ERR-NOT-MEMBER))
        (ok (open-motion "assign-role" u"" u"" u0 (some nominee)))
    )
)

(define-public (nominate-member (nominee principal) (nominee-name (string-utf8 60)))
    (begin
        (asserts! (is-active-member tx-sender) (err ERR-NOT-MEMBER))
        (asserts! (not (is-eq tx-sender nominee)) (err ERR-SELF-NOMINATE))
        (asserts! (is-none (map-get? members { addr: nominee })) (err ERR-ALREADY-MEMBER))
        (asserts! (> (len nominee-name) u0) (err ERR-EMPTY-NAME))
        (ok (open-motion "admit-member" nominee-name u"" u0 (some nominee)))
    )
)

(define-public (propose-resolution (memo (string-utf8 80)))
    (begin
        (asserts! (is-active-member tx-sender) (err ERR-NOT-MEMBER))
        (ok (open-motion "resolution" memo u"" u0 none))
    )
)

;; VOTING AND FINALIZATION

(define-public (cast-ballot (mid uint) (yea bool))
    (begin
        (asserts! (is-active-member tx-sender) (err ERR-NOT-MEMBER))
        (asserts! (is-none (map-get? ballots { mid: mid, voter: tx-sender })) (err ERR-ALREADY-VOTED))

        (let ((motion (unwrap! (map-get? motions { mid: mid }) (err ERR-NO-MOTION))))
            (asserts! (is-eq (get status motion) "open") (err ERR-MOTION-CLOSED))
            (asserts! (< block-height (get deadline motion)) (err ERR-MOTION-CLOSED))

            (map-set ballots { mid: mid, voter: tx-sender } { yea: yea })
            (map-set motions { mid: mid }
                (merge motion {
                    yes-votes: (if yea (+ (get yes-votes motion) u1) (get yes-votes motion)),
                    no-votes:  (if yea (get no-votes motion) (+ (get no-votes motion) u1))
                })
            )
            (ok true)
        )
    )
)

;; Any member can finalize after deadline
(define-public (close-motion (mid uint))
    (begin
        (asserts! (is-active-member tx-sender) (err ERR-NOT-MEMBER))

        (let ((motion (unwrap! (map-get? motions { mid: mid }) (err ERR-NO-MOTION))))
            (asserts! (is-eq (get status motion) "open") (err ERR-MOTION-CLOSED))
            (asserts! (>= block-height (get deadline motion)) (err ERR-DEADLINE-OPEN))

            (let ((new-status (if (majority (get yes-votes motion)) "passed" "defeated")))
                (map-set motions { mid: mid } (merge motion { status: new-status }))
                (ok new-status)
            )
        )
    )
)

;; READ-ONLY

(define-read-only (get-section (sec-id uint))
    (match (map-get? charter-sections { sec-id: sec-id }) s (ok s) (err ERR-NO-SECTION))
)

(define-read-only (get-motion (mid uint))
    (match (map-get? motions { mid: mid }) m (ok m) (err ERR-NO-MOTION))
)

(define-read-only (get-member (who principal))
    (match (map-get? members { addr: who }) m (ok m) (err ERR-NOT-MEMBER))
)

(define-read-only (get-role (role (string-ascii 30)))
    (map-get? role-assignments { role: role })
)

(define-read-only (get-member-count)
    (var-get member-count)
)