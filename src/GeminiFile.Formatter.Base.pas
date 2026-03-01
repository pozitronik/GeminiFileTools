/// <summary>
///   Abstract base class for conversation formatters.
///   Implements the Template Method pattern: FormatToStream contains all shared
///   iteration/decision logic (grouping, empty block detection, lazy header
///   emission, remote attachment counting), while concrete subclasses supply
///   format-specific output through protected virtual methods.
/// </summary>
unit GeminiFile.Formatter.Base;

interface

uses
	System.SysUtils,
	System.Classes,
	System.Generics.Collections,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.Grouping,
	GeminiFile.Formatter.Intf;

type
	/// <summary>
	///   Abstract base for all conversation formatters.
	///   Subclasses override 11 abstract methods and optionally 4 virtual
	///   methods with empty defaults to produce format-specific output.
	/// </summary>
	TGeminiFormatterBase = class(TInterfacedObject, IGeminiFormatter)
	private
		FHideEmptyBlocks: Boolean;
		FCombineBlocks: Boolean;
	protected
		// -- Abstract methods (11) -- every formatter must override -----------

		/// <summary>Writes document header, metadata, system instruction, and conversation heading.</summary>
		procedure WriteDocumentStart(AOutput: TStream;
			ARunSettings: TGeminiRunSettings;
			const ASystemInstruction: string); virtual; abstract;

		/// <summary>Opens a thinking group (header/summary with optional timestamp and resource hint).</summary>
		procedure BeginThinkingGroup(AOutput: TStream;
			ACreateTime: TDateTime; AAnyResource: Boolean); virtual; abstract;

		/// <summary>Writes one sub-block inside a thinking group.</summary>
		/// <param name="AText">Thinking text (already extracted, with fallback to main text).</param>
		/// <param name="AHasResource">Whether this sub-block has an embedded resource.</param>
		/// <param name="AResInfo">Resource info (valid only when AHasResource is True).</param>
		/// <param name="ASubIndex">Zero-based index of the sub-block within the thinking group.</param>
		/// <param name="ASubCount">Total number of sub-blocks in the thinking group.</param>
		procedure WriteThinkingSubBlock(AOutput: TStream;
			const AText: string; AHasResource: Boolean;
			const AResInfo: TFormatterResourceInfo;
			ASubIndex, ASubCount: Integer); virtual; abstract;

		/// <summary>Closes a thinking group (footer tag/element).</summary>
		procedure EndThinkingGroup(AOutput: TStream); virtual; abstract;

		/// <summary>Opens a user/model content group with role header, timestamp, token count.</summary>
		/// <param name="AKind">Group kind (gkUser or gkModel).</param>
		/// <param name="ACreateTime">First non-zero timestamp in the group.</param>
		/// <param name="ATotalTokens">Sum of token counts across group chunks.</param>
		/// <param name="APendingRemoteCount">Number of skipped remote attachments preceding this group.</param>
		procedure BeginContentGroup(AOutput: TStream;
			AKind: TChunkGroupKind; ACreateTime: TDateTime;
			ATotalTokens: Integer; APendingRemoteCount: Integer); virtual; abstract;

		/// <summary>Writes a separator between visible sub-blocks within a content group.</summary>
		procedure WriteContentSeparator(AOutput: TStream); virtual; abstract;

		/// <summary>Writes part-level thinking text within a content sub-block.</summary>
		procedure WritePartThinking(AOutput: TStream;
			const AThinking: string); virtual; abstract;

		/// <summary>Writes the main text content of a sub-block.</summary>
		procedure WriteContentText(AOutput: TStream;
			const AText: string); virtual; abstract;

		/// <summary>Writes a resource indicator/image for a content sub-block.</summary>
		procedure WriteContentResource(AOutput: TStream;
			const AResInfo: TFormatterResourceInfo); virtual; abstract;

		/// <summary>Writes a trailing remote attachment hint (for skipped blocks at conversation end).</summary>
		procedure WriteRemoteHint(AOutput: TStream;
			ACount: Integer); virtual; abstract;

		/// <summary>Writes spacing between groups (blank lines, etc.).</summary>
		/// <param name="AKind">The kind of group that just ended.</param>
		/// <param name="AHadVisibleContent">Whether the group produced any visible output.</param>
		procedure WriteGroupSpacing(AOutput: TStream;
			AKind: TChunkGroupKind;
			AHadVisibleContent: Boolean); virtual; abstract;

		// -- Virtual methods with empty defaults (4) -- only HTML overrides ---

		/// <summary>Writes document footer (controls, scripts, closing tags). Default: no-op.</summary>
		procedure WriteDocumentEnd(AOutput: TStream); virtual;

		/// <summary>Closes a content group container. Default: no-op.</summary>
		procedure EndContentGroup(AOutput: TStream); virtual;

		/// <summary>Opens a sub-block wrapper when combined layout is active. Default: no-op.</summary>
		procedure BeginContentSubBlock(AOutput: TStream;
			AUseCombinedLayout: Boolean); virtual;

		/// <summary>Closes a sub-block wrapper when combined layout is active. Default: no-op.</summary>
		procedure EndContentSubBlock(AOutput: TStream;
			AUseCombinedLayout: Boolean); virtual;
	public
		constructor Create;
		/// <summary>When True, empty blocks are skipped and remote attachment hints shown instead.</summary>
		property HideEmptyBlocks: Boolean read FHideEmptyBlocks write FHideEmptyBlocks;
		/// <summary>When True, consecutive same-kind chunks are merged into a single visual block.</summary>
		property CombineBlocks: Boolean read FCombineBlocks write FCombineBlocks;
		/// <summary>
		///   Template method: iterates chunk groups, delegates format-specific
		///   output to virtual methods. Do not override in subclasses.
		/// </summary>
		procedure FormatToStream(
			AOutput: TStream;
			AChunks: TObjectList<TGeminiChunk>;
			const ASystemInstruction: string;
			ARunSettings: TGeminiRunSettings;
			const AResources: TArray<TFormatterResourceInfo>
		);
	end;

