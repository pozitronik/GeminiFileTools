/// <summary>
///   Lightweight Markdown-to-HTML converter for Gemini model output.
///   Handles headings, inline formatting (bold, italic, code, strikethrough)
///   and fenced code blocks. No regex, no external dependencies -- pure string
///   scanning suitable for DLL/plugin use.
/// </summary>
unit GeminiFile.Markdown;

interface

/// <summary>
///   Converts a subset of Markdown to HTML.
///   Supported: headings (# through ######), bold (**), italic (*),
///   bold-italic (***), inline code (`), strikethrough (~~),
///   fenced code blocks (```), paragraphs, line breaks.
/// </summary>
/// <param name="AText">Raw Markdown text from Gemini model output.</param>
/// <returns>HTML string with formatting applied. Empty input returns empty string.</returns>
function MarkdownToHtml(const AText: string): string;

implementation

uses
	System.SysUtils,
	GeminiFile.Formatter.Utils;

/// <summary>
///   Splits text on a given delimiter string. Returns an array of parts
///   (always at least one element even for empty input).
/// </summary>
function SplitString(const AText, ADelimiter: string): TArray<string>;
var
	LPos, LStart, LDelLen: Integer;
	LList: TArray<string>;
	LCount: Integer;
begin
	LDelLen := Length(ADelimiter);
	if (AText = '') or (LDelLen = 0) then
	begin
		SetLength(Result, 1);
		Result[0] := AText;
		Exit;
	end;

	LCount := 0;
	SetLength(LList, 16);
	LStart := 1;

	repeat
		LPos := Pos(ADelimiter, AText, LStart);
		if LPos = 0 then
			LPos := Length(AText) + 1;

		if LCount >= Length(LList) then
			SetLength(LList, Length(LList) * 2);
		LList[LCount] := Copy(AText, LStart, LPos - LStart);
		Inc(LCount);

		LStart := LPos + LDelLen;
	until LPos > Length(AText);

	SetLength(LList, LCount);
	Result := LList;
end;

type
	/// <summary>Placeholder for extracted inline code spans.</summary>
	TCodePlaceholder = record
		Token: string;
		Html: string;
	end;

/// <summary>
///   Extracts inline code spans (backtick-delimited) from text, replacing them
///   with unique placeholders. The code content is HTML-escaped and wrapped in
///   code tags. Returns modified text and the placeholder map.
/// </summary>
procedure ExtractInlineCode(var AText: string; out APlaceholders: TArray<TCodePlaceholder>);
var
	LSB: TStringBuilder;
	I, LStart, LEnd: Integer;
	LCount: Integer;
	LCode, LToken: string;
begin
	LCount := 0;
	SetLength(APlaceholders, 0);
	LSB := TStringBuilder.Create(Length(AText));
	try
		I := 1;
		while I <= Length(AText) do
		begin
			if AText[I] = '`' then
			begin
				LStart := I + 1;
				LEnd := LStart;
				while (LEnd <= Length(AText)) and (AText[LEnd] <> '`') do
					Inc(LEnd);

				if LEnd <= Length(AText) then
				begin
					// Found closing backtick
					LCode := Copy(AText, LStart, LEnd - LStart);
					LToken := #1 + 'CODE' + IntToStr(LCount) + #1;

					Inc(LCount);
					SetLength(APlaceholders, LCount);
					APlaceholders[LCount - 1].Token := LToken;
					APlaceholders[LCount - 1].Html := '<code>' + HtmlEscape(LCode) + '</code>';

					LSB.Append(LToken);
					I := LEnd + 1;
					Continue;
				end;
			end;

			LSB.Append(AText[I]);
			Inc(I);
		end;
		AText := LSB.ToString;
	finally
		LSB.Free;
	end;
end;

/// <summary>
///   Restores inline code placeholders with their HTML equivalents.
/// </summary>
procedure RestoreInlineCode(var AText: string; const APlaceholders: TArray<TCodePlaceholder>);
var
	I: Integer;
begin
	for I := 0 to High(APlaceholders) do
		AText := StringReplace(AText, APlaceholders[I].Token, APlaceholders[I].Html, [rfReplaceAll]);
end;

