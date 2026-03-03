# Gemini File Tools

A set of tools for parsing, viewing, and extracting data from Google Gemini AI Studio conversation files. Written in Delphi (Object Pascal), framework-independent (no VCL/FMX), with zero external dependencies.

Three deliverables share the same core library:

- **GemView** — a command-line application for inspecting and extracting Gemini files
- **Gemini WCX** — a Total Commander packer plugin that presents Gemini files as virtual archives
- **Gemini WLX** — a Total Commander lister plugin that renders Gemini conversations as HTML in an embedded WebView2 control

## Gemini File Format

Google AI Studio exports conversations as extensionless JSON files. Each file may contain:

- Model run settings (model name, temperature, top-p, top-k, safety settings, feature flags)
- System instruction
- A sequence of conversation chunks (user messages, model responses, thinking blocks)
- Base64-encoded embedded resources (images attached or generated during the conversation)
- References to remote Google Drive attachments

Files can range from a few kilobytes to 500+ MB depending on the number of embedded images.

## GemView — Command-Line Application

```
gemview info <file>                Show file metadata and statistics
gemview conversation <file>        Print the conversation text
gemview resources <file>           List embedded resources
gemview extract <file> [options]   Extract embedded resources
gemview help                       Show usage information
```

### Extract Options

| Option            | Description                                               |
|-------------------|-----------------------------------------------------------|
| `--output <dir>`  | Output directory (default: `<filename>_resources`)        |
| `--sequential`    | Single-threaded extraction (default is multi-threaded)    |
| `--prefix <name>` | Filename prefix for extracted files (default: `resource`) |

### Examples

Show metadata and statistics:

```
gemview info "My Conversation"
```

Extract all embedded images:

```
gemview extract "My Conversation" --output ./images --prefix img
```

## Gemini WCX — Total Commander Plugin

The WCX plugin allows opening Gemini conversation files directly in Total Commander. Each file appears as a virtual archive containing:

```
<name>.txt                    Plain text conversation export
<name>.md                     Markdown conversation export
<name>.html                   HTML export (images as external links)
<name>_full.html              HTML export with embedded base64 images (only when resources exist)
resources\
  resource_001.png            Extracted embedded resources
  resource_002.jpg
  ...
resources\think\
  resource_003.png            Resources from thinking blocks (separated automatically)
  ...
```

The `<name>` part uses the original Gemini file name by default. This can be changed to a generic `conversation` prefix via configuration.

### Installation

1. Build the plugin from source or obtain the compiled `gemini.wcx` (32-bit) / `gemini.wcx64` (64-bit)
2. In Total Commander, go to *Configuration* > *Options* > *Plugins* > *Packer plugins*
3. Click *Configure*, then *Add* and select the `.wcx` / `.wcx64` file
4. Associate it with a file extension (e.g., `gemini`) or use the plugin directly

### Output Formats

**Plain Text** — Readable conversation with role labels (`[USER]`, `[MODEL]`), token counts, timestamps, thinking blocks wrapped in `<Thinking>` tags, and resource attachment indicators.

**Markdown** — Structured with headings (`### User`, `### Model`), collapsible thinking blocks via `<details>`, horizontal rules between turns, and inline resource references.

**HTML** — Self-contained HTML page with:

- Styled message bubbles with role labels, token counts, and timestamps
- Collapsible thinking blocks (click to expand/collapse)
- Embedded or linked images
- System instruction display
- Floating controls panel for toggling full-width mode, expanding/collapsing all thinking blocks, and toggling Markdown rendering
- Markdown rendering in model output (headings, bold, italic, code, code blocks, strikethrough)
- Custom CSS override support

**HTML Embedded** — Same as HTML but with all images embedded as base64 data URIs, producing a fully self-contained single file. Only generated when the conversation contains embedded resources.

### Block Combining

All three formatters support optional block combining. When enabled, consecutive chunks of the same kind (user, model, or thinking) are merged into a single visual block with one header. Sub-blocks within a combined group are separated by visual dividers.

This is useful when a conversation contains multiple consecutive user inputs (e.g., text followed by an image upload) or fragmented model responses that logically belong together.

Block combining is disabled by default and can be enabled per formatter independently.

## Configuration

The WCX plugin reads configuration from two optional files placed next to the plugin DLL:

- `gemini.ini` — behavioral settings
- `gemini.css` — CSS overrides for HTML output

### gemini.ini

