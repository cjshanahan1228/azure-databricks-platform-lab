# Runbook: how deploy and destroy share the lab

Only one operation may touch the lab at a time, so `deploy.yml`'s **apply** job
and `destroy.yml`'s **destroy** job share the concurrency group `lab-env`.

## The problem this avoids

GitHub allows one *running* and, by default, one *pending* job per concurrency
group. A newly queued job **cancels the existing pending one**
([docs](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)).
A deploy's apply job also waits for the `lab` environment reviewer, and pending
approvals can sit for up to 30 days. With workflow-level concurrency (the
first version of this PR), an unapproved deploy would have:

- held `lab-env`, so the nightly destroy queued behind it and never ran, and
- been able to cancel a pending destroy just by being queued after it.

## What the workflows do now

1. **Concurrency is job-level**, only on deploy's `apply` job and destroy's
   `destroy` job. Planning doesn't take the lock.
2. **`queue: max`** on both, so a newer queued run never replaces (cancels) an
   older pending one. In particular, a pending destroy can't be cancelled by a
   later deploy.
3. **`cancel-in-progress: false`** on both: an in-flight apply or destroy is
   never cancelled.
4. **destroy.yml cancels unapproved deploys first.** Its
   `cancel-pending-deploys` job (the only job with `actions: write`) cancels
   every `deploy.yml` run that's `waiting` (for approval), `queued`, `pending`
   or `requested`, then the destroy job takes the lock. A deploy that is
   *actually applying* is left alone; destroy waits for it and then removes
   what it built.

## What this means for you

- If you start a deploy late in the evening and don't approve it, the nightly
  destroy cancels it. Re-run it when you're ready.
- For an interview week, set `LAB_KEEP_ALIVE_UNTIL`. The nightly run then
  skips entirely, so it doesn't cancel anything.
- Manual destroys (type `destroy`) behave the same way: they cancel waiting
  deploys too.
