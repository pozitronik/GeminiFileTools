/// <summary>
///   Integration tests: load real Gemini sample files and verify expected values.
///   Requires the examples/ directory to be present relative to the test executable.
///   Tests that cannot find their example files pass silently (FailsOnNoAsserts=False).
/// </summary>
unit Tests.GeminiFile.Integration;

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.Generics.Collections,
  DUnitX.TestFramework,
  GeminiFile.Types,
  GeminiFile.Model,
  GeminiFile.Parser,
  GeminiFile.Extractor,
  GeminiFile;

type
  [TestFixture]
  TTestGeminiFileIntegration = class
  public
    // Tailscale tests
    [Test]
    procedure Tailscale_ChunkCounts;
    [Test]
    procedure Tailscale_RunSettings;

    // Pushkin tests
    [Test]
    procedure Pushkin_ChunkCount;
    [Test]
    procedure Pushkin_SystemInstruction;

    // Gadget tests
    [Test]
    procedure Gadget_ResourceCount;
    [Test]
    procedure Gadget_ResourceExtraction;

    // Tigritsa tests
    [Test]
    procedure Tigritsa_ResourceCount;
    [Test]
    procedure Tigritsa_RunSettings;

    // Facade tests
    [Test]
    procedure LoadFromFile_NotFound_RaisesException;
    [Test]
    procedure Create_WithCustomParserAndExtractor;
    [Test]
    procedure GetResources_PartsInlineDataFallback;
    [Test]
    procedure GetResourceCount_MatchesGetResourcesLength;
    [Test]
    procedure LoadFromStream_SystemInstruction_Parsed;
    [Test]
    procedure LoadFromStream_MultipleRoles_CorrectCounts;
    [Test]
    procedure LoadFromStream_TokenCounts_SummedCorrectly;
    [Test]
    procedure ExtractAllResources_NoResources_ReturnsZero;
    [Test]
    procedure LoadFromStream_EmptyChunks_ZeroCounts;
    [Test]
    procedure ExtractAllResources_Threaded_ExtractsAll;
    [Test]
    procedure OnExtractProgress_InvokedDuringExtraction;
    [Test]
    procedure LoadFromFile_EmptyJson_ParsesMinimalFile;
    [Test]
    procedure LoadFromStream_InvalidJson_RaisesException;
    [Test]
    procedure LoadFromStream_RunSettings_Parsed;
    [Test]
    procedure LoadFromStream_IsThoughtChunk_Detected;
    [Test]
    procedure LoadFromStream_ChunkWithParts_Parsed;
    [Test]
    procedure GetResources_NoResources_ReturnsEmptyArray;
    [Test]
    procedure GetResourceCount_NoResources_ReturnsZero;
    [Test]
    procedure LoadFromFile_LargeFileWithResources_LazyLoadWorks;
    [Test]
    procedure ExtractAllResources_CustomPrefix_UsesPrefix;
  end;

implementation

uses
	Tests.GeminiFile.TestUtils;

{ TTestGeminiFileIntegration }

procedure TTestGeminiFileIntegration.Tailscale_ChunkCounts;
var
  LFile: TGeminiFile;
  LPath: string;
begin
  LPath := FindExample('Tailscale');
  if LPath = '' then
    Exit;

  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    Assert.AreEqual<Integer>(40, LFile.ChunkCount, 'ChunkCount');
    Assert.AreEqual<Integer>(14, LFile.UserChunkCount, 'UserChunkCount');
    Assert.AreEqual<Integer>(26, LFile.ModelChunkCount, 'ModelChunkCount');
    Assert.AreEqual<Integer>(68107, LFile.TotalTokenCount, 'TotalTokenCount');
    Assert.AreEqual<Integer>(0, LFile.GetResourceCount, 'ResourceCount');
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.Tailscale_RunSettings;
var
  LFile: TGeminiFile;
  LPath: string;
