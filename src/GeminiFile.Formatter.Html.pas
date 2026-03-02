/// <summary>
///   HTML formatter for Gemini conversations.
///   Supports two modes: external resource links and embedded base64 data URIs.
///   Produces self-contained HTML with inline CSS styling.
///   Overrides all 15 TGeminiFormatterBase template methods to supply HTML output.
/// </summary>
unit GeminiFile.Formatter.Html;

interface

uses
	System.SysUtils,
	System.Classes,
	System.Math,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.Grouping,
	GeminiFile.Formatter.Base;

type
	/// <summary>
	///   Formats a Gemini conversation as HTML.
	///   When AEmbedResources is True, images use data: URIs with base64 content.
	///   When False, images reference external files via relative paths.
	/// </summary>
	TGeminiHtmlFormatter = class(TGeminiFormatterBase)
	private
		FEmbedResources: Boolean;
		FDefaultFullWidth: Boolean;
		FDefaultExpandThinking: Boolean;
		FRenderMarkdown: Boolean;
		FCustomCSS: string;
		/// <summary>Writes a content div, applying Markdown rendering or HTML escaping.</summary>
		procedure WriteContentDiv(AOutput: TStream; const AText: string);
		/// <summary>Writes a thinking details open tag, respecting the expand setting.</summary>
		procedure WriteThinkingDetailsOpen(AOutput: TStream);
	protected
		// -- Abstract method overrides (11) -----------------------------------
		procedure WriteDocumentStart(AOutput: TStream; ARunSettings: TGeminiRunSettings; const ASystemInstruction: string); override;
		procedure BeginThinkingGroup(AOutput: TStream; ACreateTime: TDateTime; AAnyResource: Boolean); override;
		procedure WriteThinkingSubBlock(AOutput: TStream; const AText: string; AHasResource: Boolean; const AResInfo: TFormatterResourceInfo; ASubIndex, ASubCount: Integer); override;
		procedure EndThinkingGroup(AOutput: TStream); override;
		procedure BeginContentGroup(AOutput: TStream; AKind: TChunkGroupKind; ACreateTime: TDateTime; ATotalTokens: Integer; APendingRemoteCount: Integer); override;
		procedure WriteContentSeparator(AOutput: TStream); override;
		procedure WritePartThinking(AOutput: TStream; const AThinking: string); override;
		procedure WriteContentText(AOutput: TStream; const AText: string); override;
		procedure WriteContentResource(AOutput: TStream; const AResInfo: TFormatterResourceInfo); override;
		procedure WriteRemoteHint(AOutput: TStream; ACount: Integer); override;
		procedure WriteGroupSpacing(AOutput: TStream; AKind: TChunkGroupKind; AHadVisibleContent: Boolean); override;
		// -- Virtual method overrides (4) -------------------------------------
		procedure WriteDocumentEnd(AOutput: TStream); override;
		procedure EndContentGroup(AOutput: TStream); override;
		procedure BeginContentSubBlock(AOutput: TStream; AUseCombinedLayout: Boolean); override;
		procedure EndContentSubBlock(AOutput: TStream; AUseCombinedLayout: Boolean); override;
	public
		/// <summary>Creates an HTML formatter.</summary>
		/// <param name="AEmbedResources">True to embed base64 images, False for external links.</param>
		/// <param name="ACustomCSS">Optional CSS appended after built-in styles for user overrides.</param>
		constructor Create(AEmbedResources: Boolean = False; const ACustomCSS: string = '');
		/// <summary>When True, the page starts in full-width mode (no max-width column).</summary>
		property DefaultFullWidth: Boolean read FDefaultFullWidth write FDefaultFullWidth;
		/// <summary>When True, thinking blocks start expanded instead of collapsed.</summary>
		property DefaultExpandThinking: Boolean read FDefaultExpandThinking write FDefaultExpandThinking;
		/// <summary>When True, Markdown in model output is rendered as HTML (bold, italic, code, etc).</summary>
		property RenderMarkdown: Boolean read FRenderMarkdown write FRenderMarkdown;
	end;

implementation

uses
	GeminiFile.Formatter.Utils,
	GeminiFile.Markdown;