/// <summary>
///   Applies a single inline marker pattern with flanking delimiter rules.
///   The opening marker must be followed by a non-space character, and
///   the closing marker must be preceded by a non-space character.
/// </summary>
/// <param name="AText">Text to process (modified in place).</param>
/// <param name="AMarker">The marker string (e.g. '**', '*', '~~').</param>
/// <param name="AOpenTag">HTML opening tag (e.g. '&lt;strong&gt;').</param>
/// <param name="ACloseTag">HTML closing tag (e.g. '&lt;/strong&gt;').</param>
procedure ApplyInlineMarker(var AText: string; const AMarker, AOpenTag, ACloseTag: string);
var
	LMarkerLen: Integer;
	LOpenPos, LClosePos: Integer;
	LSB: TStringBuilder;
	LSearchFrom: Integer;
	LAfterOpen, LBeforeClose: Char;
begin
	LMarkerLen := Length(AMarker);
	LSB := TStringBuilder.Create(Length(AText));
	try
		LSearchFrom := 1;

		while LSearchFrom <= Length(AText) do
		begin
			LOpenPos := Pos(AMarker, AText, LSearchFrom);
			if LOpenPos = 0 then
				Break;

			// Flanking check: char after opening marker must be non-space
			if LOpenPos + LMarkerLen > Length(AText) then
				Break;
			LAfterOpen := AText[LOpenPos + LMarkerLen];
			if (LAfterOpen = ' ') or (LAfterOpen = #9) or (LAfterOpen = #10) or (LAfterOpen = #13) then
			begin
				// Not a valid opening -- copy up to and including this marker, continue
				LSB.Append(Copy(AText, LSearchFrom, LOpenPos + LMarkerLen - LSearchFrom));
				LSearchFrom := LOpenPos + LMarkerLen;
				Continue;
			end;

			// Search for closing marker
			LClosePos := Pos(AMarker, AText, LOpenPos + LMarkerLen);
			if LClosePos = 0 then
				Break;

			// Flanking check: char before closing marker must be non-space
			LBeforeClose := AText[LClosePos - 1];
			if (LBeforeClose = ' ') or (LBeforeClose = #9) or (LBeforeClose = #10) or (LBeforeClose = #13) then
			begin
				LSB.Append(Copy(AText, LSearchFrom, LOpenPos + LMarkerLen - LSearchFrom));
				LSearchFrom := LOpenPos + LMarkerLen;
				Continue;
			end;

			// Valid match: emit text before marker, then wrapped content
			LSB.Append(Copy(AText, LSearchFrom, LOpenPos - LSearchFrom));
			LSB.Append(AOpenTag);
			LSB.Append(Copy(AText, LOpenPos + LMarkerLen, LClosePos - LOpenPos - LMarkerLen));
			LSB.Append(ACloseTag);
			LSearchFrom := LClosePos + LMarkerLen;
		end;

		// Append remainder
		LSB.Append(Copy(AText, LSearchFrom, MaxInt));
		AText := LSB.ToString;
	finally
		LSB.Free;
	end;
end;

/// <summary>
///   Applies the full inline formatting pipeline to a text fragment:
///   inline code extraction, HTML escaping, marker application, code restoration.
///   Shared by prose paragraphs and heading text.
/// </summary>
function FormatInline(const AText: string): string;
var
	LPlaceholders: TArray<TCodePlaceholder>;
begin
	Result := AText;
	ExtractInlineCode(Result, LPlaceholders);
	Result := HtmlEscape(Result);
	ApplyInlineMarker(Result, '***', '<strong><em>', '</em></strong>');
	ApplyInlineMarker(Result, '**', '<strong>', '</strong>');
	ApplyInlineMarker(Result, '~~', '<del>', '</del>');
	ApplyInlineMarker(Result, '*', '<em>', '</em>');
	RestoreInlineCode(Result, LPlaceholders);
end;

/// <summary>
///   Processes a single prose section (non-code-block text).
///   Splits into paragraphs on double newlines, applies inline formatting,
///   wraps in p tags, converts single newlines to br.
/// </summary>
function ProcessProse(const AText: string): string;
var
	LParagraphs: TArray<string>;
	I: Integer;
	LPara: string;
	LSB: TStringBuilder;
begin
	if AText = '' then
		Exit('');

	// Line endings already normalized by MarkdownToHtml before calling this function
	// Split on double newlines into paragraphs
	LParagraphs := SplitString(AText, #10#10);

	LSB := TStringBuilder.Create;
	try
		for I := 0 to High(LParagraphs) do
		begin
			LPara := LParagraphs[I];

			// Skip empty paragraphs
			if Trim(LPara) = '' then
				Continue;

			LPara := FormatInline(LPara);

			// Single newlines become <br>
			LPara := StringReplace(LPara, #10, '<br>', [rfReplaceAll]);

			LSB.Append('<p>').Append(LPara).Append('</p>');
		end;
		Result := LSB.ToString;
	finally
		LSB.Free;
	end;
end;

function MarkdownToHtml(const AText: string): string;
var
	LNormalized: string;
	LLines: TArray<string>;
	I: Integer;
	LInCodeBlock: Boolean;
	LCodeLang: string;
	LResult, LCodeContent, LProseAccum: TStringBuilder;
	LLine, LTrimmed: string;
	LLevel: Integer;
	LCodeStr: string;
begin
	if AText = '' then
		Exit('');

	// Normalize line endings to LF
	LNormalized := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
	LNormalized := StringReplace(LNormalized, #13, #10, [rfReplaceAll]);

	LLines := SplitString(LNormalized, #10);
	LResult := TStringBuilder.Create;
	LCodeContent := TStringBuilder.Create;
	LProseAccum := TStringBuilder.Create;
	try
		LInCodeBlock := False;
		LCodeLang := '';

		for I := 0 to High(LLines) do
		begin
			LLine := LLines[I];
			LTrimmed := TrimLeft(LLine);

			// Check for code fence (``` at start of line, possibly with leading whitespace)
			if (Length(LTrimmed) >= 3) and (Copy(LTrimmed, 1, 3) = '```') then
			begin
				if not LInCodeBlock then
				begin
					// Opening fence -- flush accumulated prose
					if LProseAccum.Length > 0 then
					begin
						LResult.Append(ProcessProse(LProseAccum.ToString));
						LProseAccum.Clear;
					end;
					LInCodeBlock := True;
					LCodeLang := Trim(Copy(LTrimmed, 4, MaxInt));
					LCodeContent.Clear;
				end
				else
				begin
					// Closing fence -- emit code block
					LCodeStr := LCodeContent.ToString;
					// Remove trailing LF if present
					if (LCodeStr <> '') and (LCodeStr[Length(LCodeStr)] = #10) then
						LCodeStr := Copy(LCodeStr, 1, Length(LCodeStr) - 1);

					if LCodeLang <> '' then
						LResult.Append('<pre><code class="language-')
							.Append(HtmlEscape(LCodeLang))
							.Append('">')
							.Append(HtmlEscape(LCodeStr))
							.Append('</code></pre>')
					else
						LResult.Append('<pre><code>')
							.Append(HtmlEscape(LCodeStr))
							.Append('</code></pre>');
					LInCodeBlock := False;
					LCodeLang := '';
					LCodeContent.Clear;
				end;
				Continue;
			end;

			if LInCodeBlock then
			begin
				// Accumulate code content with original line endings
				LCodeContent.Append(LLine).Append(#10);
				Continue;
			end;

			// Check for ATX heading (# through ######, must be followed by a space)
			if (Length(LTrimmed) >= 2) and (LTrimmed[1] = '#') then
			begin
				LLevel := 0;
				while (LLevel < Length(LTrimmed)) and (LTrimmed[LLevel + 1] = '#') do
					Inc(LLevel);
				if (LLevel <= 6) and (LLevel < Length(LTrimmed)) and (LTrimmed[LLevel + 1] = ' ') then
				begin
					// Flush accumulated prose
					if LProseAccum.Length > 0 then
					begin
						LResult.Append(ProcessProse(LProseAccum.ToString));
						LProseAccum.Clear;
					end;
					LResult.Append('<h').Append(LLevel).Append('>')
						.Append(FormatInline(Trim(Copy(LTrimmed, LLevel + 2, MaxInt))))
						.Append('</h').Append(LLevel).Append('>');
					Continue;
				end;
			end;

			// Accumulate prose lines
			if LProseAccum.Length > 0 then
				LProseAccum.Append(#10);
			LProseAccum.Append(LLine);
		end;

		// Handle unclosed code block (treat as prose)
		if LInCodeBlock then
			LProseAccum.Append(#10).Append('```').Append(LCodeLang)
				.Append(#10).Append(LCodeContent.ToString);

		// Flush remaining prose
		if LProseAccum.Length > 0 then
			LResult.Append(ProcessProse(LProseAccum.ToString));

		Result := LResult.ToString;
	finally
		LProseAccum.Free;
		LCodeContent.Free;
		LResult.Free;
	end;
end;

end.
