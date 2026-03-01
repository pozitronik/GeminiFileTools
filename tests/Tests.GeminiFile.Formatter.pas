/// <summary>
///   Unit tests for all three conversation formatters (Text, Markdown, HTML).
///   Tests output structure, content, resource references, and edge cases.
/// </summary>
unit Tests.GeminiFile.Formatter;

interface

uses
	System.SysUtils,
	System.Classes,
	System.Math,
	System.Generics.Collections,
	DUnitX.TestFramework,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.Formatter.Text,
	GeminiFile.Formatter.Md,
	GeminiFile.Formatter.Html;

type
	[TestFixture]
	TTestGeminiTextFormatter = class
	private
		FFormatter: TGeminiTextFormatter;
		FChunks: TObjectList<TGeminiChunk>;
		FRunSettings: TGeminiRunSettings;
		function FormatToString(const ASystemInstruction: string;
			const AResources: TArray<TFormatterResourceInfo>): string;
		function MakeChunk(ARole: TGeminiRole; const AText: string;
			ATokenCount: Integer = 0; AIsThought: Boolean = False): TGeminiChunk;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;

		[Test]
		procedure EmptyConversation_ProducesHeaderOnly;
		[Test]
		procedure UserModelChunks_CorrectLabelsAndText;
		[Test]
		procedure ChunkWithResource_InsertsAttachedPlaceholder;
		[Test]
		procedure ThinkingChunk_RendersInThinkingTags;
		[Test]
		procedure SystemInstruction_PresentWhenProvided;
		[Test]
		procedure SystemInstruction_AbsentWhenEmpty;
		[Test]
		procedure MetadataHeader_IncludesModelAndSettings;
		[Test]
		procedure ThinkingChunkWithResource_InsertsAttachedPlaceholder;
		[Test]
		procedure CreateTime_DisplayedInHeader;
		[Test]
		procedure CreateTimeZero_NotDisplayed;
		[Test]
		procedure ThinkingChunkCreateTime_DisplayedInTag;
		[Test]
		procedure EmptyUserChunk_SkippedWithRemoteHint;
		[Test]
		procedure EmptyUserChunkTrailing_ProducesStandaloneHint;
		[Test]
		procedure CombinedUserBlocks_SingleHeader;
		[Test]
		procedure CombinedBlocks_SeparatorBetween;
		[Test]
		procedure CombinedBlocks_SummedTokens;
		[Test]
		procedure CombinedBlocks_FirstTimestamp;
		[Test]
		procedure CombinedBlocks_ResourceInlinePosition;
		[Test]
		procedure CombinedThinkingBlocks_SeparatorBetween;
		[Test]
		procedure PartLevelThinking_RenderedInModelBlock;
		[Test]
		procedure EmptyBlockWithDriveId_SkippedViaHideBlocks;
	end;

	[TestFixture]
	TTestGeminiMarkdownFormatter = class
	private
		FFormatter: TGeminiMarkdownFormatter;
		FChunks: TObjectList<TGeminiChunk>;
		FRunSettings: TGeminiRunSettings;
		function FormatToString(const ASystemInstruction: string;
			const AResources: TArray<TFormatterResourceInfo>): string;
		function MakeChunk(ARole: TGeminiRole; const AText: string;
			ATokenCount: Integer = 0; AIsThought: Boolean = False): TGeminiChunk;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;

		[Test]
		procedure EmptyConversation_ProducesHeaderOnly;
		[Test]
		procedure UserModelChunks_CorrectHeadingsAndText;
		[Test]
		procedure ChunkWithResource_InsertsImageLink;
		[Test]
		procedure ThinkingChunk_UsesDetailsElement;
		[Test]
		procedure SystemInstruction_PresentWhenProvided;
		[Test]
		procedure SystemInstruction_AbsentWhenEmpty;
		[Test]
		procedure MetadataHeader_WithModelInfo;
		[Test]
		procedure ThinkingChunkWithResource_InsertsImageLink;
		[Test]
		procedure CreateTime_DisplayedAsItalic;
		[Test]
		procedure EmptyUserChunk_SkippedWithRemoteHint;
		[Test]
		procedure EmptyUserChunkTrailing_ProducesStandaloneHint;
		[Test]
		procedure CombinedUserBlocks_SingleHeading;
		[Test]
		procedure CombinedBlocks_HrSeparator;
		[Test]
		procedure CombinedBlocks_TokensShown;
		[Test]
		procedure CombinedThinkingBlocks_SeparatorBetween;
		[Test]
		procedure PartLevelThinking_RenderedInModelBlock;
		[Test]
		procedure EmptyBlockWithDriveId_SkippedViaHideBlocks;
		[Test]
		procedure ThinkingWithTimestampAndResource_CombinedSummary;
	end;

	[TestFixture]
	TTestGeminiHtmlFormatter = class
	private
		FChunks: TObjectList<TGeminiChunk>;
		FRunSettings: TGeminiRunSettings;
		function FormatToString(AEmbedResources: Boolean;
			const ASystemInstruction: string;
			const AResources: TArray<TFormatterResourceInfo>): string;
		function MakeChunk(ARole: TGeminiRole; const AText: string;
			ATokenCount: Integer = 0; AIsThought: Boolean = False): TGeminiChunk;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;

		[Test]
		procedure ExternalMode_ImagesUseSrcPaths;
		[Test]
		procedure EmbeddedMode_ImagesUseDataURIs;
		[Test]
		procedure ContainsProperHtmlStructure;
		[Test]
		procedure CssStylesPresent;
		[Test]
		procedure UserModelMessages_DistinctCssClasses;
		[Test]
		procedure ThinkingBlocks_InCollapsibleDetails;
		[Test]
		procedure SystemInstruction_RenderedWhenPresent;
		[Test]
		procedure EmptyConversation_ProducesValidHtml;
		[Test]
		procedure ThinkingChunkWithResource_RendersImage;
		[Test]
		procedure CreateTime_DisplayedInRoleDiv;
		[Test]
		procedure CustomCSS_EmbeddedInStyleBlock;
		[Test]
		procedure ControlsPanel_PresentInOutput;
		[Test]
		procedure ThinkingBlocks_HaveThinkingClass;
		[Test]
		procedure EmptyUserChunk_SkippedWithRemoteHint;
		[Test]
		procedure EmptyUserChunkTrailing_ProducesStandaloneHint;
		[Test]
		procedure DefaultFullWidth_AddsClassToBody;
		[Test]
		procedure DefaultExpandThinking_AddsOpenAttribute;
		[Test]
		procedure RenderMarkdown_AppliesConversion;
		[Test]
		procedure RenderMarkdownFalse_PreservesEscaping;
		[Test]
		procedure CombinedBlocks_SingleMessageDiv;
		[Test]
		procedure CombinedBlocks_CombinedPartDivs;
		[Test]
		procedure CombinedBlocks_CombinedPartCss;
		[Test]
		procedure CombinedThinkingBlocks_SingleDetails;
		[Test]
		procedure PartLevelThinking_RenderedInModelBlock;
		[Test]
		procedure PartLevelThinking_ExpandThinkingOpen;
		[Test]
		procedure PartLevelThinking_NoMarkdown_Escaped;
		[Test]
		procedure EmptyBlockWithDriveId_SkippedViaHideBlocks;
		[Test]
		procedure ThinkingWithTimestampAndResource_CombinedSummary;
		[Test]
		procedure ThinkingEmbedded_ResourceUsesDataUri;
		[Test]
		procedure ThinkingBlock_RenderMarkdownFalse_Escaped;
	end;

