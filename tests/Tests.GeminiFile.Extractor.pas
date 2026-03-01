/// <summary>
///   Unit tests for GeminiFile.Extractor: extraction, file naming, threading.
/// </summary>
unit Tests.GeminiFile.Extractor;

interface

uses
  System.SysUtils,
  System.Types,
  System.IOUtils,
  System.Classes,
  DUnitX.TestFramework,
  GeminiFile.Types,
  GeminiFile.Model,
  GeminiFile.Extractor;

type
  [TestFixture]
  TTestGeminiExtractor = class
  private
    FTempDir: string;
    FExtractor: IGeminiResourceExtractor;
    function MakeResource(const AMime, ABase64: string; AIdx: Integer): TGeminiResource;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure ExtractAll_NoResources_ReturnsZero;
    [Test]
    procedure ExtractAll_CreatesOutputDirectory;
    [Test]
    procedure ExtractAll_WritesFilesWithCorrectNames;
    [Test]
    procedure ExtractAll_WritesCorrectFileContent;
    [Test]
    procedure ExtractAll_SequentialMode_Works;
    [Test]
    procedure ExtractAll_ThreadedMode_SameResults;
  end;

implementation

{ TTestGeminiExtractor }

procedure TTestGeminiExtractor.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'GemViewTest_' + TGUID.NewGuid.ToString);
  FExtractor := TGeminiResourceExtractor.Create;
end;

procedure TTestGeminiExtractor.TearDown;
begin
  FExtractor := nil;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestGeminiExtractor.MakeResource(const AMime, ABase64: string;
  AIdx: Integer): TGeminiResource;
begin
  Result := TGeminiResource.Create(AMime, ABase64, AIdx);
end;

procedure TTestGeminiExtractor.ExtractAll_NoResources_ReturnsZero;
var
  LResources: TArray<TGeminiResource>;
  LCount: Integer;
begin
  SetLength(LResources, 0);
  LCount := FExtractor.ExtractAll(LResources, FTempDir, False, 'resource', nil);
  Assert.AreEqual<Integer>(0, LCount);
end;

procedure TTestGeminiExtractor.ExtractAll_CreatesOutputDirectory;
var
  LResources: TArray<TGeminiResource>;
  LRes: TGeminiResource;
begin
  LRes := MakeResource('text/plain', 'SGVsbG8=', 0);
  try
    LResources := TArray<TGeminiResource>.Create(LRes);
    Assert.IsFalse(TDirectory.Exists(FTempDir), 'Dir should not exist before extract');
    FExtractor.ExtractAll(LResources, FTempDir, False, 'resource', nil);
    Assert.IsTrue(TDirectory.Exists(FTempDir), 'Dir should exist after extract');
  finally
    LRes.Free;
  end;
end;

procedure TTestGeminiExtractor.ExtractAll_WritesFilesWithCorrectNames;
var
  LResources: TArray<TGeminiResource>;
  LRes1, LRes2: TGeminiResource;
  LFiles: TStringDynArray;
begin
  LRes1 := MakeResource('image/jpeg', 'SGVsbG8=', 0);
  LRes2 := MakeResource('image/png', 'SGVsbG8=', 1);
  try
    LResources := TArray<TGeminiResource>.Create(LRes1, LRes2);
    FExtractor.ExtractAll(LResources, FTempDir, False, 'img', nil);

    LFiles := TDirectory.GetFiles(FTempDir);
    Assert.AreEqual<Integer>(2, Length(LFiles));

    // Check that both expected files exist
    Assert.IsTrue(TFile.Exists(TPath.Combine(FTempDir, 'img_000.jpg')));
    Assert.IsTrue(TFile.Exists(TPath.Combine(FTempDir, 'img_001.png')));
  finally
    LRes1.Free;
    LRes2.Free;
  end;
end;

procedure TTestGeminiExtractor.ExtractAll_WritesCorrectFileContent;
var
  LResources: TArray<TGeminiResource>;
  LRes: TGeminiResource;
  LBytes: TBytes;
begin
  // "Hello" -> base64 "SGVsbG8="
  LRes := MakeResource('text/plain', 'SGVsbG8=', 0);
  try
    LResources := TArray<TGeminiResource>.Create(LRes);
    FExtractor.ExtractAll(LResources, FTempDir, False, 'resource', nil);

    LBytes := TFile.ReadAllBytes(TPath.Combine(FTempDir, 'resource_000.txt'));
    Assert.AreEqual<Integer>(5, Length(LBytes));
    Assert.AreEqual<Integer>(Ord('H'), LBytes[0]);
    Assert.AreEqual<Integer>(Ord('o'), LBytes[4]);
  finally
    LRes.Free;
  end;
end;

procedure TTestGeminiExtractor.ExtractAll_SequentialMode_Works;
var
  LResources: TArray<TGeminiResource>;
  LRes1, LRes2: TGeminiResource;
  LCount: Integer;
begin
  LRes1 := MakeResource('text/plain', 'SGVsbG8=', 0);
  LRes2 := MakeResource('text/plain', 'V29ybGQ=', 1); // "World"
  try
    LResources := TArray<TGeminiResource>.Create(LRes1, LRes2);
    LCount := FExtractor.ExtractAll(LResources, FTempDir, False, 'seq', nil);
    Assert.AreEqual<Integer>(2, LCount);
    Assert.IsTrue(TFile.Exists(TPath.Combine(FTempDir, 'seq_000.txt')));
    Assert.IsTrue(TFile.Exists(TPath.Combine(FTempDir, 'seq_001.txt')));
  finally
    LRes1.Free;
    LRes2.Free;
  end;
end;

procedure TTestGeminiExtractor.ExtractAll_ThreadedMode_SameResults;
var
  LResources: TArray<TGeminiResource>;
  LRes1, LRes2, LRes3: TGeminiResource;
  LCount: Integer;
  LBytes: TBytes;
begin
  LRes1 := MakeResource('text/plain', 'SGVsbG8=', 0); // "Hello"
  LRes2 := MakeResource('text/plain', 'V29ybGQ=', 1); // "World"
  LRes3 := MakeResource('text/plain', 'AQID', 2);      // bytes 1,2,3
  try
    LResources := TArray<TGeminiResource>.Create(LRes1, LRes2, LRes3);
    LCount := FExtractor.ExtractAll(LResources, FTempDir, True, 'par', nil);
    Assert.AreEqual<Integer>(3, LCount);

    // Verify all files exist
    Assert.IsTrue(TFile.Exists(TPath.Combine(FTempDir, 'par_000.txt')));
    Assert.IsTrue(TFile.Exists(TPath.Combine(FTempDir, 'par_001.txt')));
    Assert.IsTrue(TFile.Exists(TPath.Combine(FTempDir, 'par_002.txt')));

    // Verify content of first file
    LBytes := TFile.ReadAllBytes(TPath.Combine(FTempDir, 'par_000.txt'));
    Assert.AreEqual<Integer>(5, Length(LBytes));
  finally
    LRes1.Free;
    LRes2.Free;
    LRes3.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGeminiExtractor);

end.
