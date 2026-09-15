---
name: ps51-collection-and-path-traps
description: "PS 5.1 traps found the hard way - empty collection is falsy, if-assignment unrolls a 1-element array, [] in a positional path, GetNewClosure hides functions"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 17ecde68-9c5a-4b15-9bb0-b493baf39602
  modified: 2026-08-13T13:53:38.041Z
---

Four PS 5.1 traps that all produced *silent* wrong behaviour (no error) in WPF tool code:

1. **An empty collection is falsy.** `if ($sync.LogQueue) { $sync.LogQueue.Add(...) }` never runs,
   because the queue is empty exactly when the first item would arrive. Use `$null -ne $x`.
2b. **A function RETURNING a collection unrolls it too.** `return $rows` (an ObservableCollection)
   hands the caller a SINGLE object when it holds one item — binding that to
   `DataGrid.ItemsSource` throws *"Cannot convert the X value ... to type
   System.Collections.IEnumerable"*. Two or more items survive by accident, so this only shows up
   in the one-item case. Fix: `return ,$rows`. Then callers must NOT wrap the call in `@()` —
   `@(cmd)` around a comma-protected return gives an array *holding* the collection.
2. **Assigning from an `if` unrolls a one-element array.** `$items = if ($q) { @(...) } else {...}`
   yields a scalar when the branch produced one item — assigning that to `.ItemsSource` throws
   "cannot convert ... to IEnumerable". Wrap the WHOLE expression: `$items = @(if (...) {...})`.
3. **`[` `]` in a POSITIONAL path picks a different parameter set.** `Set-Content (path with [])
   -Encoding UTF8` → "A parameter cannot be found that matches parameter name 'Encoding'".
   Use `-LiteralPath`. Also: `New-Item` has NO `-LiteralPath` in 5.1, so strip `[]` from any name
   used to build a folder path.
4. **`.GetNewClosure()` on a WPF event handler hides the script's FUNCTIONS.** The closure runs in
   its own module scope: captured *variables* work, but `Connect-X` / `Add-UiLog` defined in the
   script are "not recognized" at click time. Register handlers as PLAIN scriptblocks and share
   state through one hashtable (see [[ps-wpf-closure-scope]]). Bitten AGAIN 2026-09-12 in Package
   Companion's review popup (`Set-ReviewAck` not recognized from a checkbox closure). For a MODAL
   dialog a plain handler is enough: the dialog function's locals stay reachable dynamically while
   `ShowDialog` blocks. A driver that fires the real Click via `RaiseEvent` catches this class in
   seconds - a `Get-Command X` guard inside a closure silently HIDES it instead.
4b. **`[Windows.TextDecorations]::Strikethrough` unrolls** to a bare `TextDecoration` in PS 5.1 -
   assigning it to `.TextDecorations` throws "cannot convert". Build a `TextDecorationCollection`.

Two more that cost real debugging time:

5. **A simple `function` (no `[CmdletBinding()]`) SWALLOWS unknown named arguments into `$args`.**
   Adding `-PackageName x` to a call whose param block was never updated does NOT error - the
   parameter is just silently `$null` inside. Symptom looked like a logic bug, not a typo.
6. **Variable names are case-INSENSITIVE**, so `$state = ...` overwrites `$State`. Trivially easy
   to do inside a WPF handler where `$State` is the shared hashtable everything runs on.

7. **Dispatcher.Invoke/BeginInvoke: the PRIORITY goes FIRST.** `BeginInvoke([action]{...},
   'Background')` binds to the `(Delegate, params object[])` overload and passes `'Background'` to
   a zero-parameter action → **"Parameter count mismatch"**, which surfaces as
   `ShowDialog` throwing and the whole window closing. Use
   `BeginInvoke([DispatcherPriority]::Background, [action]{...})`.

Also: a `.docx` zip entry may be stored as `word\document.xml` (backslash) rather than
`word/document.xml` — match either or the read silently returns nothing.

All of these were caught by tests that drove the real handlers, not by reading the code.

**WPF-in-PowerShell has no compiler.** `$UI` is a plain hashtable, so a control removed from the
XAML but still referenced in code is silently `$null` and only dies at the click with "The
property 'X' cannot be found on this object" — surfacing as `ShowDialog` throwing and the window
vanishing. Two cheap guards catch the whole class:
- a STATIC text check cross-referencing `$UI.<Name>` / `$UI['<Name>']` against `Name="..."` in the
  XAML and against the FindName list (no window, no STA needed), and
- a test that CALLS every UI helper (Set-UiBusy, Set-UiConnected, Update-UiCount, Add-UiLog) —
  helpers are where stale references hide because nothing else touches those controls.
Always verify such a guard by reintroducing the bug and watching it fail.
