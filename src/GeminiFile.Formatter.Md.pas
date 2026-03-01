/// <summary>
///   Markdown formatter for Gemini conversations.
///   Produces Markdown with headings, image links, and collapsible thinking blocks.
///   Overrides TGeminiFormatterBase template methods to supply Markdown output.
/// </summary>
unit GeminiFile.Formatter.Md;

interface

uses
	System.SysUtils,
	System.Classes,
	System.IOUtils,
	System.Math,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.Grouping,
	GeminiFile.Formatter.Base;

type
	/// <summary>
	///   Formats a Gemini conversation as Markdown.
	/// </summary>
	TGeminiMarkdownFormatter = class(TGeminiFormatterBase)
	protected
		procedure WriteDocumentStart(AOutput: TStream;
			ARunSettings: TGeminiRunSettings;
			const ASystemInstruction: string); override;
		procedure BeginThinkingGroup(AOutput: TStream;
			ACreateTime: TDateTime; AAnyResource: Boolean); override;
		procedure WriteThinkingSubBlock(AOutput: TStream;
			const AText: string; AHasResource: Boolean;
			const AResInfo: TFormatterResourceInfo;
			ASubIndex, ASubCount: Integer); override;
		procedure EndThinkingGroup(AOutput: TStream); override;
		procedure BeginContentGroup(AOutput: TStream;
			AKind: TChunkGroupKind; ACreateTime: TDateTime;
			ATotalTokens: Integer; APendingRemoteCount: Integer); override;
		procedure WriteContentSeparator(AOutput: TStream); override;
		procedure WritePartThinking(AOutput: TStream;
			const AThinking: string); override;
		procedure WriteContentText(AOutput: TStream;
			const AText: string); override;
		procedure WriteContentResource(AOutput: TStream;
			const AResInfo: TFormatterResourceInfo); override;
		procedure WriteRemoteHint(AOutput: TStream;
			ACount: Integer); override;
		procedure WriteGroupSpacing(AOutput: TStream;
			AKind: TChunkGroupKind;
			AHadVisibleContent: Boolean); override;
	end;

implementation

uses
	GeminiFile.Formatter.Utils;

{ TGeminiMarkdownFormatter }

procedure WriteMarkdownImage(AOutput: TStream; const AResInfo: TFormatterResourceInfo);
begin
	StreamWriteLn(AOutput, '![' + TPath.GetFileName(AResInfo.FileName) + '](' + AResInfo.FileName + ')');
end;

procedure TGeminiMarkdownFormatter.WriteDocumentStart(AOutput: TStream;
	ARunSettings: TGeminiRunSettings;
	const ASystemInstruction: string);
var
	LFmt: TFormatSettings;
	LMeta: string;
begin
	LFmt := TFormatSettings.Invariant;

	StreamWriteLn(AOutput, '# Gemini Conversation');
	StreamWriteLn(AOutput);

	// Metadata line
	LMeta := '';
	if ARunSettings.Model <> '' then
		LMeta := '**Model:** ' + ARunSettings.Model;
	if not IsNaN(ARunSettings.Temperature) then
	begin
		if LMeta <> '' then
			LMeta := LMeta + ' | ';
		LMeta := LMeta + '**Temperature:** ' + FormatFloat('0.0#', ARunSettings.Temperature, LFmt);
	end;
	if not IsNaN(ARunSettings.TopP) then
	begin
		if LMeta <> '' then
			LMeta := LMeta + ' | ';
		LMeta := LMeta + '**TopP:** ' + FormatFloat('0.0#', ARunSettings.TopP, LFmt);
	end;
	if ARunSettings.TopK >= 0 then
	begin
		if LMeta <> '' then
			LMeta := LMeta + ' | ';
		LMeta := LMeta + '**TopK:** ' + IntToStr(ARunSettings.TopK);
	end;
	if ARunSettings.MaxOutputTokens >= 0 then
	begin
		if LMeta <> '' then
			LMeta := LMeta + ' | ';
		LMeta := LMeta + '**MaxOutputTokens:** ' + IntToStr(ARunSettings.MaxOutputTokens);
	end;
	if LMeta <> '' then
	begin
		StreamWriteLn(AOutput, LMeta);
		StreamWriteLn(AOutput);
	end;

	if ASystemInstruction <> '' then
	begin
		StreamWriteLn(AOutput, '## System Instruction');
		StreamWriteLn(AOutput);
		StreamWriteLn(AOutput, ASystemInstruction);
		StreamWriteLn(AOutput);
	end;

	StreamWriteLn(AOutput, '---');
	StreamWriteLn(AOutput);
	StreamWriteLn(AOutput, '## Conversation');
	StreamWriteLn(AOutput);
