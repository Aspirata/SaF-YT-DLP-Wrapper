# Codec-Aware Bitrate Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace fixed-quality video transcoding with predictable codec- and resolution-aware target bitrates.

**Architecture:** Probe the source video stream bitrate and height with FFprobe, map the source/target codec pair and resolution to a conservative integer percentage, then add a 10% generation-loss margin. Software encoders use two-pass average-bitrate encoding; hardware encoders use one-pass VBR with an additional 10% margin and retain CPU fallback.

**Tech Stack:** Windows CMD, PowerShell test harness, FFmpeg/FFprobe.

**Spec:** `docs/superpowers/plans/2026-09-18-codec-bitrate-policy.md` (the Goal, Architecture, and Global Constraints below are the approved specification).

## Global Constraints

- Use only the source video stream bitrate, excluding audio and container overhead.
- Resolution bands are `<=720`, `721-1080`, and `>=1081` pixels high.
- Apply a 10% generation-loss margin to every video transcode.
- Apply another 10% margin when a hardware encoder is selected.
- Preserve stream-copy behavior and CPU fallback.
- Keep all program text and documentation in English.

---

### Task 1: Probe and calculate the software bitrate target

**Files:**
- Modify: `tests/FakeFfmpeg.cs`
- Modify: `tests/run-tests.ps1`
- Modify: `SaF-YTDLP.cmd`

**Interfaces:**
- Consumes: source path, source codec, target codec.
- Produces: `TARGET_VIDEO_BITRATE`, `MAX_VIDEO_BITRATE`, and `VIDEO_BUFFER_SIZE` in kbit/s.

- [x] Add failing integration tests with literal expected bitrate arguments for VP9 to AV1 at 1080p and AV1 to H.264 at 1080p.
- [x] Run `powershell -ExecutionPolicy Bypass -File tests/run-tests.ps1` and confirm those tests fail because bitrate arguments are absent.
- [x] Add FFprobe stream probing and the codec/resolution coefficient table.
- [x] Run the full test suite and confirm the new calculations pass.

### Task 2: Use VBR and preserve fallback behavior

**Files:**
- Modify: `tests/run-tests.ps1`
- Modify: `SaF-YTDLP.cmd`

**Interfaces:**
- Consumes: bitrate values from Task 1 and the selected encoder.
- Produces: two-pass software encoding and one-pass hardware VBR arguments.

- [x] Add failing tests for two-pass software encoding, hardware margin, and CPU fallback recalculation.
- [x] Run the full tests and confirm the new assertions fail for the expected missing behavior.
- [x] Implement two-pass software encoding and hardware VBR arguments.
- [x] Run the full test suite and confirm it passes.

### Task 3: Documentation and final verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: completed runtime behavior.
- Produces: user-facing explanation of the bitrate policy.

- [x] Replace the old CRF/CQ documentation with the coefficient table and margins.
- [x] Run the full automated suite.
- [x] Run real local FFmpeg smoke tests for bitrate-controlled Unicode-path AV1, H.265, and H.264 transcoding.
- [x] Review the final diff and report verification results.
