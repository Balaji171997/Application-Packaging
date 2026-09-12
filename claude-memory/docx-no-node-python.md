---
name: docx-no-node-python
description: This machine has no Node or real Python; build Office docs via hand-written OOXML + PowerShell zip
metadata: 
  node_type: memory
  type: reference
  originSessionId: 9821670a-d587-4d70-8e9a-15b6c36657a1
---

On this machine **neither Node/npm nor a real Python is installed** — `python`/`python3` resolve only to the Windows Store stub (`...\WindowsApps\python.exe`) which errors. So the docx/pptx/xlsx skills' helper scripts (docx-js, python-docx) **cannot run**.

**How to apply:** To produce a `.docx` (or pptx/xlsx), generate the OOXML XML by hand and package it with PowerShell using `System.IO.Compression.ZipArchive` (create entries with forward-slash names, UTF-8 no BOM). Validate each part by loading it as `[xml]` from the zip. A working generator pattern (markdown-ish parser → WordprocessingML with styles.xml, numbering.xml, settings.xml, footer, TOC field) lives in this session's scratchpad `build-doc.ps1`. Output went to `C:\Users\AW140\Downloads\files\`.