implementation

// ========================================================================
// TTestGeminiTextFormatter
// ========================================================================

procedure TTestGeminiTextFormatter.Setup;
begin
	FFormatter := TGeminiTextFormatter.Create;
	FChunks := TObjectList<TGeminiChunk>.Create(True);
	FRunSettings := TGeminiRunSettings.Create;
end;

procedure TTestGeminiTextFormatter.TearDown;
begin
	FFormatter.Free;
	FChunks.Free;
	FRunSettings.Free;
end;

function TTestGeminiTextFormatter.FormatToString(const ASystemInstruction: string;
	const AResources: TArray<TFormatterResourceInfo>): string;
var
	LStream: TMemoryStream;
	LBytes: TBytes;
begin
	LStream := TMemoryStream.Create;
	try
		FFormatter.FormatToStream(LStream, FChunks, ASystemInstruction,
			FRunSettings, AResources);
		if LStream.Size > 0 then
		begin
			SetLength(LBytes, LStream.Size);
			LStream.Position := 0;
			LStream.ReadBuffer(LBytes[0], LStream.Size);
			Result := TEncoding.UTF8.GetString(LBytes);
		end
		else
			Result := '';
	finally
		LStream.Free;
	end;
end;

function TTestGeminiTextFormatter.MakeChunk(ARole: TGeminiRole;
	const AText: string; ATokenCount: Integer; AIsThought: Boolean): TGeminiChunk;
begin
	Result := TGeminiChunk.Create;
	Result.Role := ARole;
	Result.Text := AText;
	Result.TokenCount := ATokenCount;
	Result.IsThought := AIsThought;
	Result.Index := FChunks.Count;
end;

procedure TTestGeminiTextFormatter.EmptyConversation_ProducesHeaderOnly;
var
	LResult: string;
begin
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '=== Gemini Conversation ===');
	Assert.Contains(LResult, '--- Conversation ---');
end;

procedure TTestGeminiTextFormatter.UserModelChunks_CorrectLabelsAndText;
var
	LResult: string;
begin
	FChunks.Add(MakeChunk(grUser, 'Hello'));
	FChunks.Add(MakeChunk(grModel, 'Hi there', 42));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '[USER]');
	Assert.Contains(LResult, 'Hello');
	Assert.Contains(LResult, '[MODEL] (42 tokens)');
	Assert.Contains(LResult, 'Hi there');
end;

procedure TTestGeminiTextFormatter.ChunkWithResource_InsertsAttachedPlaceholder;
var
	LResult: string;
	LRes: TArray<TFormatterResourceInfo>;
begin
	FChunks.Add(MakeChunk(grUser, 'See this image'));
	SetLength(LRes, 1);
	LRes[0].FileName := 'resources/resource_000.jpg';
	LRes[0].MimeType := 'image/jpeg';
	LRes[0].DecodedSize := 1500000;
	LRes[0].ChunkIndex := 0;
	LResult := FormatToString('', LRes);
	Assert.Contains(LResult, '[Attached: resources/resource_000.jpg (image/jpeg');
end;

procedure TTestGeminiTextFormatter.ThinkingChunk_RendersInThinkingTags;
var
	LResult: string;
begin
	FChunks.Add(MakeChunk(grModel, 'Let me think...', 0, True));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '<Thinking>');
	Assert.Contains(LResult, 'Let me think...');
	Assert.Contains(LResult, '</Thinking>');
	// Thinking chunks should not have a role header
	Assert.IsFalse(LResult.Contains('[MODEL]'), 'Thinking chunks should not have [MODEL] header');
end;

procedure TTestGeminiTextFormatter.SystemInstruction_PresentWhenProvided;
var
	LResult: string;
begin
	LResult := FormatToString('You are a helpful assistant.', nil);
	Assert.Contains(LResult, '--- System Instruction ---');
	Assert.Contains(LResult, 'You are a helpful assistant.');
end;

procedure TTestGeminiTextFormatter.SystemInstruction_AbsentWhenEmpty;
var
	LResult: string;
begin
	LResult := FormatToString('', nil);
	Assert.IsFalse(LResult.Contains('System Instruction'),
		'System instruction section should not appear when empty');
end;

procedure TTestGeminiTextFormatter.MetadataHeader_IncludesModelAndSettings;
var
	LResult: string;
begin
	FRunSettings.Model := 'models/gemini-2.5-pro';
	FRunSettings.Temperature := 0.7;
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, 'Model: models/gemini-2.5-pro');
	Assert.Contains(LResult, 'Temperature: 0.7');
end;