implementation

{ TGeminiFormatterBase }

constructor TGeminiFormatterBase.Create;
begin
	inherited Create;
	FHideEmptyBlocks := True;
	FCombineBlocks := False;
end;

procedure TGeminiFormatterBase.WriteDocumentEnd(AOutput: TStream);
begin
	// Default: no-op. HTML overrides to write controls, JS, closing tags.
end;

procedure TGeminiFormatterBase.EndContentGroup(AOutput: TStream);
begin
	// Default: no-op. HTML overrides to close the message container div.
end;

procedure TGeminiFormatterBase.BeginContentSubBlock(AOutput: TStream;
	AUseCombinedLayout: Boolean);
begin
	// Default: no-op. HTML overrides to open combined-part div.
end;

procedure TGeminiFormatterBase.EndContentSubBlock(AOutput: TStream;
	AUseCombinedLayout: Boolean);
begin
	// Default: no-op. HTML overrides to close combined-part div.
end;

procedure TGeminiFormatterBase.FormatToStream(
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
	I: Integer;
	LFirstContent: Boolean;
	LSubBlockIndex: Integer;
	LAnyResource: Boolean;
	LUseCombinedLayout: Boolean;
begin
	LPendingRemoteCount := 0;

	WriteDocumentStart(AOutput, ARunSettings, ASystemInstruction);

	LGroups := GroupConsecutiveChunks(AChunks, FCombineBlocks);

	for I := 0 to High(LGroups) do
	begin
		LGroup := LGroups[I];

		if LGroup.Kind = gkThinking then
		begin
			// Pre-scan for resources (used by summary text in MD/HTML)
			LAnyResource := False;
			for LSubBlockIndex := 0 to High(LGroup.Chunks) do
				if FindResourceForChunk(AResources, LGroup.Chunks[LSubBlockIndex].Index, LResInfo) then
				begin
					LAnyResource := True;
					Break;
				end;

			BeginThinkingGroup(AOutput, LGroup.FirstCreateTime, LAnyResource);

			for LSubBlockIndex := 0 to High(LGroup.Chunks) do
			begin
				LChunk := LGroup.Chunks[LSubBlockIndex];
				LText := LChunk.GetThinkingText;
				if LText = '' then
					LText := LChunk.Text;
				LHasResource := FindResourceForChunk(AResources, LChunk.Index, LResInfo);
				WriteThinkingSubBlock(AOutput, LText, LHasResource, LResInfo,
					LSubBlockIndex, Length(LGroup.Chunks));
			end;

			EndThinkingGroup(AOutput);
			WriteGroupSpacing(AOutput, gkThinking, True);
		end
		else
		begin
			LFirstContent := True;
			LUseCombinedLayout := Length(LGroup.Chunks) > 1;

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

				// Emit role header lazily on first visible sub-block
				if LFirstContent then
				begin
					BeginContentGroup(AOutput, LGroup.Kind, LGroup.FirstCreateTime,
						LGroup.TotalTokenCount, LPendingRemoteCount);
					LPendingRemoteCount := 0;
					LFirstContent := False;
				end
				else
					WriteContentSeparator(AOutput);

				BeginContentSubBlock(AOutput, LUseCombinedLayout);

				// Part-level thinking (model chunks with mixed parts)
				LThinking := LChunk.GetThinkingText;
				if LThinking <> '' then
					WritePartThinking(AOutput, LThinking);

				// Main text
				if LText <> '' then
					WriteContentText(AOutput, LText);

				// Resource indicator
				if LHasResource then
					WriteContentResource(AOutput, LResInfo);

				EndContentSubBlock(AOutput, LUseCombinedLayout);
			end;

			// Close content group container if it was opened
			if not LFirstContent then
				EndContentGroup(AOutput);

			WriteGroupSpacing(AOutput, LGroup.Kind, not LFirstContent);
		end;
	end;

	// Trailing remote attachment hint (empty blocks at end of conversation)
	if LPendingRemoteCount > 0 then
		WriteRemoteHint(AOutput, LPendingRemoteCount);

	WriteDocumentEnd(AOutput);
end;

end.
