/// <summary>
///   HTML formatter for Gemini conversations.
///   Supports two modes: external resource links and embedded base64 data URIs.
///   Produces self-contained HTML with inline CSS styling.
///   Supports optional block combining for consecutive same-kind chunks.
/// </summary>
unit GeminiFile.Formatter.Html;

interface

uses
	System.SysUtils,
	System.Classes,
	System.Math,
	System.Generics.Collections,
	GeminiFile.Types,
	GeminiFile.Model;

type
	/// <summary>
	///   Formats a Gemini conversation as HTML.
	///   When AEmbedResources is True, images use data: URIs with base64 content.
	///   When False, images reference external files via relative paths.
	/// </summary>
	TGeminiHtmlFormatter = class
	private
		FEmbedResources: Boolean;
		FHideEmptyBlocks: Boolean;
		FDefaultFullWidth: Boolean;
		FDefaultExpandThinking: Boolean;
		FRenderMarkdown: Boolean;
		FCustomCSS: string;
		FCombineBlocks: Boolean;
	public
		/// <summary>Creates an HTML formatter.</summary>
		/// <param name="AEmbedResources">True to embed base64 images, False for external links.</param>
		/// <param name="ACustomCSS">Optional CSS appended after built-in styles for user overrides.</param>
		constructor Create(AEmbedResources: Boolean = False; const ACustomCSS: string = '');
		/// <summary>When True, empty blocks are skipped and remote attachment hints shown instead.</summary>
		property HideEmptyBlocks: Boolean read FHideEmptyBlocks write FHideEmptyBlocks;
		/// <summary>When True, the page starts in full-width mode (no max-width column).</summary>
		property DefaultFullWidth: Boolean read FDefaultFullWidth write FDefaultFullWidth;
		/// <summary>When True, thinking blocks start expanded instead of collapsed.</summary>
		property DefaultExpandThinking: Boolean read FDefaultExpandThinking write FDefaultExpandThinking;
		/// <summary>When True, Markdown in model output is rendered as HTML (bold, italic, code, etc).</summary>
		property RenderMarkdown: Boolean read FRenderMarkdown write FRenderMarkdown;
		/// <summary>When True, consecutive same-kind chunks are merged into a single visual block.</summary>
		property CombineBlocks: Boolean read FCombineBlocks write FCombineBlocks;

		/// <summary>
		///   Writes the formatted conversation to the output stream as UTF-8 HTML.
		/// </summary>
		/// <param name="AOutput">Target stream.</param>
		/// <param name="AChunks">Conversation chunks in order.</param>
		/// <param name="ASystemInstruction">System instruction text. Empty if none.</param>
		/// <param name="ARunSettings">Model run settings.</param>
		/// <param name="AResources">Resource info records for link/embed generation.</param>
		procedure FormatToStream(
			AOutput: TStream;
			AChunks: TObjectList<TGeminiChunk>;
			const ASystemInstruction: string;
			ARunSettings: TGeminiRunSettings;
			const AResources: TArray<TFormatterResourceInfo>
		);
	end;

implementation

uses
	GeminiFile.Markdown,
	GeminiFile.Grouping;

const
	CRLF = #13#10;

procedure StreamWrite(AStream: TStream; const AStr: string);
var
	LBytes: TBytes;
begin
	LBytes := TEncoding.UTF8.GetBytes(AStr);
	if Length(LBytes) > 0 then
		AStream.WriteBuffer(LBytes[0], Length(LBytes));
end;

procedure StreamWriteLn(AStream: TStream; const AStr: string = '');
begin
	StreamWrite(AStream, AStr + CRLF);
end;

function HtmlEscape(const AStr: string): string;
begin
	Result := AStr;
	Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
	Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
	Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
	Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