const
	CSS_STYLES = '* { box-sizing: border-box; }' + CRLF + 'body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;' + ' max-width: 900px; margin: 0 auto; padding: 20px; background: #fafafa; color: #333; line-height: 1.6; }' + CRLF + 'h1 { margin: 0 0 10px; }' + CRLF + '.meta { color: #666; font-size: 0.9em; margin-bottom: 20px; }' + CRLF + '.section-title { font-size: 1.2em; font-weight: bold; margin: 20px 0 10px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }' + CRLF + '.system-instruction { background: #fff8e1; border-left: 4px solid #ffc107; padding: 12px 16px; margin: 10px 0 20px; white-space: pre-wrap; word-wrap: break-word; }' + CRLF + 'hr { border: none; border-top: 1px solid #ddd; margin: 20px 0; }' + CRLF +
		'.message { margin: 12px 0; padding: 12px 16px; border-radius: 8px; }' + CRLF + '.user { background: #e3f2fd; border-left: 4px solid #1976d2; }' + CRLF + '.model { background: #fff; border-left: 4px solid #388e3c; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }' + CRLF + '.role { font-weight: bold; font-size: 0.85em; text-transform: uppercase; margin-bottom: 6px; }' + CRLF + '.user .role { color: #1976d2; }' + CRLF + '.model .role { color: #388e3c; }' + CRLF + '.tokens { color: #999; font-weight: normal; font-size: 0.85em; }' + CRLF + '.content { white-space: pre-wrap; word-wrap: break-word; }' + CRLF + 'details { margin: 8px 0; background: #f5f5f5; border-radius: 4px; padding: 8px 12px; }' + CRLF + 'summary { cursor: pointer; color: #666; font-style: italic; }' + CRLF +
		'.resource-img { max-width: 100%; height: auto; margin: 8px 0; border-radius: 4px; }' + CRLF + '.resource-info { color: #888; font-size: 0.85em; margin: 4px 0; }' + CRLF + '.remote-attachments { color: #888; font-size: 0.85em; font-style: italic; margin: 4px 0; }' + CRLF + '.time { color: #999; font-weight: normal; font-size: 0.85em; }' + CRLF + 'body.full-width { max-width: none; }' + CRLF + '#controls { position: fixed; top: 10px; right: 10px; background: #fff; border: 1px solid #ddd;' + ' border-radius: 8px; padding: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.15); z-index: 1000;' + ' display: flex; gap: 6px; }' + CRLF + '#controls button { background: #f5f5f5; border: 1px solid #ccc; border-radius: 4px;' + ' padding: 4px 8px; cursor: pointer; font-size: 0.8em; white-space: nowrap; }' +
		CRLF + '#controls button:hover { background: #e0e0e0; }' + CRLF + 'body.md .content { white-space: normal; }' + CRLF + 'body.md .content p { margin: 0.4em 0; }' + CRLF + 'body.md .content p:first-child { margin-top: 0; }' + CRLF + 'body.md .content p:last-child { margin-bottom: 0; }' + CRLF + 'body.md .content pre { background: #1e1e1e; color: #d4d4d4; padding: 12px 16px;' + ' border-radius: 6px; overflow-x: auto; white-space: pre; font-family: Consolas, Monaco, monospace;' + ' margin: 8px 0; line-height: 1.4; }' + CRLF + 'body.md .content pre code { background: none; padding: 0; border-radius: 0; color: inherit; }' + CRLF + 'body.md .content code { background: #f0f0f0; padding: 2px 5px; border-radius: 3px;' + ' font-family: Consolas, Monaco, monospace; font-size: 0.9em; }' + CRLF +
		'.combined-part { border-top: 1px solid #e0e0e0; padding-top: 8px; margin-top: 8px; }' + CRLF + '.combined-part:first-child { border-top: none; padding-top: 0; margin-top: 0; }';

	{TGeminiHtmlFormatter}

	/// <summary>Writes an img tag (embedded or external) plus resource-info div.</summary>
procedure WriteHtmlResource(AOutput: TStream; AEmbedResources: Boolean; const AResInfo: TFormatterResourceInfo);
begin
	if AEmbedResources and (AResInfo.Base64Data <> '') then
	begin
		StreamWrite(AOutput, '<img class="resource-img" src="data:' + HtmlEscape(AResInfo.MimeType) + ';base64,');
		StreamWrite(AOutput, AResInfo.Base64Data);
		StreamWriteLn(AOutput, '" />');
	end
	else
		StreamWriteLn(AOutput, '<img class="resource-img" src="' + HtmlEscape(AResInfo.FileName) + '" />');
	StreamWriteLn(AOutput, '<div class="resource-info">' + HtmlEscape(AResInfo.FileName) + ' (' + HtmlEscape(AResInfo.MimeType) + ', ~' + FormatByteSize(AResInfo.DecodedSize) + ')</div>');
end;