procedure TTestGeminiTextFormatter.ThinkingChunkWithResource_InsertsAttachedPlaceholder;
var
	LResult: string;
	LRes: TArray<TFormatterResourceInfo>;
begin
	FChunks.Add(MakeChunk(grModel, 'Reasoning about image...', 0, True));
	SetLength(LRes, 1);
	LRes[0].FileName := 'resources/resource_000.png';
	LRes[0].MimeType := 'image/png';
	LRes[0].DecodedSize := 204800;
	LRes[0].ChunkIndex := 0;
	LResult := FormatToString('', LRes);
	Assert.Contains(LResult, '<Thinking>');
	Assert.Contains(LResult, 'Reasoning about image...');
	Assert.Contains(LResult, '</Thinking>');
	Assert.Contains(LResult, '[Attached: resources/resource_000.png (image/png');
end;

procedure TTestGeminiTextFormatter.CreateTime_DisplayedInHeader;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grUser, 'Hello', 8);
	LChunk.CreateTime := EncodeDate(2026, 2, 26) + EncodeTime(0, 1, 2, 0);
	FChunks.Add(LChunk);
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '[USER] 2026-02-26 00:01:02 (8 tokens)');
end;

procedure TTestGeminiTextFormatter.CreateTimeZero_NotDisplayed;
var
	LResult: string;
begin
	FChunks.Add(MakeChunk(grUser, 'Hello'));
	LResult := FormatToString('', nil);
	// CreateTime is 0 by default -- no date should appear between role and text
	Assert.IsFalse(LResult.Contains('2026-'), 'No date should appear when CreateTime is zero');
end;

procedure TTestGeminiTextFormatter.ThinkingChunkCreateTime_DisplayedInTag;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grModel, 'Analyzing...', 0, True);
	LChunk.CreateTime := EncodeDate(2026, 2, 26) + EncodeTime(0, 1, 2, 0);
	FChunks.Add(LChunk);
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '<Thinking> 2026-02-26 00:01:02');
end;

procedure TTestGeminiTextFormatter.EmptyUserChunk_SkippedWithRemoteHint;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	// Empty user chunk with DriveImageId (remote attachment)
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'abc123';
	FChunks.Add(LChunk);
	// Followed by non-empty user chunk
	FChunks.Add(MakeChunk(grUser, 'Analyze this image'));
	LResult := FormatToString('', nil);
	// Should NOT have a bare [USER] header for the empty chunk
	Assert.Contains(LResult, '1 remote attachment(s)');
	Assert.Contains(LResult, 'Analyze this image');
end;

procedure TTestGeminiTextFormatter.EmptyUserChunkTrailing_ProducesStandaloneHint;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	// Two empty user chunks at end of conversation
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'abc123';
	FChunks.Add(LChunk);
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'def456';
	FChunks.Add(LChunk);
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '2 remote attachment(s)');
	Assert.IsFalse(LResult.Contains('[USER]'),
		'Empty blocks should not produce role headers');
end;

procedure TTestGeminiTextFormatter.CombinedUserBlocks_SingleHeader;
var
	LResult: string;
	LPos, LSecond: Integer;
begin
	FFormatter.CombineBlocks := True;
	FChunks.Add(MakeChunk(grUser, 'First message'));
	FChunks.Add(MakeChunk(grUser, 'Second message'));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '[USER]');
	Assert.Contains(LResult, 'First message');
	Assert.Contains(LResult, 'Second message');
	// Only one [USER] header
	LPos := Pos('[USER]', LResult);
	LSecond := Pos('[USER]', LResult, LPos + 1);
	Assert.AreEqual<Integer>(0, LSecond, 'Should have only one [USER] header');
end;

procedure TTestGeminiTextFormatter.CombinedBlocks_SeparatorBetween;
var
	LResult: string;
begin
	FFormatter.CombineBlocks := True;
	FChunks.Add(MakeChunk(grUser, 'First'));
	FChunks.Add(MakeChunk(grUser, 'Second'));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '- - -');
end;

procedure TTestGeminiTextFormatter.CombinedBlocks_SummedTokens;
var
	LResult: string;
begin
	FFormatter.CombineBlocks := True;
	FChunks.Add(MakeChunk(grModel, 'A', 10));
	FChunks.Add(MakeChunk(grModel, 'B', 20));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '(30 tokens)');
end;

procedure TTestGeminiTextFormatter.CombinedBlocks_FirstTimestamp;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	FFormatter.CombineBlocks := True;
	LChunk := MakeChunk(grUser, 'First', 0);
	LChunk.CreateTime := EncodeDate(2026, 3, 1) + EncodeTime(10, 30, 0, 0);
	FChunks.Add(LChunk);
	FChunks.Add(MakeChunk(grUser, 'Second'));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '2026-03-01 10:30:00');
end;

procedure TTestGeminiTextFormatter.CombinedBlocks_ResourceInlinePosition;
var
	LResult: string;
	LRes: TArray<TFormatterResourceInfo>;
begin
	FFormatter.CombineBlocks := True;
	FChunks.Add(MakeChunk(grUser, 'Text before image'));
	FChunks.Add(MakeChunk(grUser, 'Text after image'));
	SetLength(LRes, 1);
	LRes[0].FileName := 'resources/resource_000.jpg';
	LRes[0].MimeType := 'image/jpeg';
	LRes[0].DecodedSize := 1000;
	LRes[0].ChunkIndex := 0;
	LResult := FormatToString('', LRes);
	// Resource should appear after first chunk's text, before separator
	var LResPos := Pos('[Attached:', LResult);
	var LSepPos := Pos('- - -', LResult);
	Assert.IsTrue(LResPos > 0, 'Resource indicator should be present');
	Assert.IsTrue(LSepPos > 0, 'Separator should be present');
	Assert.IsTrue(LResPos < LSepPos, 'Resource should appear before separator');
end;

procedure TTestGeminiTextFormatter.CombinedThinkingBlocks_SeparatorBetween;
var
	LResult: string;
