/// <summary>
///   Markdown formatter for Gemini conversations.
///   Produces Markdown with headings, image links, and collapsible thinking blocks.
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
	GeminiFile.Model;

type
	/// <summary>
	///   Formats a Gemini conversation as Markdown.
	/// </summary>
	TGeminiMarkdownFormatter = class
	private
		FHideEmptyBlocks: Boolean;
	public
		constructor Create;
		/// <summary>When True, empty blocks are skipped and remote attachment hints shown instead.</summary>
		property HideEmptyBlocks: Boolean read FHideEmptyBlocks write FHideEmptyBlocks;
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

{ TGeminiMarkdownFormatter }

constructor TGeminiMarkdownFormatter.Create;
begin
	inherited Create;
	FHideEmptyBlocks := True;
end;

procedure TGeminiMarkdownFormatter.FormatToStream(
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
	LMeta, LSummary: string;
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

	// Chunks
	for LChunk in AChunks do
	begin
		if LChunk.IsThought then
		begin
			// Pure thinking chunk -- collapsible block with optional time/attachment indicators
			LText := LChunk.GetThinkingText;
			if LText = '' then
				LText := LChunk.Text;
			LSummary := 'Thinking';
			if (LChunk.CreateTime > 0) and FindResourceForChunk(AResources, LChunk.Index, LResInfo) then
				LSummary := LSummary + ' (' + FormatCreateTime(LChunk.CreateTime) + ', with attachment)'
			else if LChunk.CreateTime > 0 then
				LSummary := LSummary + ' (' + FormatCreateTime(LChunk.CreateTime) + ')'
			else if FindResourceForChunk(AResources, LChunk.Index, LResInfo) then
				LSummary := LSummary + ' (with attachment)';
			StreamWriteLn(AOutput, '<details><summary>' + LSummary + '</summary>');
			StreamWriteLn(AOutput);
			StreamWriteLn(AOutput, LText);
			StreamWriteLn(AOutput);
			if FindResourceForChunk(AResources, LChunk.Index, LResInfo) then
				StreamWriteLn(AOutput, '![' + TPath.GetFileName(LResInfo.FileName) + '](' + LResInfo.FileName + ')');
			StreamWriteLn(AOutput, '</details>');
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
				StreamWriteLn(AOutput, '*' + IntToStr(LPendingRemoteCount) + ' remote attachment(s)*');
				StreamWriteLn(AOutput);
				LPendingRemoteCount := 0;
			end;

			// Role heading
			case LChunk.Role of
				grUser: StreamWriteLn(AOutput, '### User');
				grModel: StreamWriteLn(AOutput, '### Model');
			end;
			StreamWriteLn(AOutput);

			// Timestamp
			if LChunk.CreateTime > 0 then
			begin
				StreamWriteLn(AOutput, '*' + FormatCreateTime(LChunk.CreateTime) + '*');
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
