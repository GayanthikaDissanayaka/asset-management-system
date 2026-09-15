# Saved reports

Reports written here by the **Reports** page in the application
(`/reports` → *Save to project folder*), or by the API endpoint
`POST /api/network/reports/save`.

## Why this folder exists

The download buttons elsewhere in the app build a file, hand it to the
browser and keep nothing. That is right for *"let me look at this now"*.

It cannot answer *"what did the register say at the end of last month"* —
the register has moved on since, and that figure only exists if somebody
wrote it down at the time. Each file here is a snapshot of the register
at the moment it was built.

## Filenames

    uva-<report>-<YYYY-MM-DD-HHMMSS>[-<label>].xlsx

The time is part of the name because two reports built on the same day
are different documents. The optional label comes from the field on the
Reports page.

## A decision for you: commit these or not?

They are deliberately **not** in `.gitignore`, so `git status` will show
them and you can decide.

- **Commit them** if these snapshots are records the province needs to
  keep — an audit trail of what was reported and when.
- **Ignore them** if they are working files you regenerate at will. Add
  `/reports/*.xlsx` to the root `.gitignore`.

They are Excel binaries, so committing many of them will grow the
repository steadily. Either answer is reasonable; drifting into one by
accident is not.