const
	CSS_STYLES =
		'* { box-sizing: border-box; }' + CRLF +
		'body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;' +
		' max-width: 900px; margin: 0 auto; padding: 20px; background: #fafafa; color: #333; line-height: 1.6; }' + CRLF +
		'h1 { margin: 0 0 10px; }' + CRLF +
		'.meta { color: #666; font-size: 0.9em; margin-bottom: 20px; }' + CRLF +
		'.section-title { font-size: 1.2em; font-weight: bold; margin: 20px 0 10px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }' + CRLF +
		'.system-instruction { background: #fff8e1; border-left: 4px solid #ffc107; padding: 12px 16px; margin: 10px 0 20px; white-space: pre-wrap; word-wrap: break-word; }' + CRLF +
		'hr { border: none; border-top: 1px solid #ddd; margin: 20px 0; }' + CRLF +
		'.message { margin: 12px 0; padding: 12px 16px; border-radius: 8px; }' + CRLF +
		'.user { background: #e3f2fd; border-left: 4px solid #1976d2; }' + CRLF +
		'.model { background: #fff; border-left: 4px solid #388e3c; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }' + CRLF +
		'.role { font-weight: bold; font-size: 0.85em; text-transform: uppercase; margin-bottom: 6px; }' + CRLF +
		'.user .role { color: #1976d2; }' + CRLF +
		'.model .role { color: #388e3c; }' + CRLF +
		'.tokens { color: #999; font-weight: normal; font-size: 0.85em; }' + CRLF +
		'.content { white-space: pre-wrap; word-wrap: break-word; }' + CRLF +
		'details { margin: 8px 0; background: #f5f5f5; border-radius: 4px; padding: 8px 12px; }' + CRLF +
		'summary { cursor: pointer; color: #666; font-style: italic; }' + CRLF +
		'.resource-img { max-width: 100%; height: auto; margin: 8px 0; border-radius: 4px; }' + CRLF +
		'.resource-info { color: #888; font-size: 0.85em; margin: 4px 0; }' + CRLF +
		'.remote-attachments { color: #888; font-size: 0.85em; font-style: italic; margin: 4px 0; }' + CRLF +
		'.time { color: #999; font-weight: normal; font-size: 0.85em; }' + CRLF +
		'body.full-width { max-width: none; }' + CRLF +
		'#controls { position: fixed; top: 10px; right: 10px; background: #fff; border: 1px solid #ddd;' +
		' border-radius: 8px; padding: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.15); z-index: 1000;' +
		' display: flex; gap: 6px; flex-wrap: wrap; max-width: 220px; }' + CRLF +
		'#controls button { background: #f5f5f5; border: 1px solid #ccc; border-radius: 4px;' +
		' padding: 4px 8px; cursor: pointer; font-size: 0.8em; white-space: nowrap; }' + CRLF +
		'#controls button:hover { background: #e0e0e0; }' + CRLF +
		'body.md .content { white-space: normal; }' + CRLF +
		'body.md .content p { margin: 0.4em 0; }' + CRLF +
		'body.md .content p:first-child { margin-top: 0; }' + CRLF +
		'body.md .content p:last-child { margin-bottom: 0; }' + CRLF +
		'body.md .content pre { background: #1e1e1e; color: #d4d4d4; padding: 12px 16px;' +
		' border-radius: 6px; overflow-x: auto; white-space: pre; font-family: Consolas, Monaco, monospace;' +
		' margin: 8px 0; line-height: 1.4; }' + CRLF +
		'body.md .content pre code { background: none; padding: 0; border-radius: 0; color: inherit; }' + CRLF +
		'body.md .content code { background: #f0f0f0; padding: 2px 5px; border-radius: 3px;' +
		' font-family: Consolas, Monaco, monospace; font-size: 0.9em; }' + CRLF +
		'.combined-part { border-top: 1px solid #e0e0e0; padding-top: 8px; margin-top: 8px; }' + CRLF +
		'.combined-part:first-child { border-top: none; padding-top: 0; margin-top: 0; }';

{ TGeminiHtmlFormatter }

constructor TGeminiHtmlFormatter.Create(AEmbedResources: Boolean; const ACustomCSS: string);
begin
	inherited Create;
	FEmbedResources := AEmbedResources;
	FHideEmptyBlocks := True;
	FRenderMarkdown := True;
	FCustomCSS := ACustomCSS;
	FCombineBlocks := False;
end;

procedure TGeminiHtmlFormatter.FormatToStream(
	AOutput: TStream;
	AChunks: TObjectList<TGeminiChunk>;
	const ASystemInstruction: string;
	ARunSettings: TGeminiRunSettings;
	const AResources: TArray<TFormatterResourceInfo>);
var
	LGroups: TArray<TChunkGroup>;
	LGroup: TChunkGroup;
	LChunk: TGeminiChunk;
	LText, LThinking: string;
	LResInfo: TFormatterResourceInfo;
	LHasResource: Boolean;
	LPendingRemoteCount: Integer;
	LFmt: TFormatSettings;
	LRoleClass, LRoleLabel, LSummary: string;
	LBodyClasses: string;
	I: Integer;
	LFirstContent: Boolean;
	LSubBlockIndex: Integer;
	LAnyResource: Boolean;
	LUseCombinedParts: Boolean;
