# Review owner questions (one-off)

A one-off task: go through a batch of issues that wait on a decision, settle each
one that the principles or the decision register answer, and list the rest for
the owner. It is not part of the 30-minute check.

Sources, in the operator repository (the one SKILL.md calls "the operator
repository"; for example `roundtable-k8s/roundtable`):

- `docs/principles.md`: the principles.
- `docs/decisions.md`: the decision register.

Read both with `gh api repos/<operator repo>/contents/docs/<file>` (the
file content is base64 in `.content`) and read each one once per task.

## Procedure

1. **Input.** A list of issue numbers, or a label (`needs-human` or
   `product-direction`, see `project/github-pm`) from the task. List the open
   issues with that label, or fetch the given numbers, and note each title.
2. **Read the sources once.** Load the principles and the register, then split the
   issues into small groups. When the runtime has subagents, give each group to
   one subagent with the sources' text and the rules in this file; otherwise work
   through the groups in turn.
3. **Per issue.** State the question in one sentence. Find the principle or
   register entry that settles it, and decide only when one does. If none does,
   leave the issue.
4. **Act.** For a decided issue, post the decision comment from SKILL.md step 5:

   ```
   Decided <YYYY-MM-DD> (orchestrator): <the decision>.
   Why: <which principle or register entry, and how it applies>.
   ```

   Remove the hold label (`needs-human`, `product-direction`, `parked` or `hold`)
   only when the decision leaves no human step. File any follow-up issues in the
   issue format (`reference/issue-format.md`) and queue them as SKILL.md step 4
   describes. For a left issue, change nothing on it.
5. **Never decide** product-direction or taste questions (what the product is for,
   what to build next, naming, look and feel), security or credential questions,
   deletions, or approval gates. Also leave anything the principles and register
   do not settle. For each left issue, write one sentence on why it is the
   owner's.
6. **Report.** Final message: a table with columns issue, decision or "left", and
   the principle or entry used (or the reason for leaving it). Then a list of
   what is for the owner. Send the owner list with
   `bash $S/alert "<repo>#<n>: <question> — needs the owner"` when the batch has
   such items.

## Limits

The limits in SKILL.md apply unchanged: no credentials, no permissions, no
deleting data or repositories, no approval gates, no rewording someone else's
issue to get it past pickup, and no AI attribution in comments.