begin
  LPath := FindExample('Tailscale');
  if LPath = '' then
    Exit;

  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    Assert.AreEqual('models/gemini-2.5-pro', LFile.RunSettings.Model);
    Assert.AreEqual(Double(0.2), LFile.RunSettings.Temperature, 0.001);
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.Pushkin_ChunkCount;
var
  LFile: TGeminiFile;
  LPath: string;
begin
  // Try Cyrillic filename
  LPath := FindExample(#$041F#$0443#$0448#$043A#$0438#$043D + '''s Last Thoughts');
  if LPath = '' then
    Exit;

  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    Assert.AreEqual<Integer>(335, LFile.ChunkCount, 'ChunkCount');
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.Pushkin_SystemInstruction;
var
  LFile: TGeminiFile;
  LPath: string;
begin
  LPath := FindExample(#$041F#$0443#$0448#$043A#$0438#$043D + '''s Last Thoughts');
  if LPath = '' then
    Exit;

  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    Assert.IsTrue(LFile.SystemInstruction.StartsWith('# Unified'),
      'SystemInstruction should start with "# Unified"');
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.Gadget_ResourceCount;
var
  LFile: TGeminiFile;
  LPath: string;
  LResources: TArray<TGeminiResource>;
  I: Integer;
begin
  LPath := FindExample('Sberbank and Soyuzmultfilm Logo');
  if LPath = '' then
    Exit;

  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    LResources := LFile.GetResources;
    Assert.AreEqual<Integer>(2, Length(LResources), 'Should have 2 resources');
    for I := 0 to High(LResources) do
      Assert.AreEqual('image/png', LResources[I].MimeType,
        Format('Resource %d should be image/png', [I]));
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.Gadget_ResourceExtraction;
var
  LFile: TGeminiFile;
  LPath, LOutDir: string;
  LCount: Integer;
  LFiles: TStringDynArray;
begin
  LPath := FindExample('Sberbank and Soyuzmultfilm Logo');
  if LPath = '' then
    Exit;

  LOutDir := TPath.Combine(TPath.GetTempPath, 'GemViewTest_Gadget_' + TGUID.NewGuid.ToString);
  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    LCount := LFile.ExtractAllResources(LOutDir, False, 'resource');
    Assert.AreEqual<Integer>(2, LCount);

    LFiles := TDirectory.GetFiles(LOutDir);
    Assert.AreEqual<Integer>(2, Integer(Length(LFiles)), 'Should produce 2 files');

    // Each file should have a non-zero size
    Assert.IsTrue(TFile.GetSize(TPath.Combine(LOutDir, 'resource_000.png')) > 0,
      'Extracted file should be non-empty');
  finally
    LFile.Free;
    if TDirectory.Exists(LOutDir) then
      TDirectory.Delete(LOutDir, True);
  end;
end;

procedure TTestGeminiFileIntegration.Tigritsa_ResourceCount;
var
  LFile: TGeminiFile;
  LPath: string;
  LResources: TArray<TGeminiResource>;
begin
  LPath := FindExample('Creative Application Icon Design');
  if LPath = '' then
    Exit;

  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    LResources := LFile.GetResources;
    Assert.AreEqual<Integer>(1, Length(LResources), 'Should have 1 resource');
    Assert.AreEqual('image/png', LResources[0].MimeType, 'Resource should be image/png');
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.Tigritsa_RunSettings;
var
  LFile: TGeminiFile;
  LPath: string;
begin
  LPath := FindExample('Creative Application Icon Design');
  if LPath = '' then
    Exit;

  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    Assert.AreEqual('models/gemini-2.5-flash-image', LFile.RunSettings.Model);
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.LoadFromFile_NotFound_RaisesException;
begin
  Assert.WillRaise(
    procedure
    var
      LFile: TGeminiFile;
    begin
      LFile := TGeminiFile.Create;
      try
        LFile.LoadFromFile('nonexistent_file_that_does_not_exist');
      finally
        LFile.Free;
      end;
    end,
    EFileNotFoundException, '');
end;

procedure TTestGeminiFileIntegration.Create_WithCustomParserAndExtractor;
var
  LFile: TGeminiFile;
  LParser: IGeminiFileParser;
  LExtractor: IGeminiResourceExtractor;
  LStream: TStringStream;
begin
  LParser := TGeminiFileParser.Create;
  LExtractor := TGeminiResourceExtractor.Create;
  LFile := TGeminiFile.Create(LParser, LExtractor);
  try
    LStream := TStringStream.Create('{"chunkedPrompt":{"chunks":[]}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Assert.AreEqual<Integer>(0, LFile.ChunkCount);
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.GetResources_PartsInlineDataFallback;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
  LResources: TArray<TGeminiResource>;
begin
  // Chunk with InlineData in parts but no chunk-level InlineImage
  // Exercises the fallback path in TGeminiFile.GetResources
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"chunkedPrompt":{"chunks":[{"text":"","role":"user","parts":[' +
      '{"text":"test","inlineData":{"mimeType":"image/png","data":"AAAA"}}' +
      ']}]}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    LResources := LFile.GetResources;
    Assert.AreEqual<Integer>(1, Length(LResources),
      'Should find 1 resource from parts inlineData fallback');
    Assert.AreEqual('image/png', LResources[0].MimeType);
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.GetResourceCount_MatchesGetResourcesLength;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
begin
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"chunkedPrompt":{"chunks":[' +
      '{"text":"q","role":"user","parts":[' +
      '{"text":"t","inlineData":{"mimeType":"image/png","data":"AAAA"}}' +
      ']},{"text":"a","role":"model"}]}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Assert.AreEqual<Integer>(Length(LFile.GetResources), LFile.GetResourceCount,
      'GetResourceCount must match Length(GetResources)');
    Assert.AreEqual<Integer>(1, LFile.GetResourceCount);
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.LoadFromStream_SystemInstruction_Parsed;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
begin
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"systemInstruction":{"text":"Be concise."},' +
      '"chunkedPrompt":{"chunks":[]}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Assert.AreEqual('Be concise.', LFile.SystemInstruction);
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.LoadFromStream_MultipleRoles_CorrectCounts;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
begin
  // 3 user chunks + 2 model chunks = 5 total
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"chunkedPrompt":{"chunks":[' +
      '{"text":"u1","role":"user"},' +
      '{"text":"m1","role":"model"},' +
      '{"text":"u2","role":"user"},' +
      '{"text":"m2","role":"model"},' +
      '{"text":"u3","role":"user"}' +
      ']}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Assert.AreEqual<Integer>(5, LFile.ChunkCount);
    Assert.AreEqual<Integer>(3, LFile.UserChunkCount);
    Assert.AreEqual<Integer>(2, LFile.ModelChunkCount);
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.LoadFromStream_TokenCounts_SummedCorrectly;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
begin
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"chunkedPrompt":{"chunks":[' +
      '{"text":"u1","role":"user","tokenCount":100},' +
      '{"text":"m1","role":"model","tokenCount":250},' +
      '{"text":"u2","role":"user","tokenCount":50}' +
      ']}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Assert.AreEqual<Integer>(400, LFile.TotalTokenCount, 'Token counts should sum to 400');
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.ExtractAllResources_NoResources_ReturnsZero;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
  LOutDir: string;
begin
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"chunkedPrompt":{"chunks":[{"text":"hello","role":"user"}]}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    LOutDir := TPath.Combine(TPath.GetTempPath, 'GemViewTest_NoRes_' + TGUID.NewGuid.ToString);
    try
      Assert.AreEqual<Integer>(0, LFile.ExtractAllResources(LOutDir, False));
    finally
      if TDirectory.Exists(LOutDir) then
        TDirectory.Delete(LOutDir, True);
    end;
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.LoadFromStream_EmptyChunks_ZeroCounts;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
begin
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"chunkedPrompt":{"chunks":[]}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Assert.AreEqual<Integer>(0, LFile.ChunkCount);
    Assert.AreEqual<Integer>(0, LFile.UserChunkCount);
    Assert.AreEqual<Integer>(0, LFile.ModelChunkCount);
    Assert.AreEqual<Integer>(0, LFile.TotalTokenCount);
    Assert.AreEqual<Integer>(0, LFile.GetResourceCount);
    Assert.AreEqual<Integer>(0, Length(LFile.GetResources));
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.ExtractAllResources_Threaded_ExtractsAll;
var
  LFile: TGeminiFile;
  LPath, LOutDir: string;
  LCount: Integer;
  LFiles: TStringDynArray;
begin
  LPath := FindExample('Sberbank and Soyuzmultfilm Logo');
  if LPath = '' then
    Exit;

  LOutDir := TPath.Combine(TPath.GetTempPath, 'GemViewTest_Threaded_' + TGUID.NewGuid.ToString);
  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    // Threaded extraction (default = True)
    LCount := LFile.ExtractAllResources(LOutDir, True, 'resource');
    Assert.AreEqual<Integer>(2, LCount);

    LFiles := TDirectory.GetFiles(LOutDir);
    Assert.AreEqual<Integer>(2, Integer(Length(LFiles)), 'Should produce 2 files');
  finally
    LFile.Free;
    if TDirectory.Exists(LOutDir) then
      TDirectory.Delete(LOutDir, True);
  end;
end;

procedure TTestGeminiFileIntegration.OnExtractProgress_InvokedDuringExtraction;
var
  LFile: TGeminiFile;
  LPath, LOutDir: string;
  LCallCount: Integer;
begin
  LPath := FindExample('Sberbank and Soyuzmultfilm Logo');
  if LPath = '' then
    Exit;

  LCallCount := 0;
  LOutDir := TPath.Combine(TPath.GetTempPath, 'GemViewTest_Progress_' + TGUID.NewGuid.ToString);
  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    LFile.OnExtractProgress :=
      procedure(AIndex, ATotal: Integer; const AFileName: string)
      begin
        Inc(LCallCount);
      end;
    LFile.ExtractAllResources(LOutDir, False, 'resource');
    Assert.IsTrue(LCallCount > 0, 'Progress callback should be invoked at least once');
  finally
    LFile.Free;
    if TDirectory.Exists(LOutDir) then
      TDirectory.Delete(LOutDir, True);
  end;
end;

procedure TTestGeminiFileIntegration.LoadFromFile_EmptyJson_ParsesMinimalFile;
var
  LFile: TGeminiFile;
  LTempFile: string;
begin
  // Create a minimal valid Gemini JSON file on disk
  LTempFile := TPath.Combine(TPath.GetTempPath, 'GemViewTest_EmptyJson_' + TGUID.NewGuid.ToString);
  try
    TFile.WriteAllText(LTempFile, '{"chunkedPrompt":{"chunks":[]}}', TEncoding.UTF8);
    LFile := TGeminiFile.Create;
    try
      LFile.LoadFromFile(LTempFile);
      Assert.AreEqual<Integer>(0, LFile.ChunkCount);
      Assert.AreEqual('', LFile.SystemInstruction);
    finally
      LFile.Free;
    end;
  finally
    if TFile.Exists(LTempFile) then
      TFile.Delete(LTempFile);
  end;
end;

procedure TTestGeminiFileIntegration.LoadFromStream_InvalidJson_RaisesException;
begin
  Assert.WillRaise(
    procedure
    var
      LFile: TGeminiFile;
      LStream: TStringStream;
    begin
      LFile := TGeminiFile.Create;
      try
        LStream := TStringStream.Create('this is not valid json at all', TEncoding.UTF8);
        try
          LFile.LoadFromStream(LStream);
        finally
          LStream.Free;
        end;
      finally
        LFile.Free;
      end;
    end,
    EGeminiParseError, '');
end;

procedure TTestGeminiFileIntegration.LoadFromStream_RunSettings_Parsed;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
begin
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"runSettings":{"model":"models/gemini-2.0-flash","temperature":0.75},' +
      '"chunkedPrompt":{"chunks":[]}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Assert.AreEqual('models/gemini-2.0-flash', LFile.RunSettings.Model);
    Assert.AreEqual(Double(0.75), LFile.RunSettings.Temperature, 0.001);
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.LoadFromStream_IsThoughtChunk_Detected;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
begin
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"chunkedPrompt":{"chunks":[' +
      '{"text":"hello","role":"user"},' +
      '{"text":"thinking...","role":"model","isThought":true},' +
      '{"text":"answer","role":"model"}' +
      ']}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Assert.AreEqual<Integer>(3, LFile.ChunkCount);
    Assert.IsTrue(LFile.Chunks[1].IsThought, 'Second chunk should be a thought');
    Assert.IsFalse(LFile.Chunks[0].IsThought, 'First chunk should not be a thought');
    Assert.IsFalse(LFile.Chunks[2].IsThought, 'Third chunk should not be a thought');
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.LoadFromStream_ChunkWithParts_Parsed;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
begin
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"chunkedPrompt":{"chunks":[' +
      '{"text":"q","role":"user","parts":[' +
      '{"text":"part one"},{"text":"part two"}' +
      ']}]}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Assert.AreEqual<Integer>(1, LFile.ChunkCount);
    Assert.AreEqual<Integer>(2, LFile.Chunks[0].Parts.Count, 'Chunk should have 2 parts');
    Assert.AreEqual('part one', LFile.Chunks[0].Parts[0].Text);
    Assert.AreEqual('part two', LFile.Chunks[0].Parts[1].Text);
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.GetResources_NoResources_ReturnsEmptyArray;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
  LResources: TArray<TGeminiResource>;
begin
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"chunkedPrompt":{"chunks":[' +
      '{"text":"hello","role":"user"},{"text":"hi","role":"model"}' +
      ']}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    LResources := LFile.GetResources;
    Assert.AreEqual<Integer>(0, Length(LResources), 'Plain conversation should have no resources');
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.GetResourceCount_NoResources_ReturnsZero;
var
  LFile: TGeminiFile;
  LStream: TStringStream;
begin
  LFile := TGeminiFile.Create;
  try
    LStream := TStringStream.Create(
      '{"chunkedPrompt":{"chunks":[{"text":"hello","role":"user"}]}}', TEncoding.UTF8);
    try
      LFile.LoadFromStream(LStream);
    finally
      LStream.Free;
    end;
    Assert.AreEqual<Integer>(0, LFile.GetResourceCount);
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.LoadFromFile_LargeFileWithResources_LazyLoadWorks;
var
  LFile: TGeminiFile;
  LPath: string;
  LResources: TArray<TGeminiResource>;
begin
  // Uses a real example file with embedded images to exercise the lazy loading path
  LPath := FindExample('Sberbank and Soyuzmultfilm Logo');
  if LPath = '' then
    Exit;

  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    LResources := LFile.GetResources;
    Assert.AreEqual<Integer>(2, Length(LResources), 'Should find 2 lazy resources');
    // Verify lazy resources can decode -- accessing Base64Data triggers lazy load
    Assert.IsTrue(Length(LResources[0].Base64Data) > 0, 'Lazy resource should decode on access');
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.ExtractAllResources_CustomPrefix_UsesPrefix;
var
  LFile: TGeminiFile;
  LPath, LOutDir: string;
  LCount: Integer;
begin
  LPath := FindExample('Sberbank and Soyuzmultfilm Logo');
  if LPath = '' then
    Exit;

  LOutDir := TPath.Combine(TPath.GetTempPath, 'GemViewTest_Prefix_' + TGUID.NewGuid.ToString);
  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    LCount := LFile.ExtractAllResources(LOutDir, False, 'img');
    Assert.AreEqual<Integer>(2, LCount);
    // Check that extracted files use the custom prefix
    Assert.IsTrue(TFile.Exists(TPath.Combine(LOutDir, 'img_000.png')),
      'Extracted file should use custom prefix "img"');
  finally
    LFile.Free;
    if TDirectory.Exists(LOutDir) then
      TDirectory.Delete(LOutDir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGeminiFileIntegration);

end.
