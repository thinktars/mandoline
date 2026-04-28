# Backup Verification Plan (Reconsidered)

## Goal
Add a **pre-delete safety check** to Mandoline so users can verify that iPhone media exported with macOS Image Capture exists on an external drive **before** removing anything from the phone.

This document is intentionally planning-only. No implementation is included yet.

---

## Decision Summary

### Is this feasible?
**Yes, technically feasible** on macOS using Apple’s `ImageCaptureCore` framework.

- Mandoline can enumerate iPhone media metadata (name, byte size, date, unique IDs where available) without importing full media.
- Mandoline can scan the destination folder on external storage and compare inventories.
- This can run as a standalone “verification mode” before normal triage.

### Is this secure?
**Yes, if implemented with strict local-only principles and least privilege.**

- No cloud service is required.
- No media content upload is required.
- Comparison can be done from metadata only.
- Data retention can be minimized to transient, in-memory structures unless user asks to save reports.

---

## Revised Architecture (Safety-First)

## 1) Data Sources
1. **Device inventory (iPhone)**
   - Source: `ImageCaptureCore` (`ICDeviceBrowser`, `ICCameraDevice`, `ICCameraFile`).
   - Fields to collect: filename, fileSize, creationDate, optional UTI/extension, optional persistent identifiers exposed by API.

2. **Backup inventory (external drive folder)**
   - Source: recursive filesystem scan.
   - Fields: filename, fileSize, creationDate, relative path, hash (optional only for disputed matches).

## 2) Matching Strategy (Confidence Tiers)
Use multi-stage matching rather than filename-only:

- **Tier 1 (High confidence):** stable device ID ↔ exported file metadata match.
- **Tier 2 (Strong):** filename + exact fileSize + close creationDate.
- **Tier 3 (Needs review):** filename-only or size-only partial matches.

Result classes:
- `Matched`
- `MissingOnBackup`
- `Ambiguous`
- `ExtraOnBackup`

## 3) Verification Output
Generate an explicit report:
- Total items on phone
- Matched count
- Missing count
- Ambiguous count
- Optional CSV/JSON export for audit trail

No destructive actions are enabled from this screen.

---

## Security & Privacy Review

## Threat model
- **Accidental data loss** due to false “all present” result.
- **Over-privileged app access** in sandboxed environment.
- **Metadata leakage** if logs/reports include sensitive filenames.
- **Tampered or partial backup folder** (copy interrupted, hidden errors).

## Controls
1. **Least privilege entitlements only**
   - Keep app sandbox and user-selected file access.
   - Add only device access needed for Image Capture integration.

2. **Local processing only**
   - No network calls during verification.
   - No analytics payload with media identifiers.

3. **Safe logging defaults**
   - Do not log full filenames by default in production logs.
   - Redact paths in diagnostic logs unless user explicitly opts in.

4. **Conservative UX language**
   - “Verification passed with X confidence” (never “guaranteed”).
   - If ambiguity > 0, block “safe to delete” badge and prompt manual review.

5. **Optional deep verification mode**
   - Hash-based verification for ambiguous/missing candidates only.
   - Avoid full-library hashing by default for speed and SSD wear.

---

## Feasibility Risks and Mitigations

## Risk 1: iPhone metadata inconsistencies
- Some exports may alter names (e.g., duplicate suffixing) or date fields.
- **Mitigation:** tiered matching + ambiguity bucket + optional hash pass.

## Risk 2: Very large libraries (performance)
- 50k+ items can stress memory if naive.
- **Mitigation:** streaming scan + chunked comparison + progress reporting.

## Risk 3: External drive behavior
- Slow I/O, disconnects, transient read failures.
- **Mitigation:** resumable scan state + robust error classification + retry.

## Risk 4: User misunderstanding of “verified”
- Users may assume absolute certainty.
- **Mitigation:** confidence scoring and explicit caveats in UI copy.

---

## Proposed Non-Implementation Deliverables (Now)
Since we are pausing implementation, the immediate outputs should be:

1. **Technical design spec** (this doc).
2. **API spike checklist** for `ImageCaptureCore` behavior with real devices.
3. **Test matrix** definition (below).
4. **Go/No-Go security checklist** before coding.

---

## Test Matrix to Validate Before Build

1. **Device states**
   - Locked vs unlocked phone
   - Trust prompt accepted/denied
   - iCloud Photos optimize storage on/off

2. **Media diversity**
   - HEIC, JPEG, PNG, MOV, ProRes, Live Photos components
   - Burst photos and edited variants

3. **Scale**
   - 1k / 10k / 50k items

4. **Backup edge cases**
   - Interrupted Image Capture copy
   - Duplicate filenames in different folders
   - External drive disconnect during verification

5. **Correctness gates**
   - Known missing set injected; verifier must detect all
   - Known ambiguous set injected; verifier must not falsely mark as matched

---

## Go/No-Go Criteria (Before Implementation)
Proceed only if all are true:

- `ImageCaptureCore` reliably enumerates required metadata on target macOS + iOS versions.
- Entitlement set is minimal and approved.
- Prototype demonstrates low false-negative/false-positive rate on real datasets.
- UX copy clearly communicates confidence and limitations.
- No network egress in verification path.

---

## Recommendation
**Proceed with this approach later**, but only after a small prototype and security gate review.

This is the most native and user-aligned path for Mandoline’s mission:
- keep what matters,
- confidently verify backup completeness first,
- then free phone storage without avoidable loss.

