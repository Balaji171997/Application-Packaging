---
name: audi-ppt-template-facts
description: "Facts about the user's \"Package Builder.pptx\" deck template - VW Group 2023 theme colours, fonts and which layouts to use"
metadata: 
  node_type: memory
  type: reference
  originSessionId: fd7b3460-9b55-454d-8890-76d54ccc8d20
  modified: 2026-07-30T15:46:19.149Z
---

The user's house deck template is `C:\temp\Package Builder.pptx`. When asked for a PPT "using my
template", copy it, keep `theme/` + `slideMasters/` + `slideLayouts/` + `media/` untouched, and
replace only `ppt/slides/`.

- 16:9, `12192000 x 6858000` EMU. Theme name **"Volkswagen Group 2023"**.
- Colours: `dk2`/`accent1` `#002733`, `accent2` `#008C82`, `accent3` `#99D1CD`,
  `accent4` `#809399`, `accent5` `#CCD3D6`, `accent6` `#4C6870`.
- Fonts: **The Group HEAD Light** (major/`+mj-lt`), **The Group TEXT** (minor/`+mn-lt`).
- 67 layouts. Useful ones: `slideLayout8` = "1_Title slide_Dark", `slideLayout35` =
  "Title, action title and text_Dark" (title + one-line takeaway + body — the workhorse),
  `slideLayout20` = "1_Agenda_Dark", `slideLayout60` = "Final slide_Dark".
- **Dark layouts carry `overrideClrMapping tx1="lt1"`**, so on those slides `tx1` resolves to
  white. Reference theme colour *slots* (`schemeClr`), never literal hex, so branding stays
  uniform if they retheme.
- Master geometry: title at `y=644520`, action title at `y=1056085`, body at `y=1844675`
  `cx=11380788`. Footer/date/slide-number sit at `y~6579000`.

Build with hand-written OOXML + PowerShell zip ([[docx-no-node-python]]). Verify by rendering:
PowerPoint COM `$pres.Slides.Item($i).Export($png,'PNG',1600,900)` — opening without a repair
prompt plus a visual check catches layout bugs that XML validation cannot.