begin
	FFormatter.CombineBlocks := True;
	FChunks.Add(MakeChunk(grModel, 'Think A', 0, True));
	FChunks.Add(MakeChunk(grModel, 'Think B', 0, True));
	LResult := FormatToString('', nil);
	// Should have separator between combined thinking sub-blocks
	Assert.Contains(LResult, '- - -');
	Assert.Contains(LResult, 'Think A');
	Assert.Contains(LResult, 'Think B');
end;

procedure TTestGeminiTextFormatter.PartLevelThinking_RenderedInModelBlock;
var
	LResult: string;
	LChunk: TGeminiChunk;
	LPart: TGeminiPart;
begin
	// Model chunk (not IsThought) with mixed parts: one thinking, one text
	LChunk := TGeminiChunk.Create;
	LChunk.Role := grModel;
	LChunk.IsThought := False;
	LChunk.Index := 0;
	LPart := TGeminiPart.Create;
	LPart.Text := 'Internal reasoning';
	LPart.IsThought := True;
	LChunk.Parts.Add(LPart);
	LPart := TGeminiPart.Create;
	LPart.Text := 'Visible answer';
	LPart.IsThought := False;
	LChunk.Parts.Add(LPart);
	FChunks.Add(LChunk);
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '[MODEL]');
	Assert.Contains(LResult, '<Thinking>');
	Assert.Contains(LResult, 'Internal reasoning');
	Assert.Contains(LResult, '</Thinking>');
	Assert.Contains(LResult, 'Visible answer');
end;

procedure TTestGeminiTextFormatter.EmptyBlockWithDriveId_SkippedViaHideBlocks;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	// Empty chunk with DriveImageId but no text -- should increment pending count
	// and Continue, followed by a model response to reset pending count
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'drive_id_1';
	FChunks.Add(LChunk);
	FChunks.Add(MakeChunk(grModel, 'Response'));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '1 remote attachment(s)');
	Assert.Contains(LResult, 'Response');
end;

// ========================================================================
// TTestGeminiMarkdownFormatter
// ========================================================================

procedure TTestGeminiMarkdownFormatter.Setup;
begin
	FFormatter := TGeminiMarkdownFormatter.Create;
	FChunks := TObjectList<TGeminiChunk>.Create(True);
	FRunSettings := TGeminiRunSettings.Create;
end;

procedure TTestGeminiMarkdownFormatter.TearDown;
begin
	FFormatter.Free;
	FChunks.Free;
	FRunSettings.Free;
end;

function TTestGeminiMarkdownFormatter.FormatToString(const ASystemInstruction: string;
	const AResources: TArray<TFormatterResourceInfo>): string;
var
	LStream: TMemoryStream;
	LBytes: TBytes;
begin
	LStream := TMemoryStream.Create;
	try
		FFormatter.FormatToStream(LStream, FChunks, ASystemInstruction,
			FRunSettings, AResources);
		if LStream.Size > 0 then
		begin
			SetLength(LBytes, LStream.Size);
			LStream.Position := 0;
			LStream.ReadBuffer(LBytes[0], LStream.Size);
			Result := TEncoding.UTF8.GetString(LBytes);
		end
		else
			Result := '';
	finally
		LStream.Free;
	end;
end;

function TTestGeminiMarkdownFormatter.MakeChunk(ARole: TGeminiRole;
	const AText: string; ATokenCount: Integer; AIsThought: Boolean): TGeminiChunk;
begin
	Result := TGeminiChunk.Create;
	Result.Role := ARole;
	Result.Text := AText;
	Result.TokenCount := ATokenCount;
	Result.IsThought := AIsThought;
	Result.Index := FChunks.Count;
end;

procedure TTestGeminiMarkdownFormatter.EmptyConversation_ProducesHeaderOnly;
var
	LResult: string;
begin
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '# Gemini Conversation');
	Assert.Contains(LResult, '## Conversation');
end;

procedure TTestGeminiMarkdownFormatter.UserModelChunks_CorrectHeadingsAndText;
var
	LResult: string;
begin
	FChunks.Add(MakeChunk(grUser, 'Hello'));
	FChunks.Add(MakeChunk(grModel, 'Hi there'));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '### User');
	Assert.Contains(LResult, 'Hello');
	Assert.Contains(LResult, '### Model');
	Assert.Contains(LResult, 'Hi there');
end;

procedure TTestGeminiMarkdownFormatter.ChunkWithResource_InsertsImageLink;
var
	LResult: string;
	LRes: TArray<TFormatterResourceInfo>;
begin
	FChunks.Add(MakeChunk(grUser, 'Image attached'));
	SetLength(LRes, 1);
	LRes[0].FileName := 'resources/resource_000.png';
	LRes[0].MimeType := 'image/png';
	LRes[0].DecodedSize := 500000;
	LRes[0].ChunkIndex := 0;
	LResult := FormatToString('', LRes);
	Assert.Contains(LResult, '![resource_000.png](resources/resource_000.png)');
end;

procedure TTestGeminiMarkdownFormatter.ThinkingChunk_UsesDetailsElement;
var
	LResult: string;
begin
	FChunks.Add(MakeChunk(grModel, 'Analyzing...', 0, True));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '<details><summary>Thinking</summary>');
	Assert.Contains(LResult, 'Analyzing...');
	Assert.Contains(LResult, '</details>');
end;

procedure TTestGeminiMarkdownFormatter.SystemInstruction_PresentWhenProvided;
var
	LResult: string;
begin
	LResult := FormatToString('Be helpful.', nil);
	Assert.Contains(LResult, '## System Instruction');
	Assert.Contains(LResult, 'Be helpful.');
end;

procedure TTestGeminiMarkdownFormatter.SystemInstruction_AbsentWhenEmpty;
var
	LResult: string;
begin
	LResult := FormatToString('', nil);
	Assert.IsFalse(LResult.Contains('System Instruction'),
		'System instruction section should not appear when empty');
end;

procedure TTestGeminiMarkdownFormatter.MetadataHeader_WithModelInfo;
var
	LResult: string;