end;

procedure TGeminiMarkdownFormatter.BeginThinkingGroup(AOutput: TStream;
	ACreateTime: TDateTime; AAnyResource: Boolean);
var
	LSummary: string;
begin
	LSummary := 'Thinking';
	if (ACreateTime > 0) and AAnyResource then
		LSummary := LSummary + ' (' + FormatCreateTime(ACreateTime) + ', with attachment)'
	else if ACreateTime > 0 then
		LSummary := LSummary + ' (' + FormatCreateTime(ACreateTime) + ')'
	else if AAnyResource then
		LSummary := LSummary + ' (with attachment)';
	StreamWriteLn(AOutput, '<details><summary>' + LSummary + '</summary>');
	StreamWriteLn(AOutput);
end;

procedure TGeminiMarkdownFormatter.WriteThinkingSubBlock(AOutput: TStream;
	const AText: string; AHasResource: Boolean;
	const AResInfo: TFormatterResourceInfo;
	ASubIndex, ASubCount: Integer);
begin
	if ASubIndex > 0 then
		StreamWriteLn(AOutput);
	StreamWriteLn(AOutput, AText);
	if AHasResource then
	begin
		StreamWriteLn(AOutput);
		WriteMarkdownImage(AOutput, AResInfo);
	end;
end;

procedure TGeminiMarkdownFormatter.EndThinkingGroup(AOutput: TStream);
begin
	StreamWriteLn(AOutput);
	StreamWriteLn(AOutput, '</details>');
end;

procedure TGeminiMarkdownFormatter.BeginContentGroup(AOutput: TStream;
	AKind: TChunkGroupKind; ACreateTime: TDateTime;
	ATotalTokens: Integer; APendingRemoteCount: Integer);
begin
	if APendingRemoteCount > 0 then
	begin
		StreamWriteLn(AOutput, '*' + IntToStr(APendingRemoteCount) + ' remote attachment(s)*');
		StreamWriteLn(AOutput);
	end;

	case AKind of
		gkUser: StreamWriteLn(AOutput, '### User');
		gkModel: StreamWriteLn(AOutput, '### Model');
	end;
	StreamWriteLn(AOutput);

	if ACreateTime > 0 then
	begin
		StreamWriteLn(AOutput, '*' + FormatCreateTime(ACreateTime) + '*');
		StreamWriteLn(AOutput);
	end;

	if ATotalTokens > 0 then
	begin
		StreamWriteLn(AOutput, '*(' + IntToStr(ATotalTokens) + ' tokens)*');
		StreamWriteLn(AOutput);
	end;
end;

procedure TGeminiMarkdownFormatter.WriteContentSeparator(AOutput: TStream);
begin
	StreamWriteLn(AOutput);
	StreamWriteLn(AOutput, '---');
	StreamWriteLn(AOutput);
end;

procedure TGeminiMarkdownFormatter.WritePartThinking(AOutput: TStream;
	const AThinking: string);
begin
	StreamWriteLn(AOutput, '<details><summary>Thinking</summary>');
	StreamWriteLn(AOutput);
	StreamWriteLn(AOutput, AThinking);
	StreamWriteLn(AOutput);
	StreamWriteLn(AOutput, '</details>');
	StreamWriteLn(AOutput);
end;

procedure TGeminiMarkdownFormatter.WriteContentText(AOutput: TStream;
	const AText: string);
begin
	StreamWriteLn(AOutput, AText);
end;

procedure TGeminiMarkdownFormatter.WriteContentResource(AOutput: TStream;
	const AResInfo: TFormatterResourceInfo);
begin
	StreamWriteLn(AOutput);
	WriteMarkdownImage(AOutput, AResInfo);
end;

procedure TGeminiMarkdownFormatter.WriteRemoteHint(AOutput: TStream;
	ACount: Integer);
begin
	StreamWriteLn(AOutput, '*' + IntToStr(ACount) + ' remote attachment(s)*');
	StreamWriteLn(AOutput);
end;

procedure TGeminiMarkdownFormatter.WriteGroupSpacing(AOutput: TStream;
	AKind: TChunkGroupKind; AHadVisibleContent: Boolean);
begin
	// Markdown always emits a blank line between groups
	StreamWriteLn(AOutput);
end;

end.
