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
	Assert.Contains(LResult, '<body>');
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
	Assert.Contains(LResult, '<details>');
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

initialization
	TDUnitX.RegisterTestFixture(TTestGeminiTextFormatter);
	TDUnitX.RegisterTestFixture(TTestGeminiMarkdownFormatter);
	TDUnitX.RegisterTestFixture(TTestGeminiHtmlFormatter);

end.