All settings are optional. Defaults are used when a key is absent or the file does not exist.

#### [General]

| Key               | Default | Description                                                                                                                |
|-------------------|---------|----------------------------------------------------------------------------------------------------------------------------|
| `UseOriginalName` | `1`     | `1` = virtual files use the original Gemini file name (`MyChat.txt`, etc.). `0` = generic names (`conversation.txt`, etc.) |

#### [Formatters]

| Key                   | Default | Description                                             |
|-----------------------|---------|---------------------------------------------------------|
| `EnableText`          | `1`     | Include plain text export in the virtual archive        |
| `EnableMarkdown`      | `1`     | Include Markdown export in the virtual archive          |
| `EnableHtml`          | `1`     | Include HTML export in the virtual archive              |
| `EnableHtmlEmbedded`  | `1`     | Include embedded HTML export (when resources exist)     |
| `HideEmptyBlocksText` | `1`     | Hide empty display blocks in text output                |
| `HideEmptyBlocksMd`   | `1`     | Hide empty display blocks in Markdown output            |
| `HideEmptyBlocksHtml` | `1`     | Hide empty display blocks in HTML output                |
| `CombineBlocksText`   | `0`     | Combine consecutive same-kind blocks in text output     |
| `CombineBlocksMd`     | `0`     | Combine consecutive same-kind blocks in Markdown output |
| `CombineBlocksHtml`   | `0`     | Combine consecutive same-kind blocks in HTML output     |

When empty blocks are hidden, chunks with no text and no embedded resource are skipped. Remote attachment counts are shown as hints on the next non-empty block instead.

#### [HtmlDefaults]

| Key                     | Default | Description                                                                                                                                                                                |
|-------------------------|---------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `DefaultFullWidth`      | `0`     | Start the HTML page in full-width mode (no max-width column). The user can still toggle via the floating controls panel.                                                                   |
| `DefaultExpandThinking` | `0`     | Start thinking blocks expanded instead of collapsed. The user can still toggle via the floating controls panel.                                                                            |
| `RenderMarkdown`        | `1`     | Render Markdown formatting in model output as HTML. Supports: headings (`#` through `######`), bold (`**`), italic (`*`), bold-italic (`***`), inline code (`` ` ``), strikethrough (`~~`), fenced code blocks (`` ``` ``). |

### gemini.css

Place a `gemini.css` file next to the plugin DLL to override the built-in HTML styles. The custom CSS is appended after the built-in stylesheet, so it takes precedence.

Available selectors:

| Selector                | Purpose                                        |
|-------------------------|------------------------------------------------|
| `body`                  | Page container (max-width, background, font)   |
| `body.full-width`       | Active when full-width mode is on              |
| `body.md`               | Active when Markdown rendering is on           |
| `h1`                    | Page title                                     |
| `.meta`                 | Model/settings metadata line                   |
| `.section-title`        | "System Instruction" / "Conversation" headings |
| `.system-instruction`   | System instruction block                       |
| `.message`              | Each conversation turn container               |
| `.message.user`         | User message                                   |
| `.message.model`        | Model message                                  |
| `.role`                 | Role label (USER / MODEL)                      |
| `.tokens`               | Token count badge                              |
| `.time`                 | Timestamp badge                                |
| `.content`              | Message text container                         |
| `details.thinking`      | Collapsible thinking block                     |
| `summary`               | Thinking block toggle label                    |
| `.resource-img`         | Embedded/linked image                          |
| `.resource-info`        | Image metadata caption                         |
| `.remote-attachments`   | Remote attachment hint                         |
| `.combined-part`        | Sub-block within a combined group              |
| `#controls`             | Floating controls panel                        |
| `#controls button`      | Control panel buttons                          |
| `body.md .content`      | Content when Markdown is rendered              |
| `body.md .content p`    | Paragraphs in rendered Markdown                |
| `body.md .content pre`  | Fenced code blocks                             |
| `body.md .content code` | Inline code spans                              |

Example dark theme (excerpt):

```css
body {
    background: #1a1a2e;
    color: #e0e0e0;
}
.message.user {
    background: #16213e;
    border-left-color: #4a9eff;
}
.message.model {
    background: #1a1a2e;
    border-left-color: #4caf50;
}
```

See the included `gemini.css` file for a complete dark theme example and other override snippets.

## Gemini WLX — Total Commander Lister Plugin

