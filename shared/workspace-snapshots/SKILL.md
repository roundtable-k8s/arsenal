---
name: workspace-snapshots
description: Take a snapshot of a knight's workspace and check that a fresh, ready snapshot exists, using the gateway's list_knight_snapshots and snapshot_knight tools. Use before a risky mission or change to confirm a restore point exists, or when asked whether a knight has a recent backup.
allowed-tools: Bash(bash:*) Read
metadata:
  author: roundtable
  version: "1.0"
---

# Workspace snapshots

A knight's workspace (`/data`) is a PVC. The operator can take a `VolumeSnapshot` of it, which is a restore point. The gateway tools list those snapshots and ask for a new one. The check script only reads a saved reply: it calls no gateway and needs no credentials.

## When to Use

- Before a risky mission or a large change to a knight's files: confirm a recent ready snapshot exists, or take one first.
- "Does galahad have a backup from today?"
- Reading why a snapshot is not being taken (the condition and pending snapshots).

Restoring a snapshot, deleting snapshots and setting snapshot schedules are not MCP tools. Restoring means a new knight with `spec.workspace.fromSnapshot` (see `docs/workspace-snapshots.md` in roundtable-k8s/roundtable); do not attempt it from here.

## Tools

| Tool | Use |
|------|-----|
| `list_knight_snapshots` | The knight's snapshots, oldest first, and its condition. Args: `name`, optional `namespace`. |
| `snapshot_knight` | Ask for a new snapshot. Args: `name`, optional `namespace`, optional `waitSeconds` (waits until the snapshot is ready). |

The list reply: `{knight, namespace, lastSnapshotRequest, snapshots: [{name, createdAt, readyToUse}], condition: {status, reason, message}}`. Only a snapshot with `readyToUse: true` can be restored.

The snapshot reply: `{request, expectedName, note?, ready?, snapshot?, condition?}`. The expected name is `<knight>-ws-<unix seconds>` by the operator's clock and can differ by a second from what appears in the list, so confirm with the list rather than trusting `expectedName`.

## Steps: check for a fresh snapshot

1. `D=$(mktemp -d)`.
2. Call `list_knight_snapshots` with the knight's `name` and save the reply as `$D/snapshots.json`.
3. Run the script with the age you need, in seconds (for example 86400 for one day):

```bash
bash /skills/shared/workspace-snapshots/scripts/check --list $D/snapshots.json --max-age 86400
```

4. Read the output and say in your own words whether the knight can be restored from a recent point and what is pending or wrong. Exit codes: 0 a ready snapshot younger than max-age exists; 1 none does; 2 bad input, fix it rather than guess.

## Steps: take a snapshot before risky work

1. Call `snapshot_knight` with `name`. Use `waitSeconds` (for example 120) to wait for it to be ready; without it the reply returns at once with `ready` unset.
2. If the reply has `note` saying the knight is suspended, the snapshot is taken on resume. Tell the owner; do not resume the knight to get it.
3. Run the list check again (steps above) with a small `--max-age` such as 300 and confirm a ready snapshot is there. The list is authoritative, not `expectedName`.

## Failure answers

- `409` (a second request in the same second): wait a few seconds and call `snapshot_knight` again.
- `422` (workspace is ephemeral): the knight has no PVC, so no snapshot can be taken. Say so; do not change the knight's workspace.
- Condition `False` / `SnapshotAPIUnavailable`: the cluster has no VolumeSnapshot API. Report it; no restart fixes it.
- Condition `False` / `SnapshotFailed`: the message has the error. Quote it.
- Condition `False` / `WorkspaceNotPersistent`: same as the 422 case.
- Snapshot listed but `readyToUse` false: still being cut. Check again later; do not treat it as a backup.

## Rules

- Do not take snapshots of a knight you were not asked about. A snapshot costs storage until `keep` prunes it.
- Never delete snapshots from here; deletion happens through retention.
- Do not count snapshots yourself when the script has printed the answer.
- A snapshot is not a backup of anything outside the knight's workspace.

## Dependencies

- `jq` and coreutils (`date`). Both ship in the knight image.
