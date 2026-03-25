# charter-dao

On-chain organizational charter management. Amend rules, elect roles, and ratify decisions through a structured governance process.

---

## Overview

Every organization runs on rules. `charter-dao` stores those rules on-chain as a living document — a charter — and governs amendments through a member vote. Beyond text amendments, the contract manages elected roles (think: President, Treasurer, Secretary) where incumbents are replaced through the same voting mechanism.

The design is inspired by corporate governance and cooperative models, adapted for on-chain execution. Members are admitted by existing members, each holding equal voting weight (one member, one vote).

---

## Governance Primitives

**Charter Sections** — The charter is composed of numbered sections. Each section has a title and body stored on-chain. Amendments replace section content through a ratified vote.

**Roles** — Named positions (e.g. "president", "treasurer") that can be held by one member at a time. Role assignments are made through the same amendment process.

**Resolutions** — General-purpose governance motions that don't change the charter text but are recorded on-chain as ratified decisions.

**Membership** — Members are admitted via a vote. Any current member can nominate; a majority admits.

---

## Architecture

```
members          principal → name, joined-at, active
charter-sections section-id → title, body, last-amended-at, version
role-assignments role-name → holder, assigned-at
motions          motion-id → type, payload, yes, no, status, deadline
ballots          (motion-id, voter) → vote cast
```

Motion types: `amend-section` | `assign-role` | `admit-member` | `resolution`

---

## Function Reference

### Membership

| Function | Description |
|---|---|
| `nominate-member(principal, name)` | Member nominates another for admission |
| `cast-ballot(motion-id, yea)` | Vote on any open motion |
| `close-motion(motion-id)` | Finalize a motion after voting deadline passes |

### Charter Management

| Function | Description |
|---|---|
| `propose-amendment(section-id, new-title, new-body)` | Open amendment vote for a section |
| `propose-role-assignment(role-name, nominee)` | Open election for a role |
| `propose-resolution(memo)` | Create a general on-chain resolution |
| `apply-amendment(motion-id)` | Execute passed amendment after close |
| `get-section(section-id)` | Read current charter text |

### Setup

| Function | Description |
|---|---|
| `bootstrap(name)` | Founding member self-registers (one-time only) |
| `add-section(section-id, title, body)` | Founding member writes initial charter |

---

## Example

```clarity
;; Founding member bootstraps
(contract-call? .charter-dao bootstrap u"Alice")

;; Write initial charter section 1
(contract-call? .charter-dao add-section u1 u"Purpose" u"This DAO exists to...")

;; Propose amendment to section 1
(contract-call? .charter-dao propose-amendment u1
    u"Revised Purpose"
    u"This DAO exists to fund open source development...")

;; Members vote
(contract-call? .charter-dao cast-ballot u1 true)

;; After deadline, close and apply
(contract-call? .charter-dao close-motion u1)
(contract-call? .charter-dao apply-amendment u1)
```

---

## Design Notes

- One member, one vote — no token-weighted governance; this suits cooperatives and small DAOs
- Motion deadline is 1008 blocks (~7 days) — long enough for async participation
- `close-motion` is callable by any member after deadline — no single gatekeeper
- `apply-amendment` is separate from `close-motion` — passage and execution are distinct events
- Founding member is the sole member until new members are admitted via motion

---

## Security Considerations

- `bootstrap` can only be called once and only when the member count is zero
- Members cannot vote on motions that would admit themselves
- Closed motions cannot be re-opened or modified
- Charter section writes are only possible via ratified amendment motions (after bootstrap)
