# Notes for AI coding assistants

## Nerd Font icons are invisible to you. Don't rewrite files that contain them.

Many files here contain Nerd Font icons: private-use Unicode characters. When
you read such a file the icon shows up as a gap, and if you then rewrite the
file, re-type a block that contains one, or move code between files, the icon
is silently deleted. There's no error; the label just loses its icon. This
already broke the rofi menu icons twice (Aug 7 and Aug 31).

Rules:

- Change these files with `Edit`, using ASCII-only `old_string` anchors, and
  never include a line that contains an icon in `old_string`. `Edit` preserves
  the bytes around your change; `Write` and any copy-by-retyping do not.
- Don't paste an icon into a file. Icons for the rofi menus are defined by
  codepoint in `home/icons.nix`; use `@icon:<name>@` in `home/rofi/scripts/*.sh`
  or `${icons.<name>}` inside Nix strings. To add one, add its codepoint there.
- Files that still contain raw icons (edit with the rules above, and don't
  refactor or move them without asking): `home/waybar.nix`,
  `home/fastfetch.nix`, `home/zsh.nix`, `home/waybar/privacy-dots.sh`,
  `home/quickshell/sysPanel/*.qml`.
- To see whether a file has any, since you can't tell by looking:

  ```
  LC_ALL=C grep -c -P '\xee[\x80-\xbf][\x80-\xbf]|\xef[\x80-\xa3][\x80-\xbf]|\xf3[\xb0-\xbf][\x80-\xbf][\x80-\xbf]' <file>
  ```

## Keep documentation small. Docs are reference, not a changelog.

Earlier sessions turned several docs into session-by-session changelogs
(STATUS.md reached 1400 lines, the Miracast README 850) that cost every later
agent tokens and buried the facts that matter. Rules:

- Git history is the changelog. Don't write "this session I...", dated
  update blocks, "fixed X" narratives, or commit hashes into docs.
- Keep only what a future agent can't get from the code: non-obvious
  constraints, gotchas that already cost real debugging time (with the
  cause, in a sentence or two), design decisions the user made on purpose
  ("don't re-add X"), external contracts, recovery steps, and open items.
- Don't document what the code or its comments already say, resolved
  investigations, disproved theories, or step-by-step debugging stories.
- Update in place: when something changes, edit or delete the old entry.
  Never stack a new section on top of a superseded one. Delete open items
  once done.
- Don't create a new .md file for a feature. Add a short section to the
  nearest existing doc, or put it in a code comment. A doc over ~250 lines
  is a smell: trim it before adding to it.
- One reader in mind: an agent with zero history who needs to change this
  area safely. If an entry wouldn't change what they do, leave it out.