The WLX plugin renders Gemini conversation files as formatted HTML directly in Total Commander's built-in viewer (F3) and quick view panel (Ctrl+Q). It uses an embedded WebView2 (Microsoft Edge) control for rendering.

### Features

- Renders conversations as styled HTML with embedded images, thinking blocks, and interactive controls
- In-page text search via Total Commander's search dialog
- Keyboard transparency — unmodified keys (Esc, N, P, and other TC hotkeys) pass through to Total Commander even when the viewer has focus; modifier combinations (Ctrl+C, Ctrl+A, Ctrl+scroll zoom) are handled by WebView2
- Custom CSS override support (same selectors as the WCX HTML output)

### Requirements

- Microsoft Edge WebView2 Runtime (pre-installed on Windows 10/11)
- `WebView2Loader.dll` — place in a `webview2x64` or `webview2x32` subfolder next to the plugin DLL, or in the plugin directory itself, or rely on the system search path

### Installation

1. Build the plugin from source or obtain the compiled `gemini.wlx` (32-bit) / `gemini.wlx64` (64-bit)
2. In Total Commander, go to *Configuration* > *Options* > *Plugins* > *Lister plugins (WLX)*
3. Click *Add* and select the `.wlx` / `.wlx64` file
4. The plugin auto-detects Gemini files by looking for `runSettings` and `models/gemini` in the first 8 KB of the file

### Configuration

The WLX plugin reads configuration from two optional files placed next to the plugin DLL:

- `gemini.ini` — behavioral and WebView2 settings
- `gemini.css` — CSS overrides for HTML output (same selectors as the WCX plugin)

#### gemini.ini

All settings are optional. Defaults are used when a key is absent or the file does not exist.

##### [General]

| Key                | Default | Description                                                      |
|--------------------|---------|------------------------------------------------------------------|
| `HideEmptyBlocks`  | `1`     | Hide empty display blocks (no text, no embedded resource)        |
| `CombineBlocks`    | `0`     | Combine consecutive same-kind blocks into a single visual block  |
| `RenderMarkdown`   | `1`     | Render Markdown formatting in model output as HTML               |

##### [HtmlDefaults]

| Key                       | Default | Description                                                |
|---------------------------|---------|------------------------------------------------------------|
| `DefaultFullWidth`        | `0`     | Start in full-width mode (toggleable via controls panel)   |
| `DefaultExpandThinking`   | `0`     | Start thinking blocks expanded (toggleable via controls)   |

##### [WebView2]

| Key                 | Default              | Description                                      |
|---------------------|----------------------|--------------------------------------------------|
| `UserDataFolder`    | `%TEMP%\gemini_wlx`  | WebView2 browser profile storage location        |
| `AllowContextMenu`  | `0`                  | Allow right-click context menu in the viewer     |
| `AllowDevTools`     | `0`                  | Allow opening DevTools (F12) in the viewer       |

## Building from Source

### Requirements

- Delphi 12 Athens (or compatible)
- Windows build environment

### Project Structure

```
src/                              Core library (framework-independent)
  GeminiFile.Types.pas            Value types, enums, records, helpers
  GeminiFile.Model.pas            Domain model classes
  GeminiFile.Parser.pas           JSON parser
  GeminiFile.Extractor.pas        Resource extractor
  GeminiFile.Grouping.pas         Block combining logic
  GeminiFile.Formatter.Text.pas   Plain text formatter
  GeminiFile.Formatter.Md.pas     Markdown formatter
  GeminiFile.Formatter.Html.pas   HTML formatter
  GeminiFile.Markdown.pas         Markdown-to-HTML renderer
  GeminiFile.pas                  Facade (re-exports all types)
app/                              GemView console application
wcx/                              Total Commander WCX packer plugin
  GeminiWcx.pas                   Plugin logic
  WcxApi.pas                      WCX SDK types
  gemini.dpr                      DLL project
  gemini.ini                      Example configuration
  gemini.css                      Example CSS overrides
wlx/                              Total Commander WLX lister plugin
  GeminiWlx.pas                   Plugin logic (WebView2 integration)
  WlxApi.pas                      WLX SDK types
  gemini.dpr                      DLL project
  gemini.ini                      Example configuration
  gemini.css                      Example CSS overrides
tests/                            DUnitX test suite
```

## License and copyright

Copyright (C) 2026 Pavel Dubrovsky

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation.

See [LICENSE](LICENSE) for the full text.
