/// <summary>
///   Plain text formatter for Gemini conversations.
///   Produces readable text with role labels, token counts, thinking blocks,
///   and resource indicators. Overrides TGeminiFormatterBase template methods
///   to supply plain text output.
/// </summary>
unit GeminiFile.Formatter.Text;

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
	///   Formats a Gemini conversation as plain text.
	/// </summary>
	TGeminiTextFormatter = class(TGeminiFormatterBase)
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

{ TGeminiTextFormatter }

procedure TGeminiTextFormatter.WriteDocumentStart(AOutput: TStream;
	ARunSettings: TGeminiRunSettings;
	const ASystemInstruction: string);
var
	LFmt: TFormatSettings;
begin
	LFmt := TFormatSettings.Invariant;

	StreamWriteLn(AOutput, '=== Gemini Conversation ===');
	if ARunSettings.Model <> '' then
		StreamWriteLn(AOutput, 'Model: ' + ARunSettings.Model);
	if not IsNaN(ARunSettings.Temperature) then
		StreamWriteLn(AOutput, 'Temperature: ' + FormatFloat('0.0#', ARunSettings.Temperature, LFmt));
	if not IsNaN(ARunSettings.TopP) then
		StreamWriteLn(AOutput, 'TopP: ' + FormatFloat('0.0#', ARunSettings.TopP, LFmt));
	if ARunSettings.TopK >= 0 then
		StreamWriteLn(AOutput, 'TopK: ' + IntToStr(ARunSettings.TopK));
	if ARunSettings.MaxOutputTokens >= 0 then
		StreamWriteLn(AOutput, 'MaxOutputTokens: ' + IntToStr(ARunSettings.MaxOutputTokens));
	StreamWriteLn(AOutput);

	if ASystemInstruction <> '' then
	begin
		StreamWriteLn(AOutput, '--- System Instruction ---');
		StreamWriteLn(AOutput, ASystemInstruction);
		StreamWriteLn(AOutput);
	end;

	StreamWriteLn(AOutput, '--- Conversation ---');
	StreamWriteLn(AOutput);
end;

procedure TGeminiTextFormatter.BeginThinkingGroup(AOutput: TStream;
	ACreateTime: TDateTime; AAnyResource: Boolean);
begin
	if ACreateTime > 0 then
		StreamWriteLn(AOutput, '<Thinking> ' + FormatCreateTime(ACreateTime))
	else
		StreamWriteLn(AOutput, '<Thinking>');
end;

procedure TGeminiTextFormatter.WriteThinkingSubBlock(AOutput: TStream;
	const AText: string; AHasResource: Boolean;
	const AResInfo: TFormatterResourceInfo;
	ASubIndex, ASubCount: Integer);
begin
	if ASubIndex > 0 then
		StreamWriteLn(AOutput, '- - -');
	StreamWriteLn(AOutput, AText);
	if AHasResource then
		StreamWriteLn(AOutput, '[Attached: ' + AResInfo.FileName +
			' (' + AResInfo.MimeType + ', ~' + FormatByteSize(AResInfo.DecodedSize) + ')]');
end;

procedure TGeminiTextFormatter.EndThinkingGroup(AOutput: TStream);
begin
	StreamWriteLn(AOutput, '</Thinking>');
end;

procedure TGeminiTextFormatter.BeginContentGroup(AOutput: TStream;
	AKind: TChunkGroupKind; ACreateTime: TDateTime;
	ATotalTokens: Integer; APendingRemoteCount: Integer);
begin
	if APendingRemoteCount > 0 then
	begin
		StreamWriteLn(AOutput, '[' + IntToStr(APendingRemoteCount) + ' remote attachment(s)]');
		StreamWriteLn(AOutput);
	end;

	case AKind of
		gkUser: StreamWrite(AOutput, '[USER]');
		gkModel: StreamWrite(AOutput, '[MODEL]');
	end;
	if ACreateTime > 0 then
		StreamWrite(AOutput, ' ' + FormatCreateTime(ACreateTime));
	if ATotalTokens > 0 then
		StreamWrite(AOutput, ' (' + IntToStr(ATotalTokens) + ' tokens)');
	StreamWriteLn(AOutput);
end;

procedure TGeminiTextFormatter.WriteContentSeparator(AOutput: TStream);
begin
	StreamWriteLn(AOutput, '- - -');
end;

procedure TGeminiTextFormatter.WritePartThinking(AOutput: TStream;
	const AThinking: string);
begin
	StreamWriteLn(AOutput, '<Thinking>');
	StreamWriteLn(AOutput, AThinking);
	StreamWriteLn(AOutput, '</Thinking>');
	StreamWriteLn(AOutput);
end;

procedure TGeminiTextFormatter.WriteContentText(AOutput: TStream;
	const AText: string);
begin
	StreamWriteLn(AOutput, AText);
end;

procedure TGeminiTextFormatter.WriteContentResource(AOutput: TStream;
	const AResInfo: TFormatterResourceInfo);
begin
	StreamWriteLn(AOutput, '[Attached: ' + AResInfo.FileName +
		' (' + AResInfo.MimeType + ', ~' + FormatByteSize(AResInfo.DecodedSize) + ')]');
end;

procedure TGeminiTextFormatter.WriteRemoteHint(AOutput: TStream;
	ACount: Integer);
begin
	StreamWriteLn(AOutput, '[' + IntToStr(ACount) + ' remote attachment(s)]');
	StreamWriteLn(AOutput);
end;

procedure TGeminiTextFormatter.WriteGroupSpacing(AOutput: TStream;
	AKind: TChunkGroupKind; AHadVisibleContent: Boolean);
begin
	if (AKind = gkThinking) or AHadVisibleContent then
		StreamWriteLn(AOutput);
end;

end.
