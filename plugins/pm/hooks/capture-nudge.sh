#!/bin/sh
# capture-nudge — PMCollab uncaptured-change reminder (Stop hook).
#
# Fires when a Claude Code session is about to stop while the working tree
# (or unpushed history) carries changes with no PMCollab change-spec linkage.
# Exit 2 blocks the stop ONCE and hands Claude the reminder text on stderr;
# the stop_hook_active guard guarantees the second stop attempt passes, so
# the nudge can never loop.
#
# Opt-in per repo (default: off) — the rollout default is an open question
# on the Express Mode change spec, so the mechanism ships disabled:
#   git config pmc.captureNudge true
# Disable again with `git config --unset pmc.captureNudge`.

set -u

payload=$(cat 2>/dev/null || true)

# Never re-fire on the stop attempt that follows our own nudge.
case "$payload" in
  *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
esac

# Only inside a git work tree.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Opt-in gate.
[ "$(git config --get pmc.captureNudge 2>/dev/null)" = "true" ] || exit 0

dirty=$(git status --porcelain 2>/dev/null | head -1)

# Unpushed commits missing a Change-Spec trailer (tolerate a missing upstream).
unlinked=""
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  unlinked=$(git log '@{u}..HEAD' --format='%h %(trailers:key=Change-Spec,valueonly)' 2>/dev/null \
    | awk 'NF < 2 { print $1; exit }')
fi

[ -z "$dirty" ] && [ -z "$unlinked" ] && exit 0

{
  echo "PMCollab capture nudge: this repo has changes with no linked change spec."
  [ -n "$dirty" ] && echo "- Uncommitted working-tree changes present."
  [ -n "$unlinked" ] && echo "- Unpushed commit(s) without a 'Change-Spec:' trailer (first: $unlinked)."
  echo "Remind the user ONCE, briefly: they can capture this now via /pm:quick-change (spec drafted from the diff) or /pm:chat-to-spec-review (full review first), or skip — in which case PMCollab will flag the eventual PR as an uncaptured change. Ask which they'd like; if they decline or don't care, drop it and stop. Do not repeat this reminder."
} >&2
exit 2
