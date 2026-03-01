/// <summary>
///   HTML formatter for Gemini conversations.
///   Supports two modes: external resource links and embedded base64 data URIs.
///   Produces self-contained HTML with inline CSS styling.
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
	public
		/// <summary>Creates an HTML formatter.</summary>
		/// <param name="AEmbedResources">True to embed base64 images, False for external links.</param>
		constructor Create(AEmbedResources: Boolean = False);

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
		'.resource-info { color: #888; font-size: 0.85em; margin: 4px 0; }';

{ TGeminiHtmlFormatter }

constructor TGeminiHtmlFormatter.Create(AEmbedResources: Boolean);
begin
	inherited Create;
	FEmbedResources := AEmbedResources;
end;

procedure TGeminiHtmlFormatter.FormatToStream(
	AOutput: TStream;
	AChunks: TObjectList<TGeminiChunk>;
	const ASystemInstruction: string;
	ARunSettings: TGeminiRunSettings;
	const AResources: TArray<TFormatterResourceInfo>);
var
	LChunk: TGeminiChunk;
	LText, LThinking: string;
	LResInfo: TFormatterResourceInfo;
	LFmt: TFormatSettings;
	LRoleClass, LRoleLabel: string;
begin
	LFmt := TFormatSettings.Invariant;

	// HTML header
	StreamWriteLn(AOutput, '<!DOCTYPE html>');
	StreamWriteLn(AOutput, '<html lang="en">');
	StreamWriteLn(AOutput, '<head>');
	StreamWriteLn(AOutput, '<meta charset="UTF-8">');
	StreamWriteLn(AOutput, '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
	StreamWriteLn(AOutput, '<title>Gemini Conversation</title>');
	StreamWriteLn(AOutput, '<style>');
	StreamWriteLn(AOutput, CSS_STYLES);
	StreamWriteLn(AOutput, '</style>');
	StreamWriteLn(AOutput, '</head>');
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

	// Chunks
	for LChunk in AChunks do
	begin
		if LChunk.IsThought then
		begin
			// Pure thinking chunk
			LText := LChunk.GetThinkingText;
			if LText = '' then
				LText := LChunk.Text;
			StreamWriteLn(AOutput, '<details>');
			if FindResourceForChunk(AResources, LChunk.Index, LResInfo) then
				StreamWriteLn(AOutput, '<summary>Thinking (with attachment)</summary>')
			else
				StreamWriteLn(AOutput, '<summary>Thinking</summary>');
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
			StreamWriteLn(AOutput, '</details>');
		end
		else
		begin
			// Message container
			case LChunk.Role of
				grUser:
				begin
					LRoleClass := 'user';
					LRoleLabel := 'User';
				end;
				grModel:
				begin
					LRoleClass := 'model';
					LRoleLabel := 'Model';
				end;
			end;

			StreamWriteLn(AOutput, '<div class="message ' + LRoleClass + '">');

			// Role label with optional token count
			StreamWrite(AOutput, '<div class="role">' + LRoleLabel);
			if LChunk.TokenCount > 0 then
				StreamWrite(AOutput, ' <span class="tokens">(' +
					IntToStr(LChunk.TokenCount) + ' tokens)</span>');
			StreamWriteLn(AOutput, '</div>');

			// Part-level thinking
			LThinking := LChunk.GetThinkingText;
			if LThinking <> '' then
			begin
				StreamWriteLn(AOutput, '<details>');
				StreamWriteLn(AOutput, '<summary>Thinking</summary>');
				StreamWriteLn(AOutput, '<div class="content">' + HtmlEscape(LThinking) + '</div>');
				StreamWriteLn(AOutput, '</details>');
			end;

			// Main text
			LText := LChunk.GetFullText;
			if LText <> '' then
				StreamWriteLn(AOutput, '<div class="content">' + HtmlEscape(LText) + '</div>');

			// Resource
			if FindResourceForChunk(AResources, LChunk.Index, LResInfo) then
			begin
				if FEmbedResources and (LResInfo.Base64Data <> '') then
				begin
					// Embedded: stream base64 data directly into data URI
					StreamWrite(AOutput, '<img class="resource-img" src="data:' +
						HtmlEscape(LResInfo.MimeType) + ';base64,');
					StreamWrite(AOutput, LResInfo.Base64Data);
					StreamWriteLn(AOutput, '" />');
				end
				else
				begin
					// External: reference file path
					StreamWriteLn(AOutput, '<img class="resource-img" src="' +
						HtmlEscape(LResInfo.FileName) + '" />');
				end;
				StreamWriteLn(AOutput, '<div class="resource-info">' +
					HtmlEscape(LResInfo.FileName) + ' (' + HtmlEscape(LResInfo.MimeType) +
					', ~' + FormatByteSize(LResInfo.DecodedSize) + ')</div>');
			end;

			StreamWriteLn(AOutput, '</div>');
		end;
	end;

	// HTML footer
	StreamWriteLn(AOutput, '</body>');
	StreamWriteLn(AOutput, '</html>');
end;

end.