constructor TGeminiHtmlFormatter.Create(AEmbedResources: Boolean; const ACustomCSS: string);
begin
	inherited Create;
	FEmbedResources := AEmbedResources;
	FRenderMarkdown := True;
	FCustomCSS := ACustomCSS;
end;

procedure TGeminiHtmlFormatter.WriteContentDiv(AOutput: TStream; const AText: string);
begin
	if FRenderMarkdown then
		StreamWriteLn(AOutput, '<div class="content">' + MarkdownToHtml(AText) + '</div>')
	else
		StreamWriteLn(AOutput, '<div class="content">' + HtmlEscape(AText) + '</div>');
end;

procedure TGeminiHtmlFormatter.WriteThinkingDetailsOpen(AOutput: TStream);
begin
	if FDefaultExpandThinking then
		StreamWriteLn(AOutput, '<details class="thinking" open>')
	else
		StreamWriteLn(AOutput, '<details class="thinking">');
end;

procedure TGeminiHtmlFormatter.WriteDocumentStart(AOutput: TStream; ARunSettings: TGeminiRunSettings; const ASystemInstruction: string);
var
	LFmt: TFormatSettings;
	LBodyClasses: string;
begin
	LFmt := TFormatSettings.Invariant;

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

	StreamWriteLn(AOutput, '<h1>Gemini Conversation</h1>');

	// Metadata
	StreamWrite(AOutput, '<div class="meta">');
	if ARunSettings.Model <> '' then
		StreamWrite(AOutput, '<strong>Model:</strong> ' + HtmlEscape(ARunSettings.Model));
	if not IsNaN(ARunSettings.Temperature) then
		StreamWrite(AOutput, ' | <strong>Temperature:</strong> ' + FormatFloat('0.0#', ARunSettings.Temperature, LFmt));
	if not IsNaN(ARunSettings.TopP) then
		StreamWrite(AOutput, ' | <strong>TopP:</strong> ' + FormatFloat('0.0#', ARunSettings.TopP, LFmt));
	if ARunSettings.TopK >= 0 then
		StreamWrite(AOutput, ' | <strong>TopK:</strong> ' + IntToStr(ARunSettings.TopK));
	if ARunSettings.MaxOutputTokens >= 0 then
		StreamWrite(AOutput, ' | <strong>MaxOutputTokens:</strong> ' + IntToStr(ARunSettings.MaxOutputTokens));
	StreamWriteLn(AOutput, '</div>');

	// System instruction
	if ASystemInstruction <> '' then
	begin
		StreamWriteLn(AOutput, '<div class="section-title">System Instruction</div>');
		StreamWriteLn(AOutput, '<div class="system-instruction">' + HtmlEscape(ASystemInstruction) + '</div>');
	end;

	StreamWriteLn(AOutput, '<hr>');
	StreamWriteLn(AOutput, '<div class="section-title">Conversation</div>');
end;

procedure TGeminiHtmlFormatter.BeginThinkingGroup(AOutput: TStream; ACreateTime: TDateTime; AAnyResource: Boolean);
begin
	WriteThinkingDetailsOpen(AOutput);
	StreamWriteLn(AOutput, '<summary>Thinking' + HtmlEscape(ThinkingSummarySuffix(ACreateTime, AAnyResource)) + '</summary>');
end;

procedure TGeminiHtmlFormatter.WriteThinkingSubBlock(AOutput: TStream; const AText: string; AHasResource: Boolean; const AResInfo: TFormatterResourceInfo; ASubIndex, ASubCount: Integer);
var
	LUseCombinedParts: Boolean;
begin
	LUseCombinedParts := ASubCount > 1;
	if LUseCombinedParts then
		StreamWriteLn(AOutput, '<div class="combined-part">');

	WriteContentDiv(AOutput, AText);

	if AHasResource then
		WriteHtmlResource(AOutput, FEmbedResources, AResInfo);

	if LUseCombinedParts then
		StreamWriteLn(AOutput, '</div>');
end;

procedure TGeminiHtmlFormatter.EndThinkingGroup(AOutput: TStream);
begin
	StreamWriteLn(AOutput, '</details>');
end;

procedure TGeminiHtmlFormatter.BeginContentGroup(AOutput: TStream; AKind: TChunkGroupKind; ACreateTime: TDateTime; ATotalTokens: Integer; APendingRemoteCount: Integer);
var
	LRoleClass, LRoleLabel: string;
