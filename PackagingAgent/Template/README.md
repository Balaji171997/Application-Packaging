# Template - the PSADT template the agent builds from

`Content\` is the team's PSADT v4 template: the toolkit, the team's own extensions
(`PSAppDeployToolkit.Extensions` - `Set-MTBReboot`, `Set-MTBDetectionKey`, `Remove-MTBFonts`,
`Expand-MTBZipFile` and the rest), plus `Config\`, `Assets\` and `Strings\`.

**This is the MTB template.** Copied from `MTB-PackageAssistance\Lib\PSADT_Template\Content`
on 26 Sep 2026 - 221 files, ~20 MB.

## Why it lives here

The agent used to look for a template by searching the folders sitting next to it for a Package
Assistance copy. That made it depend on whatever happened to be beside it, and with MTB, GPF and PAG
variants all present it silently took the first one it found - so a GPF order could be built with the
MTB template and nobody would know until after handover. The agent carries its own template now and
searches nowhere else.

## The rule that has not changed

**The template is fixed.** The agent generates a package FROM it and never rewrites or restyles it -
only the code the tool injects into the marked sections changes. If a finding needs the template
itself altered, that is a person's decision, not the agent's.

## Using a different brand's template

Set `TemplatePath` in `engine-settings.json` to that template's `Content` folder. An explicit setting
wins over this copy, so switching brands is deliberate and visible rather than accidental. Whichever
one is used, the agent logs it once at build time.

## Keeping it current

There is no sync. When the team's template changes, copy the new `Content` over this one - the same
trade the `Engine\` folder makes: independence over automatic updates.
