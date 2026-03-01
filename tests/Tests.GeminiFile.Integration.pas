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
  private
    function ExamplesDir: string;
    function FindExample(const AName: string): string;
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
  end;

implementation

{ TTestGeminiFileIntegration }

function TTestGeminiFileIntegration.ExamplesDir: string;
begin
  // Navigate from tests/Win64/Debug/ up to project root, then into examples
  // Full path: <root>/tests/Win64/Debug/GemViewTests.exe
  // GetDirectoryName x1: <root>/tests/Win64/Debug
  // GetDirectoryName x2: <root>/tests/Win64
  // GetDirectoryName x3: <root>/tests
  // GetDirectoryName x4: <root>
  Result := TPath.Combine(
    TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
      TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
    'examples');
  // Fallback: try relative path from working directory
  if not TDirectory.Exists(Result) then
    Result := TPath.GetFullPath('..\examples');
end;

/// <summary>
///   Attempts to find an example file by name. Returns empty string if not found.
/// </summary>
function TTestGeminiFileIntegration.FindExample(const AName: string): string;
begin
  Result := TPath.Combine(ExamplesDir, AName);
  if FileExists(Result) then
    Exit;
  Result := '';
end;

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
  LPath := FindExample('Gadget Hackwrench In Tulle Dress');
  if LPath = '' then
    Exit;

  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    LResources := LFile.GetResources;
    Assert.AreEqual<Integer>(4, Length(LResources), 'Should have 4 resources');
    for I := 0 to High(LResources) do
      Assert.AreEqual('image/jpeg', LResources[I].MimeType,
        Format('Resource %d should be image/jpeg', [I]));
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
  LPath := FindExample('Gadget Hackwrench In Tulle Dress');
  if LPath = '' then
    Exit;

  LOutDir := TPath.Combine(TPath.GetTempPath, 'GemViewTest_Gadget_' + TGUID.NewGuid.ToString);
  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    LCount := LFile.ExtractAllResources(LOutDir, False, 'resource');
    Assert.AreEqual<Integer>(4, LCount);

    LFiles := TDirectory.GetFiles(LOutDir);
    Assert.AreEqual<Integer>(4, Integer(Length(LFiles)), 'Should produce 4 files');

    // Each file should have a non-zero size
    Assert.IsTrue(TFile.GetSize(TPath.Combine(LOutDir, 'resource_000.jpg')) > 0,
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
  I: Integer;
begin
  LPath := FindExample(
    #$0422#$0438#$0433#$0440#$0438#$0446#$0430 + ', ' +
    #$041F#$043B#$044E#$0449 + ', ' +
    #$041F#$0443#$0448#$043A#$0438#$043D + ', ' +
    #$041B#$0430#$0442#$044B#$043D#$044C + ', ' +
    #$0413#$0435#$0440#$0431);
  if LPath = '' then
    Exit;

  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    LResources := LFile.GetResources;
    Assert.AreEqual<Integer>(4, Length(LResources), 'Should have 4 resources');
    for I := 0 to High(LResources) do
      Assert.AreEqual('image/png', LResources[I].MimeType,
        Format('Resource %d should be image/png', [I]));
  finally
    LFile.Free;
  end;
end;

procedure TTestGeminiFileIntegration.Tigritsa_RunSettings;
var
  LFile: TGeminiFile;
  LPath: string;
begin
  LPath := FindExample(
    #$0422#$0438#$0433#$0440#$0438#$0446#$0430 + ', ' +
    #$041F#$043B#$044E#$0449 + ', ' +
    #$041F#$0443#$0448#$043A#$0438#$043D + ', ' +
    #$041B#$0430#$0442#$044B#$043D#$044C + ', ' +
    #$0413#$0435#$0440#$0431);
  if LPath = '' then
    Exit;

  LFile := TGeminiFile.Create;
  try
    LFile.LoadFromFile(LPath);
    Assert.AreEqual('models/gemini-2.5-flash-image-preview', LFile.RunSettings.Model);
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

initialization
  TDUnitX.RegisterTestFixture(TTestGeminiFileIntegration);

end.
