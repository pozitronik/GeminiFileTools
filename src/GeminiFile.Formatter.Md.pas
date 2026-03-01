/// <summary>
///   Markdown formatter for Gemini conversations.
///   Produces Markdown with headings, image links, and collapsible thinking blocks.
///   Supports optional block combining for consecutive same-kind chunks.
/// </summary>
unit GeminiFile.Formatter.Md;

interface

uses
	System.SysUtils,
	System.Classes,
	System.IOUtils,
	System.Math,
	System.Generics.Collections,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.Formatter.Intf;

type
	/// <summary>
	///   Formats a Gemini conversation as Markdown.
	/// </summary>
	TGeminiMarkdownFormatter = class(TInterfacedObject, IGeminiFormatter)
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
		///   Writes the formatted conversation to the output stream as UTF-8 Markdown.
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

{ TGeminiMarkdownFormatter }

constructor TGeminiMarkdownFormatter.Create;
begin
	inherited Create;
	FHideEmptyBlocks := True;
	FCombineBlocks := False;
end;

procedure TGeminiMarkdownFormatter.FormatToStream(
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
	LMeta, LSummary: string;
	I: Integer;
	LFirstContent: Boolean;
	LSubBlockIndex: Integer;
	LAnyResource: Boolean;
begin
	LFmt := TFormatSettings.Invariant;
	LPendingRemoteCount := 0;

	// Title
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

	// System instruction
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

	// Build groups
	LGroups := GroupConsecutiveChunks(AChunks, FCombineBlocks);

	// Iterate groups
	for I := 0 to High(LGroups) do
	begin
		LGroup := LGroups[I];

		if LGroup.Kind = gkThinking then
		begin
			// Thinking group -- one <details> block with combined summary
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
				LSummary := LSummary + ' (' + FormatCreateTime(LGroup.FirstCreateTime) + ', with attachment)'
			else if LGroup.FirstCreateTime > 0 then
				LSummary := LSummary + ' (' + FormatCreateTime(LGroup.FirstCreateTime) + ')'
			else if LAnyResource then
				LSummary := LSummary + ' (with attachment)';
			StreamWriteLn(AOutput, '<details><summary>' + LSummary + '</summary>');
			StreamWriteLn(AOutput);
			for LSubBlockIndex := 0 to High(LGroup.Chunks) do
			begin
				LChunk := LGroup.Chunks[LSubBlockIndex];
				// Blank line separator between sub-blocks
				if LSubBlockIndex > 0 then
					StreamWriteLn(AOutput);
				LText := LChunk.GetThinkingText;
				if LText = '' then
					LText := LChunk.Text;
				StreamWriteLn(AOutput, LText);
				// Resource image link
				if FindResourceForChunk(AResources, LChunk.Index, LResInfo) then
				begin
					StreamWriteLn(AOutput);
					StreamWriteLn(AOutput, '![' + TPath.GetFileName(LResInfo.FileName) + '](' + LResInfo.FileName + ')');
				end;
			end;
			StreamWriteLn(AOutput);
			StreamWriteLn(AOutput, '</details>');
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
					StreamWriteLn(AOutput, '*' + IntToStr(LPendingRemoteCount) + ' remote attachment(s)*');
					StreamWriteLn(AOutput);
					LPendingRemoteCount := 0;
				end;

				// Emit role heading lazily on first visible sub-block
				if LFirstContent then
				begin
					case LGroup.Kind of
						gkUser: StreamWriteLn(AOutput, '### User');
						gkModel: StreamWriteLn(AOutput, '### Model');
					end;
					StreamWriteLn(AOutput);

					// Timestamp
					if LGroup.FirstCreateTime > 0 then
					begin
						StreamWriteLn(AOutput, '*' + FormatCreateTime(LGroup.FirstCreateTime) + '*');
						StreamWriteLn(AOutput);
					end;

					// Token count (shown when non-zero)
					if LGroup.TotalTokenCount > 0 then
					begin
						StreamWriteLn(AOutput, '*(' + IntToStr(LGroup.TotalTokenCount) + ' tokens)*');
						StreamWriteLn(AOutput);
					end;

					LFirstContent := False;
				end
				else
				begin
					// Sub-block separator (Markdown horizontal rule)
					StreamWriteLn(AOutput);
					StreamWriteLn(AOutput, '---');
					StreamWriteLn(AOutput);
				end;

				// Part-level thinking
				LThinking := LChunk.GetThinkingText;
				if LThinking <> '' then
				begin
					StreamWriteLn(AOutput, '<details><summary>Thinking</summary>');
					StreamWriteLn(AOutput);
					StreamWriteLn(AOutput, LThinking);
					StreamWriteLn(AOutput);
					StreamWriteLn(AOutput, '</details>');
					StreamWriteLn(AOutput);
				end;

				// Main text
				if LText <> '' then
					StreamWriteLn(AOutput, LText);

				// Resource image link
				if LHasResource then
				begin
					StreamWriteLn(AOutput);
					StreamWriteLn(AOutput, '![' + TPath.GetFileName(LResInfo.FileName) + '](' + LResInfo.FileName + ')');
				end;
			end;
		end;

		StreamWriteLn(AOutput);
	end;

	// Trailing remote attachment hint (empty blocks at end of conversation)
	if LPendingRemoteCount > 0 then
	begin
		StreamWriteLn(AOutput, '*' + IntToStr(LPendingRemoteCount) + ' remote attachment(s)*');
		StreamWriteLn(AOutput);
	end;
end;

end.