begin
	LFmt := TFormatSettings.Invariant;
	LPendingRemoteCount := 0;

	// HTML header
	StreamWriteLn(AOutput, '<!DOCTYPE html>');
	StreamWriteLn(AOutput, '<html lang="en">');
	StreamWriteLn(AOutput, '<head>');
	StreamWriteLn(AOutput, '<meta charset="UTF-8">');
	StreamWriteLn(AOutput, '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
	StreamWriteLn(AOutput, '<title>Gemini Conversation</title>');
	StreamWriteLn(AOutput, '<style>');
	StreamWriteLn(AOutput, CSS_STYLES);
	if FCustomCSS <> '' then
		StreamWriteLn(AOutput, FCustomCSS);
	StreamWriteLn(AOutput, '</style>');
	StreamWriteLn(AOutput, '</head>');
	// Build body class list from active options
	LBodyClasses := '';
	if FDefaultFullWidth then
		LBodyClasses := LBodyClasses + ' full-width';
	if FRenderMarkdown then
		LBodyClasses := LBodyClasses + ' md';
	LBodyClasses := Trim(LBodyClasses);
	if LBodyClasses <> '' then
		StreamWriteLn(AOutput, '<body class="' + LBodyClasses + '">')
	else
		StreamWriteLn(AOutput, '<body>');

	// Title
	StreamWriteLn(AOutput, '<h1>Gemini Conversation</h1>');

	// Metadata
	StreamWrite(AOutput, '<div class="meta">');
	if ARunSettings.Model <> '' then
		StreamWrite(AOutput, '<strong>Model:</strong> ' + HtmlEscape(ARunSettings.Model));
	if not IsNaN(ARunSettings.Temperature) then
		StreamWrite(AOutput, ' | <strong>Temperature:</strong> ' +
			FormatFloat('0.0#', ARunSettings.Temperature, LFmt));
	if not IsNaN(ARunSettings.TopP) then
		StreamWrite(AOutput, ' | <strong>TopP:</strong> ' +
			FormatFloat('0.0#', ARunSettings.TopP, LFmt));
	if ARunSettings.TopK >= 0 then
		StreamWrite(AOutput, ' | <strong>TopK:</strong> ' + IntToStr(ARunSettings.TopK));
	if ARunSettings.MaxOutputTokens >= 0 then
		StreamWrite(AOutput, ' | <strong>MaxOutputTokens:</strong> ' + IntToStr(ARunSettings.MaxOutputTokens));
	StreamWriteLn(AOutput, '</div>');

	// System instruction
	if ASystemInstruction <> '' then
	begin
		StreamWriteLn(AOutput, '<div class="section-title">System Instruction</div>');
		StreamWriteLn(AOutput, '<div class="system-instruction">' +
			HtmlEscape(ASystemInstruction) + '</div>');
	end;

	StreamWriteLn(AOutput, '<hr>');
	StreamWriteLn(AOutput, '<div class="section-title">Conversation</div>');

	// Build groups
	LGroups := GroupConsecutiveChunks(AChunks, FCombineBlocks);

	// Iterate groups
	for I := 0 to High(LGroups) do
	begin
		LGroup := LGroups[I];

		if LGroup.Kind = gkThinking then
		begin
			// Thinking group -- one <details> with combined summary
			if FDefaultExpandThinking then
				StreamWriteLn(AOutput, '<details class="thinking" open>')
			else
				StreamWriteLn(AOutput, '<details class="thinking">');
			LSummary := 'Thinking';
			// Check if any chunk in the group has a resource
			LAnyResource := False;
			for LSubBlockIndex := 0 to High(LGroup.Chunks) do
				if FindResourceForChunk(AResources, LGroup.Chunks[LSubBlockIndex].Index, LResInfo) then
				begin
					LAnyResource := True;
					Break;
				end;
			if (LGroup.FirstCreateTime > 0) and LAnyResource then
				LSummary := LSummary + ' (' + HtmlEscape(FormatCreateTime(LGroup.FirstCreateTime)) + ', with attachment)'
			else if LGroup.FirstCreateTime > 0 then
				LSummary := LSummary + ' (' + HtmlEscape(FormatCreateTime(LGroup.FirstCreateTime)) + ')'
			else if LAnyResource then
				LSummary := LSummary + ' (with attachment)';
			StreamWriteLn(AOutput, '<summary>' + LSummary + '</summary>');

			for LSubBlockIndex := 0 to High(LGroup.Chunks) do
			begin
				LChunk := LGroup.Chunks[LSubBlockIndex];
				LText := LChunk.GetThinkingText;
				if LText = '' then
					LText := LChunk.Text;

				// Use combined-part divs when group has multiple chunks
				LUseCombinedParts := Length(LGroup.Chunks) > 1;
				if LUseCombinedParts then
					StreamWriteLn(AOutput, '<div class="combined-part">');

				if FRenderMarkdown then
					StreamWriteLn(AOutput, '<div class="content">' + MarkdownToHtml(LText) + '</div>')
				else
					StreamWriteLn(AOutput, '<div class="content">' + HtmlEscape(LText) + '</div>');
				if FindResourceForChunk(AResources, LChunk.Index, LResInfo) then
				begin
					if FEmbedResources and (LResInfo.Base64Data <> '') then
					begin
						StreamWrite(AOutput, '<img class="resource-img" src="data:' +
							HtmlEscape(LResInfo.MimeType) + ';base64,');
						StreamWrite(AOutput, LResInfo.Base64Data);
						StreamWriteLn(AOutput, '" />');
					end
					else
						StreamWriteLn(AOutput, '<img class="resource-img" src="' +
							HtmlEscape(LResInfo.FileName) + '" />');
					StreamWriteLn(AOutput, '<div class="resource-info">' +
						HtmlEscape(LResInfo.FileName) + ' (' + HtmlEscape(LResInfo.MimeType) +
						', ~' + FormatByteSize(LResInfo.DecodedSize) + ')</div>');
				end;

				if LUseCombinedParts then
					StreamWriteLn(AOutput, '</div>');
			end;
			StreamWriteLn(AOutput, '</details>');
		end
		else
		begin
			// User/Model group -- lazy header emission for empty block handling
			case LGroup.Kind of
				gkUser:
				begin
					LRoleClass := 'user';
					LRoleLabel := 'User';
				end;
			else
				begin
					LRoleClass := 'model';
					LRoleLabel := 'Model';
				end;
			end;

			LFirstContent := True;

			for LSubBlockIndex := 0 to High(LGroup.Chunks) do
			begin
				LChunk := LGroup.Chunks[LSubBlockIndex];

				// Pre-compute text and resource for empty block detection
				LText := LChunk.GetFullText;
				LHasResource := FindResourceForChunk(AResources, LChunk.Index, LResInfo);

				// Skip empty display blocks (no text, no embedded resource)
				if FHideEmptyBlocks and (LText = '') and (not LHasResource) then
				begin
					if LChunk.DriveImageId <> '' then
						Inc(LPendingRemoteCount);
					Continue;
				end;

				// Emit message container and role header lazily on first visible sub-block
				if LFirstContent then
				begin
					StreamWriteLn(AOutput, '<div class="message ' + LRoleClass + '">');

					// Role label with optional timestamp and token count
					StreamWrite(AOutput, '<div class="role">' + LRoleLabel);
					if LGroup.FirstCreateTime > 0 then
						StreamWrite(AOutput, ' <span class="time">' +
							HtmlEscape(FormatCreateTime(LGroup.FirstCreateTime)) + '</span>');
					if LGroup.TotalTokenCount > 0 then
						StreamWrite(AOutput, ' <span class="tokens">(' +
							IntToStr(LGroup.TotalTokenCount) + ' tokens)</span>');
					StreamWriteLn(AOutput, '</div>');

					// Emit pending remote attachment hint
					if LPendingRemoteCount > 0 then
					begin
						StreamWriteLn(AOutput, '<div class="remote-attachments" title="' +
							IntToStr(LPendingRemoteCount) +
							' remote attachment(s) uploaded before this message">' +
							IntToStr(LPendingRemoteCount) + ' remote attachment(s)</div>');
						LPendingRemoteCount := 0;
					end;

					LFirstContent := False;
				end;

				// Use combined-part divs when group has multiple chunks
				LUseCombinedParts := Length(LGroup.Chunks) > 1;
				if LUseCombinedParts then
					StreamWriteLn(AOutput, '<div class="combined-part">');

				// Part-level thinking
				LThinking := LChunk.GetThinkingText;
				if LThinking <> '' then
				begin
					if FDefaultExpandThinking then
						StreamWriteLn(AOutput, '<details class="thinking" open>')
					else
						StreamWriteLn(AOutput, '<details class="thinking">');
					StreamWriteLn(AOutput, '<summary>Thinking</summary>');
					if FRenderMarkdown then
						StreamWriteLn(AOutput, '<div class="content">' + MarkdownToHtml(LThinking) + '</div>')
					else
						StreamWriteLn(AOutput, '<div class="content">' + HtmlEscape(LThinking) + '</div>');
					StreamWriteLn(AOutput, '</details>');
				end;

				// Main text
				if LText <> '' then
				begin
					if FRenderMarkdown then
						StreamWriteLn(AOutput, '<div class="content">' + MarkdownToHtml(LText) + '</div>')
					else
						StreamWriteLn(AOutput, '<div class="content">' + HtmlEscape(LText) + '</div>');
				end;

				// Resource
				if LHasResource then
				begin
					if FEmbedResources and (LResInfo.Base64Data <> '') then
					begin
						StreamWrite(AOutput, '<img class="resource-img" src="data:' +
							HtmlEscape(LResInfo.MimeType) + ';base64,');
						StreamWrite(AOutput, LResInfo.Base64Data);
						StreamWriteLn(AOutput, '" />');
					end
					else
					begin
						StreamWriteLn(AOutput, '<img class="resource-img" src="' +
							HtmlEscape(LResInfo.FileName) + '" />');
					end;
					StreamWriteLn(AOutput, '<div class="resource-info">' +
						HtmlEscape(LResInfo.FileName) + ' (' + HtmlEscape(LResInfo.MimeType) +
						', ~' + FormatByteSize(LResInfo.DecodedSize) + ')</div>');
				end;

				if LUseCombinedParts then
					StreamWriteLn(AOutput, '</div>');
			end;

			// Close message container if it was opened
			if not LFirstContent then
				StreamWriteLn(AOutput, '</div>');
		end;
	end;

	// Trailing remote attachment hint (empty blocks at end of conversation)
	if LPendingRemoteCount > 0 then
	begin
		StreamWriteLn(AOutput, '<div class="message user">');
		StreamWriteLn(AOutput, '<div class="remote-attachments">' +
			IntToStr(LPendingRemoteCount) + ' remote attachment(s)</div>');
		StreamWriteLn(AOutput, '</div>');
	end;

	// Controls panel
	StreamWriteLn(AOutput, '<div id="controls">');
	if FDefaultFullWidth then
		StreamWriteLn(AOutput, '<button onclick="toggleWidth(this)">Column width</button>')
	else
		StreamWriteLn(AOutput, '<button onclick="toggleWidth(this)">Full width</button>');
	StreamWriteLn(AOutput, '<button onclick="setDetails(true)">Expand all</button>');
	StreamWriteLn(AOutput, '<button onclick="setDetails(false)">Collapse all</button>');
	StreamWriteLn(AOutput, '<button onclick="setThinking(true)">Expand thinking</button>');
	StreamWriteLn(AOutput, '<button onclick="setThinking(false)">Collapse thinking</button>');
	StreamWriteLn(AOutput, '</div>');

	// JavaScript
	StreamWriteLn(AOutput, '<script>');
	StreamWriteLn(AOutput, 'function toggleWidth(btn) {');
	StreamWriteLn(AOutput, '  document.body.classList.toggle("full-width");');
	StreamWriteLn(AOutput, '  btn.textContent = document.body.classList.contains("full-width") ? "Column width" : "Full width";');
	StreamWriteLn(AOutput, '}');
	StreamWriteLn(AOutput, 'function setDetails(open) {');
	StreamWriteLn(AOutput, '  document.querySelectorAll("details").forEach(function(d) { d.open = open; });');
	StreamWriteLn(AOutput, '}');
	StreamWriteLn(AOutput, 'function setThinking(open) {');
	StreamWriteLn(AOutput, '  document.querySelectorAll("details.thinking").forEach(function(d) { d.open = open; });');
	StreamWriteLn(AOutput, '}');
	StreamWriteLn(AOutput, '</script>');

	// HTML footer
	StreamWriteLn(AOutput, '</body>');
	StreamWriteLn(AOutput, '</html>');
end;

end.