begin
	FRunSettings.Model := 'models/gemini-2.5-pro';
	FRunSettings.Temperature := 1.0;
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '**Model:** models/gemini-2.5-pro');
	Assert.Contains(LResult, '**Temperature:** 1.0');
end;

procedure TTestGeminiMarkdownFormatter.ThinkingChunkWithResource_InsertsImageLink;
var
	LResult: string;
	LRes: TArray<TFormatterResourceInfo>;
begin
	FChunks.Add(MakeChunk(grModel, 'Analyzing the image...', 0, True));
	SetLength(LRes, 1);
	LRes[0].FileName := 'resources/resource_000.jpg';
	LRes[0].MimeType := 'image/jpeg';
	LRes[0].DecodedSize := 102400;
	LRes[0].ChunkIndex := 0;
	LResult := FormatToString('', LRes);
	Assert.Contains(LResult, 'Thinking (with attachment)');
	Assert.Contains(LResult, '![resource_000.jpg](resources/resource_000.jpg)');
	Assert.Contains(LResult, '</details>');
end;

procedure TTestGeminiMarkdownFormatter.CreateTime_DisplayedAsItalic;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grUser, 'Hello');
	LChunk.CreateTime := EncodeDate(2026, 2, 26) + EncodeTime(0, 1, 2, 0);
	FChunks.Add(LChunk);
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '*2026-02-26 00:01:02*');
end;

procedure TTestGeminiMarkdownFormatter.EmptyUserChunk_SkippedWithRemoteHint;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'abc123';
	FChunks.Add(LChunk);
	FChunks.Add(MakeChunk(grUser, 'Analyze this image'));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '*1 remote attachment(s)*');
	Assert.Contains(LResult, 'Analyze this image');
end;

procedure TTestGeminiMarkdownFormatter.EmptyUserChunkTrailing_ProducesStandaloneHint;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'abc123';
	FChunks.Add(LChunk);
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'def456';
	FChunks.Add(LChunk);
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '*2 remote attachment(s)*');
end;

procedure TTestGeminiMarkdownFormatter.CombinedUserBlocks_SingleHeading;
var
	LResult: string;
begin
	FFormatter.CombineBlocks := True;
	FChunks.Add(MakeChunk(grUser, 'First'));
	FChunks.Add(MakeChunk(grUser, 'Second'));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '### User');
	Assert.Contains(LResult, 'First');
	Assert.Contains(LResult, 'Second');
	// Only one ### User heading
	var LPos := Pos('### User', LResult);
	var LSecond := Pos('### User', LResult, LPos + 1);
	Assert.AreEqual<Integer>(0, LSecond, 'Should have only one ### User heading');
end;

procedure TTestGeminiMarkdownFormatter.CombinedBlocks_HrSeparator;
var
	LResult: string;
	LPos: Integer;
begin
	FFormatter.CombineBlocks := True;
	FChunks.Add(MakeChunk(grUser, 'First'));
	FChunks.Add(MakeChunk(grUser, 'Second'));
	LResult := FormatToString('', nil);
	// Find --- that appears after the Conversation section separator
	// The separator between sub-blocks should appear after the content starts
	LPos := Pos('First', LResult);
	Assert.IsTrue(Pos('---', LResult, LPos) > 0,
		'Horizontal rule separator should appear between combined sub-blocks');
end;

procedure TTestGeminiMarkdownFormatter.CombinedBlocks_TokensShown;
var
	LResult: string;
begin
	FFormatter.CombineBlocks := True;
	FChunks.Add(MakeChunk(grModel, 'A', 15));
	FChunks.Add(MakeChunk(grModel, 'B', 25));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '*(40 tokens)*');
end;

procedure TTestGeminiMarkdownFormatter.CombinedThinkingBlocks_SeparatorBetween;
var
	LResult: string;
begin
	FFormatter.CombineBlocks := True;
	FChunks.Add(MakeChunk(grModel, 'Think A', 0, True));
	FChunks.Add(MakeChunk(grModel, 'Think B', 0, True));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, 'Think A');
	Assert.Contains(LResult, 'Think B');
	// Only one <details> block for combined thinking
	var LPos := Pos('<details>', LResult);
	Assert.IsTrue(LPos > 0, 'Should have a details element');
	var LSecond := Pos('<details>', LResult, LPos + 1);
	Assert.AreEqual<Integer>(0, LSecond, 'Should have only one details element');
end;

procedure TTestGeminiMarkdownFormatter.PartLevelThinking_RenderedInModelBlock;
var
	LResult: string;
	LChunk: TGeminiChunk;
	LPart: TGeminiPart;
begin
	LChunk := TGeminiChunk.Create;
	LChunk.Role := grModel;
	LChunk.IsThought := False;
	LChunk.Index := 0;
	LPart := TGeminiPart.Create;
	LPart.Text := 'Internal reasoning';
	LPart.IsThought := True;
	LChunk.Parts.Add(LPart);
	LPart := TGeminiPart.Create;
	LPart.Text := 'Visible answer';
	LPart.IsThought := False;
	LChunk.Parts.Add(LPart);
	FChunks.Add(LChunk);
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '### Model');
	Assert.Contains(LResult, '<details><summary>Thinking</summary>');
	Assert.Contains(LResult, 'Internal reasoning');
	Assert.Contains(LResult, '</details>');
	Assert.Contains(LResult, 'Visible answer');
end;

procedure TTestGeminiMarkdownFormatter.EmptyBlockWithDriveId_SkippedViaHideBlocks;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'drive_id_1';
	FChunks.Add(LChunk);
	FChunks.Add(MakeChunk(grModel, 'Response'));
	LResult := FormatToString('', nil);
	Assert.Contains(LResult, '*1 remote attachment(s)*');
	Assert.Contains(LResult, 'Response');
end;

procedure TTestGeminiMarkdownFormatter.ThinkingWithTimestampAndResource_CombinedSummary;
var
	LResult: string;
	LChunk: TGeminiChunk;
	LRes: TArray<TFormatterResourceInfo>;
