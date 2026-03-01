/// <summary>
///   Plain text formatter for Gemini conversations.
///   Produces readable text with role labels, token counts, thinking blocks,
///   and resource indicators.
/// </summary>
unit GeminiFile.Formatter.Text;

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
	///   Formats a Gemini conversation as plain text.
	/// </summary>
	TGeminiTextFormatter = class
	private
		FHideEmptyBlocks: Boolean;
	public
		constructor Create;
		/// <summary>When True, empty blocks are skipped and remote attachment hints shown instead.</summary>
		property HideEmptyBlocks: Boolean read FHideEmptyBlocks write FHideEmptyBlocks;
		/// <summary>
		///   Writes the formatted conversation to the output stream as UTF-8 text.
		/// </summary>
		/// <param name="AOutput">Target stream.</param>
		/// <param name="AChunks">Conversation chunks in order.</param>
		/// <param name="ASystemInstruction">System instruction text. Empty if none.</param>
		/// <param name="ARunSettings">Model run settings.</param>
		/// <param name="AResources">Resource info records for link generation.</param>
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

{ TGeminiTextFormatter }

constructor TGeminiTextFormatter.Create;
begin
	inherited Create;
	FHideEmptyBlocks := True;
end;

procedure TGeminiTextFormatter.FormatToStream(
	AOutput: TStream;
	AChunks: TObjectList<TGeminiChunk>;
	const ASystemInstruction: string;
	ARunSettings: TGeminiRunSettings;
	const AResources: TArray<TFormatterResourceInfo>);
var
	LChunk: TGeminiChunk;
	LText, LThinking: string;
	LResInfo: TFormatterResourceInfo;
	LHasResource: Boolean;
	LPendingRemoteCount: Integer;
	LFmt: TFormatSettings;
begin
	LFmt := TFormatSettings.Invariant;
	LPendingRemoteCount := 0;

	// Header
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

	// System instruction
	if ASystemInstruction <> '' then
	begin
		StreamWriteLn(AOutput, '--- System Instruction ---');
		StreamWriteLn(AOutput, ASystemInstruction);
		StreamWriteLn(AOutput);
	end;

	StreamWriteLn(AOutput, '--- Conversation ---');
	StreamWriteLn(AOutput);

	// Chunks
	for LChunk in AChunks do
	begin
		if LChunk.IsThought then
		begin
			// Pure thinking chunk -- no role header
			LText := LChunk.GetThinkingText;
			if LText = '' then
				LText := LChunk.Text;
			if LChunk.CreateTime > 0 then
				StreamWriteLn(AOutput, '<Thinking> ' + FormatCreateTime(LChunk.CreateTime))
			else
				StreamWriteLn(AOutput, '<Thinking>');
			StreamWriteLn(AOutput, LText);
			StreamWriteLn(AOutput, '</Thinking>');
			// Resource indicator for thinking chunks with attachments
			if FindResourceForChunk(AResources, LChunk.Index, LResInfo) then
				StreamWriteLn(AOutput, '[Attached: ' + LResInfo.FileName +
					' (' + LResInfo.MimeType + ', ~' + FormatByteSize(LResInfo.DecodedSize) + ')]');
		end
		else
		begin
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

			// Emit pending remote attachment hint
			if LPendingRemoteCount > 0 then
			begin
				StreamWriteLn(AOutput, '[' + IntToStr(LPendingRemoteCount) + ' remote attachment(s)]');
				StreamWriteLn(AOutput);
				LPendingRemoteCount := 0;
			end;

			// Role header
			case LChunk.Role of
				grUser: StreamWrite(AOutput, '[USER]');
				grModel: StreamWrite(AOutput, '[MODEL]');
			end;
			if LChunk.CreateTime > 0 then
				StreamWrite(AOutput, ' ' + FormatCreateTime(LChunk.CreateTime));
			if LChunk.TokenCount > 0 then
				StreamWrite(AOutput, ' (' + IntToStr(LChunk.TokenCount) + ' tokens)');
			StreamWriteLn(AOutput);

			// Part-level thinking (model chunks with mixed parts)
			LThinking := LChunk.GetThinkingText;
			if LThinking <> '' then
			begin
				StreamWriteLn(AOutput, '<Thinking>');
				StreamWriteLn(AOutput, LThinking);
				StreamWriteLn(AOutput, '</Thinking>');
				StreamWriteLn(AOutput);
			end;

			// Main text
			if LText <> '' then
				StreamWriteLn(AOutput, LText);

			// Resource indicator
			if LHasResource then
				StreamWriteLn(AOutput, '[Attached: ' + LResInfo.FileName +
					' (' + LResInfo.MimeType + ', ~' + FormatByteSize(LResInfo.DecodedSize) + ')]');
		end;

		StreamWriteLn(AOutput);
	end;

	// Trailing remote attachment hint (empty blocks at end of conversation)
	if LPendingRemoteCount > 0 then
	begin
		StreamWriteLn(AOutput, '[' + IntToStr(LPendingRemoteCount) + ' remote attachment(s)]');
		StreamWriteLn(AOutput);
	end;
end;

end.
