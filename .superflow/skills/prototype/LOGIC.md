# Logic Prototype
A tiny interactive terminal app that lets the user drive a state model by hand.

## 1. State the question
Before writing code, write down the state model and the question being prototyped — one paragraph, top-of-file comment or README.

## 2. Pick the language
Whatever the host project uses; match its existing tooling — no new package manager or runtime for the prototype. No obvious runtime → ask.

## 3. Logic in a pure module
Put the logic in a pure module (reducer, state machine or functions — whatever fits the question; a state machine when "which actions are legal right now" is part of the question). No I/O, no terminal code, no logging for control flow. The TUI calls it; never the reverse, so the module can be lifted into the real code.

## 4. Build the smallest TUI that exposes the state
A **lightweight TUI** over one in-memory state object: render the first frame, then read one keystroke (or line) at a time, map it to an action and call the logic module (terminal keys never reach the logic), then clear the screen and re-render the whole frame — one stable view, never growing scrollback — until quit. The frame fits one screen: the **current state**, pretty-printed and diff-friendly (one field per line, or formatted JSON; no styling library unless the project already has one), then the keyboard shortcuts at the bottom.

## 5. Hand it over
Add the run script to the project's existing task runner (`package.json` scripts, `Makefile`, `justfile`) — no task runner → put the command at the top of the README. Give the user the run command; they drive it, and new actions get added as they ask for them.
