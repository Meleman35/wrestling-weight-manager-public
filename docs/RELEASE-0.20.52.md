# Wrestling Manager 0.20.52

The 0.20.51 live page contained the new Members feature but retained `Build v0.20.49` in the account menu. This release corrects the displayed label and adds a source check requiring it to match the release header.

Organization administrators can choose **Board Room → People → Positions → Invite to this position** on an active, vacant adult position. The same action appears while editing a saved vacant position. Unsaved edits require explicit discard before leaving the editor.

The action reloads invitation context from the existing server endpoint and opens the leadership form with the saved position selected. Access remains Title only until the administrator explicitly selects otherwise; adult and permission confirmations remain required. A position that is no longer available produces an error, without falling back to another position or administrator access. Back and Cancel return to positions.

Ordinary membership stays in People → Members. No invitation, membership, position assignment, database migration, backend deployment, subscription or native package is created by this release.

The structure embed helper now writes updated modules on subsequent builds, as well as on its original insertion. Source checks verify both embedded modules and all 46 inline scripts.

Validation: ten DOM interaction scenarios using the actual invitation and structure modules with synthetic RPC/email transport; nine source checks including version consistency and preservation of native/security blocks. Chromium could not be downloaded in this environment, so no real browser/device or delivered-email result is claimed. Real iPhone and recipient acceptance checks remain necessary.

Commands:

```sh
python scripts/embed-structure.py
python scripts/build-organization-invitations-045.py
python tests/organization-invitations-source.py
NODE_PATH=/tmp/wm-dom-qa/node_modules node tests/organization-position-invitations.cjs
```

The isolated DOM harness uses jsdom 26.1.0 installed outside the application; it adds no runtime application dependency.
