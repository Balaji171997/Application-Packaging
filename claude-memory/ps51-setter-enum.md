---
name: ps51-setter-enum
description: "New-Object Windows.Setter (prop, enumValue) mis-binds enum values in PowerShell 5.1; use explicit .Property/.Value"
metadata: 
  node_type: memory
  type: reference
  originSessionId: f4fc59ce-bb2a-4ffe-b080-0f251cb9e612
---

In Windows PowerShell 5.1, building a WPF `Style` Setter with an ENUM value via the constructor form
`New-Object Windows.Setter ([X]::SomeProperty), [Windows.SomeEnum]::Value` stores the value as the
literal expression STRING, so applying the style throws e.g. "'[Windows.HorizontalAlignment]::Center'
is not a valid value for the ... property on a Setter." (Brush/Thickness OBJECT values via the same
constructor work fine — only enums break.)

**Use instead** — assign the Setter's members explicitly:
```
$s = New-Object Windows.Setter
$s.Property = [Windows.Controls.TextBlock]::TextWrappingProperty
$s.Value    = [Windows.TextWrapping]::Wrap
$style.Setters.Add($s)
```
Found while building the MST plan dialog in Package Builder (GUI.ps1). Verified via offscreen
RenderTargetBitmap, which is the project's way to catch WPF construction/binding errors without showing a window. See [[ps51-list-object-wrap]].