begin
	LChunk := MakeChunk(grModel, 'Reasoning about image...', 0, True);
	LChunk.CreateTime := EncodeDate(2026, 3, 1) + EncodeTime(12, 0, 0, 0);
	FChunks.Add(LChunk);
	SetLength(LRes, 1);
	LRes[0].FileName := 'resources/resource_000.png';
	LRes[0].MimeType := 'image/png';
	LRes[0].DecodedSize := 51200;
	LRes[0].ChunkIndex := 0;
	LResult := FormatToString('', LRes);
	// Summary should contain both timestamp and "with attachment"
	Assert.Contains(LResult, '2026-03-01 12:00:00');
	Assert.Contains(LResult, 'with attachment');
end;

// ========================================================================
// TTestGeminiHtmlFormatter
// ========================================================================

procedure TTestGeminiHtmlFormatter.Setup;
begin
	FChunks := TObjectList<TGeminiChunk>.Create(True);
	FRunSettings := TGeminiRunSettings.Create;
end;

procedure TTestGeminiHtmlFormatter.TearDown;
begin
	FChunks.Free;
	FRunSettings.Free;
end;

function TTestGeminiHtmlFormatter.FormatToString(AEmbedResources: Boolean;
	const ASystemInstruction: string;
	const AResources: TArray<TFormatterResourceInfo>): string;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
begin
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(AEmbedResources);
		try
			LFormatter.FormatToStream(LStream, FChunks, ASystemInstruction,
				FRunSettings, AResources);
		finally
			LFormatter.Free;
		end;
		if LStream.Size > 0 then
		begin
			SetLength(LBytes, LStream.Size);
			LStream.Position := 0;
			LStream.ReadBuffer(LBytes[0], LStream.Size);
			Result := TEncoding.UTF8.GetString(LBytes);
		end
		else
			Result := '';
	finally
		LStream.Free;
	end;
end;

function TTestGeminiHtmlFormatter.MakeChunk(ARole: TGeminiRole;
	const AText: string; ATokenCount: Integer; AIsThought: Boolean): TGeminiChunk;
begin
	Result := TGeminiChunk.Create;
	Result.Role := ARole;
	Result.Text := AText;
	Result.TokenCount := ATokenCount;
	Result.IsThought := AIsThought;
	Result.Index := FChunks.Count;
end;

procedure TTestGeminiHtmlFormatter.ExternalMode_ImagesUseSrcPaths;
var
	LResult: string;
	LRes: TArray<TFormatterResourceInfo>;
begin
	FChunks.Add(MakeChunk(grUser, 'Image'));
	SetLength(LRes, 1);
	LRes[0].FileName := 'resources/resource_000.png';
	LRes[0].MimeType := 'image/png';
	LRes[0].DecodedSize := 100;
	LRes[0].ChunkIndex := 0;
	LResult := FormatToString(False, '', LRes);
	Assert.Contains(LResult, 'src="resources/resource_000.png"');
end;

procedure TTestGeminiHtmlFormatter.EmbeddedMode_ImagesUseDataURIs;
var
	LResult: string;
	LRes: TArray<TFormatterResourceInfo>;
begin
	FChunks.Add(MakeChunk(grUser, 'Image'));
	SetLength(LRes, 1);
	LRes[0].FileName := 'resources/resource_000.jpg';
	LRes[0].MimeType := 'image/jpeg';
	LRes[0].Base64Data := 'AQID';
	LRes[0].DecodedSize := 3;
	LRes[0].ChunkIndex := 0;
	LResult := FormatToString(True, '', LRes);
	Assert.Contains(LResult, 'src="data:image/jpeg;base64,AQID"');
end;

procedure TTestGeminiHtmlFormatter.ContainsProperHtmlStructure;
var
	LResult: string;
begin
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, '<!DOCTYPE html>');
	Assert.Contains(LResult, '<html');
	Assert.Contains(LResult, '<head>');
	Assert.Contains(LResult, '<body');
	Assert.Contains(LResult, '</html>');
end;

procedure TTestGeminiHtmlFormatter.CssStylesPresent;
var
	LResult: string;
begin
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, '<style>');
	Assert.Contains(LResult, '</style>');
	Assert.Contains(LResult, '.message');
	Assert.Contains(LResult, '.user');
	Assert.Contains(LResult, '.model');
end;

procedure TTestGeminiHtmlFormatter.UserModelMessages_DistinctCssClasses;
var
	LResult: string;
begin
	FChunks.Add(MakeChunk(grUser, 'Question'));
	FChunks.Add(MakeChunk(grModel, 'Answer'));
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, 'class="message user"');
	Assert.Contains(LResult, 'class="message model"');
end;

procedure TTestGeminiHtmlFormatter.ThinkingBlocks_InCollapsibleDetails;
var
	LResult: string;
begin
	FChunks.Add(MakeChunk(grModel, 'Processing...', 0, True));
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, '<details class="thinking">');
	Assert.Contains(LResult, '<summary>Thinking</summary>');
	Assert.Contains(LResult, 'Processing...');
	Assert.Contains(LResult, '</details>');
end;

procedure TTestGeminiHtmlFormatter.SystemInstruction_RenderedWhenPresent;
var
	LResult: string;
begin
	LResult := FormatToString(False, 'Be concise.', nil);
	Assert.Contains(LResult, 'System Instruction');
	Assert.Contains(LResult, 'Be concise.');
end;

procedure TTestGeminiHtmlFormatter.EmptyConversation_ProducesValidHtml;
var
	LResult: string;
begin
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, '<!DOCTYPE html>');
	Assert.Contains(LResult, '</html>');
	Assert.Contains(LResult, 'Gemini Conversation');
end;

procedure TTestGeminiHtmlFormatter.ThinkingChunkWithResource_RendersImage;
var
	LResult: string;
	LRes: TArray<TFormatterResourceInfo>;
begin
	FChunks.Add(MakeChunk(grModel, 'Looking at the picture...', 0, True));
	SetLength(LRes, 1);
	LRes[0].FileName := 'resources/resource_000.png';
	LRes[0].MimeType := 'image/png';
	LRes[0].DecodedSize := 51200;
	LRes[0].ChunkIndex := 0;
	LResult := FormatToString(False, '', LRes);
	Assert.Contains(LResult, 'Thinking (with attachment)');
	Assert.Contains(LResult, '<img class="resource-img" src="resources/resource_000.png"');
	Assert.Contains(LResult, '</details>');
