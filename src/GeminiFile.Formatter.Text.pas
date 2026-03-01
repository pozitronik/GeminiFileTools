/// <summary>
///   Plain text formatter for Gemini conversations.
///   Produces readable text with role labels, token counts, thinking blocks,
///   and resource indicators. Supports optional block combining for
///   consecutive same-kind chunks.
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
		FCombineBlocks: Boolean;
	public
		constructor Create;
		/// <summary>When True, empty blocks are skipped and remote attachment hints shown instead.</summary>
		property HideEmptyBlocks: Boolean read FHideEmptyBlocks write FHideEmptyBlocks;
		/// <summary>When True, consecutive same-kind chunks are merged into a single visual block.</summary>
		property CombineBlocks: Boolean read FCombineBlocks write FCombineBlocks;
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

uses
	GeminiFile.Formatter.Utils,
	GeminiFile.Grouping;

{ TGeminiTextFormatter }

constructor TGeminiTextFormatter.Create;
begin
	inherited Create;
	FHideEmptyBlocks := True;
	FCombineBlocks := False;
end;

procedure TGeminiTextFormatter.FormatToStream(
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
	I: Integer;
	LFirstContent: Boolean;
	LSubBlockIndex: Integer;
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

	// Build groups
	LGroups := GroupConsecutiveChunks(AChunks, FCombineBlocks);

	// Iterate groups
	for I := 0 to High(LGroups) do
	begin
		LGroup := LGroups[I];
		LFirstContent := True;

		if LGroup.Kind = gkThinking then
		begin
			// Thinking group -- one header, then each sub-block's content
			if LGroup.FirstCreateTime > 0 then
				StreamWriteLn(AOutput, '<Thinking> ' + FormatCreateTime(LGroup.FirstCreateTime))
			else
				StreamWriteLn(AOutput, '<Thinking>');
			for LSubBlockIndex := 0 to High(LGroup.Chunks) do
			begin
				LChunk := LGroup.Chunks[LSubBlockIndex];
				// Sub-block separator
				if LSubBlockIndex > 0 then
					StreamWriteLn(AOutput, '- - -');
				LText := LChunk.GetThinkingText;
				if LText = '' then
					LText := LChunk.Text;
				StreamWriteLn(AOutput, LText);
				// Resource indicator
				if FindResourceForChunk(AResources, LChunk.Index, LResInfo) then
					StreamWriteLn(AOutput, '[Attached: ' + LResInfo.FileName +
						' (' + LResInfo.MimeType + ', ~' + FormatByteSize(LResInfo.DecodedSize) + ')]');
			end;
			StreamWriteLn(AOutput, '</Thinking>');
		end
		else
		begin
			// User/Model group -- lazy header emission for empty block handling
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

				// Emit pending remote attachment hint before first visible content
				if LFirstContent and (LPendingRemoteCount > 0) then
				begin
					StreamWriteLn(AOutput, '[' + IntToStr(LPendingRemoteCount) + ' remote attachment(s)]');
					StreamWriteLn(AOutput);
					LPendingRemoteCount := 0;
				end;

				// Emit role header lazily on first visible sub-block
				if LFirstContent then
				begin
					case LGroup.Kind of
						gkUser: StreamWrite(AOutput, '[USER]');
						gkModel: StreamWrite(AOutput, '[MODEL]');
					end;
					if LGroup.FirstCreateTime > 0 then
						StreamWrite(AOutput, ' ' + FormatCreateTime(LGroup.FirstCreateTime));
					if LGroup.TotalTokenCount > 0 then
						StreamWrite(AOutput, ' (' + IntToStr(LGroup.TotalTokenCount) + ' tokens)');
					StreamWriteLn(AOutput);
					LFirstContent := False;
				end
				else
				begin
					// Sub-block separator between visible sub-blocks
					StreamWriteLn(AOutput, '- - -');
				end;

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
		end;

		// Only emit trailing blank line if the group produced visible output
		if (LGroup.Kind = gkThinking) or (not LFirstContent) then
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
