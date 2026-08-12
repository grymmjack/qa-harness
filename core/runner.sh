#!/usr/bin/env bash
# core/runner.sh — the portable runner. Owns logging/tally, the region registry,
# region-diff assertions (see core/assert.sh), ETA, live status, per-run results
# + report, run isolation/cache, run modes/consent, and the CLI. Knows nothing
# about any app or OS — it calls driver_* verbs and adapter_* facts.
#
# SKELETON: the bodies port near-verbatim from DRAW/QA/draw-qa.sh (that script is
# the reference; ARCHITECTURE.md has the per-symbol port checklist). This file
# currently defines the entry point and the shape so bin/qa wires end-to-end.

# core/assert.sh lives beside this file.
# shellcheck source=/dev/null
[[ -f "${QA_HARNESS_ROOT:-.}/core/assert.sh" ]] && source "${QA_HARNESS_ROOT}/core/assert.sh"

# qa_main <core flags…> <tests…> — the port target. Responsibilities, in order:
#   1. parse flags (--list/--eta/--report/--status/--mode/--rerun-passed/…)
#   2. resolve run mode; self-wrap under driver_run_offscreen when offscreen
#   3. collect tests from args (glob) or the adapter's ADAPTER_TESTS_DIR
#   4. print ETA (per-test median + session total + finish clock time)
#   5. for each test: write live status → adapter_launch → source test →
#      crash check → adapter_quit → record duration + result
#   6. write report.html + junit.xml (via $QA_REPORT_PY), exit non-zero on fail
qa_main() {
    echo "qa-harness: core runner is a skeleton — port the body from DRAW/QA/draw-qa.sh." >&2
    echo "  adapter : ${ADAPTER_NAME:-<unset>}   tests dir: ${ADAPTER_TESTS_DIR:-<unset>}" >&2
    echo "  driver  : input/capture/target verbs loaded = $(command -v driver_capture_full >/dev/null && echo yes || echo NO)" >&2
    echo "  report  : ${QA_REPORT_PY:-<unset>}" >&2
    return 3
}