begin
	case AKind of
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

	StreamWriteLn(AOutput, '<div class="message ' + LRoleClass + '">');

	// Role label with optional timestamp and token count
	StreamWrite(AOutput, '<div class="role">' + LRoleLabel);
	if ACreateTime > 0 then
		StreamWrite(AOutput, ' <span class="time">' + HtmlEscape(FormatCreateTime(ACreateTime)) + '</span>');
	if ATotalTokens > 0 then
		StreamWrite(AOutput, ' <span class="tokens">(' + IntToStr(ATotalTokens) + ' tokens)</span>');
	StreamWriteLn(AOutput, '</div>');

	// Remote attachment hint (inside the message container, after role label)
	if APendingRemoteCount > 0 then
		StreamWriteLn(AOutput, '<div class="remote-attachments" title="' + IntToStr(APendingRemoteCount) + ' remote attachment(s) uploaded before this message">' + IntToStr(APendingRemoteCount) + ' remote attachment(s)</div>');
end;

procedure TGeminiHtmlFormatter.WriteContentSeparator(AOutput: TStream);
begin
	// HTML uses combined-part divs for sub-block separation, no explicit separator
end;

procedure TGeminiHtmlFormatter.WritePartThinking(AOutput: TStream; const AThinking: string);
begin
	WriteThinkingDetailsOpen(AOutput);
	StreamWriteLn(AOutput, '<summary>Thinking</summary>');
	WriteContentDiv(AOutput, AThinking);
	StreamWriteLn(AOutput, '</details>');
end;

procedure TGeminiHtmlFormatter.WriteContentText(AOutput: TStream; const AText: string);
begin
	WriteContentDiv(AOutput, AText);
end;

procedure TGeminiHtmlFormatter.WriteContentResource(AOutput: TStream; const AResInfo: TFormatterResourceInfo);
begin
	WriteHtmlResource(AOutput, FEmbedResources, AResInfo);
end;

procedure TGeminiHtmlFormatter.WriteRemoteHint(AOutput: TStream; ACount: Integer);
begin
	StreamWriteLn(AOutput, '<div class="message user">');
	StreamWriteLn(AOutput, '<div class="remote-attachments">' + IntToStr(ACount) + ' remote attachment(s)</div>');
	StreamWriteLn(AOutput, '</div>');
end;

procedure TGeminiHtmlFormatter.WriteGroupSpacing(AOutput: TStream; AKind: TChunkGroupKind; AHadVisibleContent: Boolean);
begin
	// HTML uses CSS margins for spacing, no blank lines needed
end;

procedure TGeminiHtmlFormatter.WriteDocumentEnd(AOutput: TStream);
begin
	// Controls panel
	StreamWriteLn(AOutput, '<div id="controls">');
	if FDefaultFullWidth then
		StreamWriteLn(AOutput, '<button onclick="toggleWidth(this)">Column width</button>')
	else
		StreamWriteLn(AOutput, '<button onclick="toggleWidth(this)">Full width</button>');
	StreamWriteLn(AOutput, '<button onclick="setThinking(true)">Expand thinking</button>');
	StreamWriteLn(AOutput, '<button onclick="setThinking(false)">Collapse thinking</button>');
	StreamWriteLn(AOutput, '</div>');

	// JavaScript
	StreamWriteLn(AOutput, '<script>');
	StreamWriteLn(AOutput, 'function toggleWidth(btn) {');
	StreamWriteLn(AOutput, '  document.body.classList.toggle("full-width");');
	StreamWriteLn(AOutput, '  btn.textContent = document.body.classList.contains("full-width") ? "Column width" : "Full width";');
	StreamWriteLn(AOutput, '}');
	StreamWriteLn(AOutput, 'function setThinking(open) {');
	StreamWriteLn(AOutput, '  document.querySelectorAll("details.thinking").forEach(function(d) { d.open = open; });');
	StreamWriteLn(AOutput, '}');
	StreamWriteLn(AOutput, '</script>');

	StreamWriteLn(AOutput, '</body>');
	StreamWriteLn(AOutput, '</html>');
end;

procedure TGeminiHtmlFormatter.EndContentGroup(AOutput: TStream);
begin
	StreamWriteLn(AOutput, '</div>');
end;

procedure TGeminiHtmlFormatter.BeginContentSubBlock(AOutput: TStream; AUseCombinedLayout: Boolean);
begin
	if AUseCombinedLayout then
		StreamWriteLn(AOutput, '<div class="combined-part">');
end;

procedure TGeminiHtmlFormatter.EndContentSubBlock(AOutput: TStream; AUseCombinedLayout: Boolean);
begin
	if AUseCombinedLayout then
		StreamWriteLn(AOutput, '</div>');
end;

end.