end;

procedure TTestGeminiHtmlFormatter.CreateTime_DisplayedInRoleDiv;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grUser, 'Hello', 8);
	LChunk.CreateTime := EncodeDate(2026, 2, 26) + EncodeTime(0, 1, 2, 0);
	FChunks.Add(LChunk);
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, 'class="time"');
	Assert.Contains(LResult, '2026-02-26 00:01:02');
end;

procedure TTestGeminiHtmlFormatter.CustomCSS_EmbeddedInStyleBlock;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
begin
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False, '.custom-rule { color: red; }');
		try
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	// Custom CSS must appear within the style block, after built-in styles
	Assert.Contains(LResult, '<style>');
	Assert.Contains(LResult, '.custom-rule { color: red; }');
	Assert.Contains(LResult, '</style>');
end;

procedure TTestGeminiHtmlFormatter.ControlsPanel_PresentInOutput;
var
	LResult: string;
begin
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, 'id="controls"');
	Assert.Contains(LResult, 'toggleWidth');
	Assert.Contains(LResult, 'setThinking');
end;

procedure TTestGeminiHtmlFormatter.ThinkingBlocks_HaveThinkingClass;
var
	LResult: string;
begin
	FChunks.Add(MakeChunk(grModel, 'Reasoning...', 0, True));
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, '<details class="thinking">');
end;

procedure TTestGeminiHtmlFormatter.EmptyUserChunk_SkippedWithRemoteHint;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'abc123';
	FChunks.Add(LChunk);
	FChunks.Add(MakeChunk(grUser, 'Analyze this image'));
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, 'class="remote-attachments"');
	Assert.Contains(LResult, '1 remote attachment(s)');
	Assert.Contains(LResult, 'Analyze this image');
end;

procedure TTestGeminiHtmlFormatter.EmptyUserChunkTrailing_ProducesStandaloneHint;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'abc123';
	FChunks.Add(LChunk);
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'def456';
	FChunks.Add(LChunk);
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, '2 remote attachment(s)');
	Assert.Contains(LResult, 'class="remote-attachments"');
end;

procedure TTestGeminiHtmlFormatter.DefaultFullWidth_AddsClassToBody;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
begin
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False);
		try
			LFormatter.DefaultFullWidth := True;
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	Assert.Contains(LResult, 'full-width');
	Assert.Contains(LResult, 'Column width</button>');
end;

procedure TTestGeminiHtmlFormatter.DefaultExpandThinking_AddsOpenAttribute;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
begin
	FChunks.Add(MakeChunk(grModel, 'Reasoning...', 0, True));
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False);
		try
			LFormatter.DefaultExpandThinking := True;
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	Assert.Contains(LResult, '<details class="thinking" open>');
end;

procedure TTestGeminiHtmlFormatter.RenderMarkdown_AppliesConversion;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
begin
	FChunks.Add(MakeChunk(grModel, '**bold**'));
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False);
		try
			LFormatter.RenderMarkdown := True;
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	Assert.Contains(LResult, '<strong>bold</strong>');
	Assert.Contains(LResult, 'class="md"');
end;

procedure TTestGeminiHtmlFormatter.RenderMarkdownFalse_PreservesEscaping;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
begin
	FChunks.Add(MakeChunk(grModel, '**bold**'));
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False);
		try
			LFormatter.RenderMarkdown := False;
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	Assert.Contains(LResult, '**bold**');
	Assert.IsFalse(LResult.Contains('<strong>'), 'Markdown should not be rendered when disabled');
	Assert.IsFalse(LResult.Contains('class="md"'), 'md class should not be present when disabled');
end;

procedure TTestGeminiHtmlFormatter.CombinedBlocks_SingleMessageDiv;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
begin
	FChunks.Add(MakeChunk(grUser, 'First'));
	FChunks.Add(MakeChunk(grUser, 'Second'));
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False);
		try
			LFormatter.CombineBlocks := True;
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	// Should have exactly one message div for both user chunks
	var LPos := Pos('class="message user"', LResult);
	Assert.IsTrue(LPos > 0, 'Should have a message div');
	var LSecond := Pos('class="message user"', LResult, LPos + 1);
	Assert.AreEqual<Integer>(0, LSecond, 'Should have only one message div');
	Assert.Contains(LResult, 'First');
	Assert.Contains(LResult, 'Second');
end;

procedure TTestGeminiHtmlFormatter.CombinedBlocks_CombinedPartDivs;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
begin
	FChunks.Add(MakeChunk(grUser, 'First'));
	FChunks.Add(MakeChunk(grUser, 'Second'));
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False);
		try
			LFormatter.CombineBlocks := True;
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	Assert.Contains(LResult, 'class="combined-part"');
end;

procedure TTestGeminiHtmlFormatter.CombinedBlocks_CombinedPartCss;
var
	LResult: string;
begin
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, '.combined-part');
end;

procedure TTestGeminiHtmlFormatter.CombinedThinkingBlocks_SingleDetails;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
begin
	FChunks.Add(MakeChunk(grModel, 'Think A', 0, True));
	FChunks.Add(MakeChunk(grModel, 'Think B', 0, True));
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False);
		try
			LFormatter.CombineBlocks := True;
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	// Should have exactly one <details class="thinking">
	var LPos := Pos('<details class="thinking">', LResult);
	Assert.IsTrue(LPos > 0, 'Should have a thinking details element');
	var LSecond := Pos('<details class="thinking">', LResult, LPos + 1);
	Assert.AreEqual<Integer>(0, LSecond, 'Should have only one thinking details element');
	Assert.Contains(LResult, 'Think A');
	Assert.Contains(LResult, 'Think B');
end;

procedure TTestGeminiHtmlFormatter.PartLevelThinking_RenderedInModelBlock;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
	LChunk: TGeminiChunk;
	LPart: TGeminiPart;
begin
	LChunk := TGeminiChunk.Create;
	LChunk.Role := grModel;
	LChunk.IsThought := False;
	LChunk.Index := 0;
	LPart := TGeminiPart.Create;
	LPart.Text := 'Internal reasoning';
	LPart.IsThought := True;
	LChunk.Parts.Add(LPart);
	LPart := TGeminiPart.Create;
	LPart.Text := 'Visible answer';
	LPart.IsThought := False;
	LChunk.Parts.Add(LPart);
	FChunks.Add(LChunk);
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False);
		try
			LFormatter.RenderMarkdown := True;
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	Assert.Contains(LResult, 'class="message model"');
	Assert.Contains(LResult, '<details class="thinking">');
	Assert.Contains(LResult, '<summary>Thinking</summary>');
	Assert.Contains(LResult, 'Internal reasoning');
	Assert.Contains(LResult, '</details>');
	Assert.Contains(LResult, 'Visible answer');
end;

procedure TTestGeminiHtmlFormatter.PartLevelThinking_ExpandThinkingOpen;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
	LChunk: TGeminiChunk;
	LPart: TGeminiPart;
begin
	LChunk := TGeminiChunk.Create;
	LChunk.Role := grModel;
	LChunk.IsThought := False;
	LChunk.Index := 0;
	LPart := TGeminiPart.Create;
	LPart.Text := 'Thinking part';
	LPart.IsThought := True;
	LChunk.Parts.Add(LPart);
	LPart := TGeminiPart.Create;
	LPart.Text := 'Answer';
	LPart.IsThought := False;
	LChunk.Parts.Add(LPart);
	FChunks.Add(LChunk);
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False);
		try
			LFormatter.DefaultExpandThinking := True;
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	Assert.Contains(LResult, '<details class="thinking" open>');
end;

procedure TTestGeminiHtmlFormatter.PartLevelThinking_NoMarkdown_Escaped;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
	LChunk: TGeminiChunk;
	LPart: TGeminiPart;
begin
	LChunk := TGeminiChunk.Create;
	LChunk.Role := grModel;
	LChunk.IsThought := False;
	LChunk.Index := 0;
	LPart := TGeminiPart.Create;
	LPart.Text := '**bold thinking**';
	LPart.IsThought := True;
	LChunk.Parts.Add(LPart);
	LPart := TGeminiPart.Create;
	LPart.Text := 'Answer';
	LPart.IsThought := False;
	LChunk.Parts.Add(LPart);
	FChunks.Add(LChunk);
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False);
		try
			LFormatter.RenderMarkdown := False;
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	Assert.Contains(LResult, '**bold thinking**');
	Assert.IsFalse(LResult.Contains('<strong>bold thinking</strong>'),
		'Markdown should not be rendered in thinking when disabled');
end;

procedure TTestGeminiHtmlFormatter.EmptyBlockWithDriveId_SkippedViaHideBlocks;
var
	LResult: string;
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grUser, '');
	LChunk.DriveImageId := 'drive_id_1';
	FChunks.Add(LChunk);
	FChunks.Add(MakeChunk(grModel, 'Response'));
	LResult := FormatToString(False, '', nil);
	Assert.Contains(LResult, '1 remote attachment(s)');
	Assert.Contains(LResult, 'Response');
end;

procedure TTestGeminiHtmlFormatter.ThinkingWithTimestampAndResource_CombinedSummary;
var
	LResult: string;
	LChunk: TGeminiChunk;
	LRes: TArray<TFormatterResourceInfo>;
begin
	LChunk := MakeChunk(grModel, 'Reasoning about image...', 0, True);
	LChunk.CreateTime := EncodeDate(2026, 3, 1) + EncodeTime(12, 0, 0, 0);
	FChunks.Add(LChunk);
	SetLength(LRes, 1);
	LRes[0].FileName := 'resources/resource_000.png';
	LRes[0].MimeType := 'image/png';
	LRes[0].DecodedSize := 51200;
	LRes[0].ChunkIndex := 0;
	LResult := FormatToString(False, '', LRes);
	Assert.Contains(LResult, '2026-03-01 12:00:00');
	Assert.Contains(LResult, 'with attachment');
end;

procedure TTestGeminiHtmlFormatter.ThinkingEmbedded_ResourceUsesDataUri;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
	LRes: TArray<TFormatterResourceInfo>;
begin
	FChunks.Add(MakeChunk(grModel, 'Analyzing image...', 0, True));
	SetLength(LRes, 1);
	LRes[0].FileName := 'resources/resource_000.png';
	LRes[0].MimeType := 'image/png';
	LRes[0].Base64Data := 'AQIDBA==';
	LRes[0].DecodedSize := 4;
	LRes[0].ChunkIndex := 0;
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(True);
		try
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, LRes);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	Assert.Contains(LResult, 'src="data:image/png;base64,AQIDBA=="');
end;

procedure TTestGeminiHtmlFormatter.ThinkingBlock_RenderMarkdownFalse_Escaped;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
	LBytes: TBytes;
	LResult: string;
begin
	FChunks.Add(MakeChunk(grModel, '**bold thinking**', 0, True));
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiHtmlFormatter.Create(False);
		try
			LFormatter.RenderMarkdown := False;
			LFormatter.FormatToStream(LStream, FChunks, '', FRunSettings, nil);
		finally
			LFormatter.Free;
		end;
		SetLength(LBytes, LStream.Size);
		LStream.Position := 0;
		LStream.ReadBuffer(LBytes[0], LStream.Size);
		LResult := TEncoding.UTF8.GetString(LBytes);
	finally
		LStream.Free;
	end;
	Assert.Contains(LResult, '**bold thinking**');
	Assert.IsFalse(LResult.Contains('<strong>'),
		'Markdown should not be rendered in thinking block when disabled');
end;

initialization
	TDUnitX.RegisterTestFixture(TTestGeminiTextFormatter);
	TDUnitX.RegisterTestFixture(TTestGeminiMarkdownFormatter);
	TDUnitX.RegisterTestFixture(TTestGeminiHtmlFormatter);

end.
