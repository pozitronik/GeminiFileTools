/// <summary>
///   Unit tests for GeminiFile.Types and BuildFormatterResourceInfos.
/// </summary>
unit Tests.GeminiFile.Types;

interface

uses
  System.Generics.Collections,
  DUnitX.TestFramework,
  GeminiFile.Types,
  GeminiFile.Model,
  GeminiFile;

type
  [TestFixture]
  TTestGeminiFileTypes = class
  public
    // MimeToExtension tests
    [Test]
    procedure MimeToExtension_Jpeg_ReturnsJpg;
    [Test]
    procedure MimeToExtension_Png_ReturnsPng;
    [Test]
    procedure MimeToExtension_Gif_ReturnsGif;
    [Test]
    procedure MimeToExtension_Webp_ReturnsWebp;
    [Test]
    procedure MimeToExtension_Pdf_ReturnsPdf;
    [Test]
    procedure MimeToExtension_Unknown_ReturnsBin;
    [Test]
    procedure MimeToExtension_CaseInsensitive;
    [Test]
    procedure MimeToExtension_Empty_ReturnsBin;
    [Test]
    procedure MimeToExtension_Bmp_ReturnsBmp;
    [Test]
    procedure MimeToExtension_Svg_ReturnsSvg;
    [Test]
    procedure MimeToExtension_Tiff_ReturnsTiff;
    [Test]
    procedure MimeToExtension_Mp3_ReturnsMp3;
    [Test]
    procedure MimeToExtension_Wav_ReturnsWav;
    [Test]
    procedure MimeToExtension_Ogg_ReturnsOgg;
    [Test]
    procedure MimeToExtension_Mp4_ReturnsMp4;
    [Test]
    procedure MimeToExtension_Webm_ReturnsWebm;
    [Test]
    procedure MimeToExtension_Json_ReturnsJson;
    [Test]
    procedure MimeToExtension_Html_ReturnsHtml;
    [Test]
    procedure MimeToExtension_Csv_ReturnsCsv;

    // FormatCreateTime tests
    [Test]
    procedure FormatCreateTime_Zero_ReturnsEmpty;

    [Test]
    procedure FormatCreateTime_NonZero_ReturnsFormattedString;

    // FormatByteSize tests
    [Test]
    procedure FormatByteSize_Bytes;
    [Test]
    procedure FormatByteSize_KB;
    [Test]
    procedure FormatByteSize_MB;
    [Test]
    procedure FormatByteSize_GB;
    [Test]
    procedure FormatByteSize_Zero;

    // FindResourceForChunk tests
    [Test]
    procedure FindResourceForChunk_Found_ReturnsTrueAndInfo;
    [Test]
    procedure FindResourceForChunk_NotFound_ReturnsFalse;
    [Test]
    procedure FindResourceForChunk_EmptyArray_ReturnsFalse;
    [Test]
    procedure FindResourceForChunk_MultipleResources_FindsCorrectOne;

    // ResourcePadWidth tests
    [Test]
    procedure ResourcePadWidth_SmallCount_ReturnsMinimum3;
    [Test]
    procedure ResourcePadWidth_LargeCount_ReturnsDigitCount;
  end;

  [TestFixture]
  TTestBuildFormatterResourceInfos = class
  private
    FChunks: TObjectList<TGeminiChunk>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure EmptyResources_ReturnsEmptyArray;
    [Test]
    procedure SingleResource_CorrectFields;
    [Test]
    procedure ThinkingResource_GetsThinkSubdir;
    [Test]
    procedure NonThinkingResource_GetsResourcesDir;
    [Test]
    procedure Base64Data_AlwaysEmpty;
    [Test]
    procedure OutOfBoundsChunkIndex_NotThinking;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils;

{ TTestGeminiFileTypes }

procedure TTestGeminiFileTypes.MimeToExtension_Jpeg_ReturnsJpg;
begin
  Assert.AreEqual('.jpg', MimeToExtension('image/jpeg'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Png_ReturnsPng;
begin
  Assert.AreEqual('.png', MimeToExtension('image/png'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Gif_ReturnsGif;
begin
  Assert.AreEqual('.gif', MimeToExtension('image/gif'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Webp_ReturnsWebp;
begin
  Assert.AreEqual('.webp', MimeToExtension('image/webp'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Pdf_ReturnsPdf;
begin
  Assert.AreEqual('.pdf', MimeToExtension('application/pdf'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Unknown_ReturnsBin;
begin
  Assert.AreEqual('.bin', MimeToExtension('application/octet-stream'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_CaseInsensitive;
begin
  Assert.AreEqual('.jpg', MimeToExtension('IMAGE/JPEG'));
  Assert.AreEqual('.png', MimeToExtension('Image/Png'));
  Assert.AreEqual('.pdf', MimeToExtension('APPLICATION/PDF'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Empty_ReturnsBin;
begin
  Assert.AreEqual('.bin', MimeToExtension(''));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Bmp_ReturnsBmp;
begin
  Assert.AreEqual('.bmp', MimeToExtension('image/bmp'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Svg_ReturnsSvg;
begin
  Assert.AreEqual('.svg', MimeToExtension('image/svg+xml'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Tiff_ReturnsTiff;
begin
  Assert.AreEqual('.tiff', MimeToExtension('image/tiff'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Mp3_ReturnsMp3;
begin
  Assert.AreEqual('.mp3', MimeToExtension('audio/mpeg'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Wav_ReturnsWav;
begin
  Assert.AreEqual('.wav', MimeToExtension('audio/wav'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Ogg_ReturnsOgg;
begin
  Assert.AreEqual('.ogg', MimeToExtension('audio/ogg'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Mp4_ReturnsMp4;
begin
  Assert.AreEqual('.mp4', MimeToExtension('video/mp4'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Webm_ReturnsWebm;
begin
  Assert.AreEqual('.webm', MimeToExtension('video/webm'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Json_ReturnsJson;
begin
  Assert.AreEqual('.json', MimeToExtension('application/json'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Html_ReturnsHtml;
begin
  Assert.AreEqual('.html', MimeToExtension('text/html'));
end;

procedure TTestGeminiFileTypes.MimeToExtension_Csv_ReturnsCsv;
begin
  Assert.AreEqual('.csv', MimeToExtension('text/csv'));
end;

procedure TTestGeminiFileTypes.FormatCreateTime_Zero_ReturnsEmpty;
begin
  Assert.AreEqual('', FormatCreateTime(0));
end;

procedure TTestGeminiFileTypes.FormatByteSize_Bytes;
begin
  Assert.AreEqual('512 B', FormatByteSize(512));
  Assert.AreEqual('1 B', FormatByteSize(1));
  Assert.AreEqual('1023 B', FormatByteSize(1023));
end;

procedure TTestGeminiFileTypes.FormatByteSize_KB;
begin
  Assert.AreEqual('1.0 KB', FormatByteSize(1024));
  Assert.AreEqual('1.5 KB', FormatByteSize(1536));
  Assert.AreEqual('999.0 KB', FormatByteSize(999 * 1024));
end;

procedure TTestGeminiFileTypes.FormatByteSize_MB;
begin
  Assert.AreEqual('1.0 MB', FormatByteSize(1024 * 1024));
  Assert.AreEqual('2.5 MB', FormatByteSize(Round(2.5 * 1024 * 1024)));
end;

procedure TTestGeminiFileTypes.FormatByteSize_GB;
begin
  Assert.AreEqual('1.00 GB', FormatByteSize(Int64(1024) * 1024 * 1024));
  Assert.AreEqual('2.50 GB', FormatByteSize(Round(2.5 * 1024 * 1024 * 1024)));
end;

procedure TTestGeminiFileTypes.FormatByteSize_Zero;
begin
  Assert.AreEqual('0 B', FormatByteSize(0));
end;

procedure TTestGeminiFileTypes.FormatCreateTime_NonZero_ReturnsFormattedString;
var
  LDT: TDateTime;
begin
  LDT := EncodeDate(2026, 2, 26) + EncodeTime(0, 1, 2, 0);
  Assert.AreEqual('2026-02-26 00:01:02', FormatCreateTime(LDT));
end;

procedure TTestGeminiFileTypes.FindResourceForChunk_Found_ReturnsTrueAndInfo;
var
  LResources: TArray<TFormatterResourceInfo>;
  LInfo: TFormatterResourceInfo;
begin
  SetLength(LResources, 1);
  LResources[0].ChunkIndex := 5;
  LResources[0].FileName := 'resource_000.png';
  LResources[0].MimeType := 'image/png';
  Assert.IsTrue(FindResourceForChunk(LResources, 5, LInfo));
  Assert.AreEqual('resource_000.png', LInfo.FileName);
  Assert.AreEqual('image/png', LInfo.MimeType);
end;

procedure TTestGeminiFileTypes.FindResourceForChunk_NotFound_ReturnsFalse;
var
  LResources: TArray<TFormatterResourceInfo>;
  LInfo: TFormatterResourceInfo;
begin
  SetLength(LResources, 1);
  LResources[0].ChunkIndex := 5;
  Assert.IsFalse(FindResourceForChunk(LResources, 99, LInfo));
end;

procedure TTestGeminiFileTypes.FindResourceForChunk_EmptyArray_ReturnsFalse;
var
  LResources: TArray<TFormatterResourceInfo>;
  LInfo: TFormatterResourceInfo;
begin
  SetLength(LResources, 0);
  Assert.IsFalse(FindResourceForChunk(LResources, 0, LInfo));
end;

procedure TTestGeminiFileTypes.FindResourceForChunk_MultipleResources_FindsCorrectOne;
var
  LResources: TArray<TFormatterResourceInfo>;
  LInfo: TFormatterResourceInfo;
begin
  SetLength(LResources, 3);
  LResources[0].ChunkIndex := 2;
  LResources[0].FileName := 'first.png';
  LResources[1].ChunkIndex := 7;
  LResources[1].FileName := 'second.jpg';
  LResources[2].ChunkIndex := 12;
  LResources[2].FileName := 'third.gif';
  Assert.IsTrue(FindResourceForChunk(LResources, 7, LInfo));
  Assert.AreEqual('second.jpg', LInfo.FileName);
end;

procedure TTestGeminiFileTypes.ResourcePadWidth_SmallCount_ReturnsMinimum3;
begin
  Assert.AreEqual<Integer>(3, ResourcePadWidth(1));
  Assert.AreEqual<Integer>(3, ResourcePadWidth(99));
  Assert.AreEqual<Integer>(3, ResourcePadWidth(999));
end;

procedure TTestGeminiFileTypes.ResourcePadWidth_LargeCount_ReturnsDigitCount;
begin
  Assert.AreEqual<Integer>(4, ResourcePadWidth(1000));
  Assert.AreEqual<Integer>(4, ResourcePadWidth(9999));
  Assert.AreEqual<Integer>(5, ResourcePadWidth(10000));
end;

// ========================================================================
// TTestBuildFormatterResourceInfos
// ========================================================================

procedure TTestBuildFormatterResourceInfos.Setup;
begin
  FChunks := TObjectList<TGeminiChunk>.Create(True);
end;

procedure TTestBuildFormatterResourceInfos.TearDown;
begin
  FChunks.Free;
end;

procedure TTestBuildFormatterResourceInfos.EmptyResources_ReturnsEmptyArray;
var
  LResult: TArray<TFormatterResourceInfo>;
begin
  LResult := BuildFormatterResourceInfos(nil, FChunks);
  Assert.AreEqual<Integer>(0, Length(LResult));
end;

procedure TTestBuildFormatterResourceInfos.SingleResource_CorrectFields;
var
  LChunk: TGeminiChunk;
  LRes: TGeminiResource;
  LResources: TArray<TGeminiResource>;
  LResult: TArray<TFormatterResourceInfo>;
begin
  LChunk := TGeminiChunk.Create;
  LChunk.Role := grModel;
  FChunks.Add(LChunk);

  LRes := TGeminiResource.Create('image/png', 'AAAA', 0);
  LResources := TArray<TGeminiResource>.Create(LRes);

  LResult := BuildFormatterResourceInfos(LResources, FChunks);
  try
    Assert.AreEqual<Integer>(1, Length(LResult));
    Assert.AreEqual('image/png', LResult[0].MimeType);
    Assert.AreEqual<Integer>(0, LResult[0].ChunkIndex);
    Assert.IsTrue(LResult[0].FileName.Contains('resource_000'));
    Assert.IsTrue(LResult[0].FileName.EndsWith('.png'));
  finally
    LRes.Free;
  end;
end;

procedure TTestBuildFormatterResourceInfos.ThinkingResource_GetsThinkSubdir;
var
  LChunk: TGeminiChunk;
  LRes: TGeminiResource;
  LResources: TArray<TGeminiResource>;
  LResult: TArray<TFormatterResourceInfo>;
begin
  LChunk := TGeminiChunk.Create;
  LChunk.Role := grModel;
  LChunk.IsThought := True;
  FChunks.Add(LChunk);

  LRes := TGeminiResource.Create('image/png', 'AAAA', 0);
  LResources := TArray<TGeminiResource>.Create(LRes);

  LResult := BuildFormatterResourceInfos(LResources, FChunks);
  try
    Assert.IsTrue(LResult[0].FileName.StartsWith('resources/think/'),
      'Thinking resource should have think/ subdirectory');
    Assert.IsTrue(LResult[0].IsThinking);
  finally
    LRes.Free;
  end;
end;

procedure TTestBuildFormatterResourceInfos.NonThinkingResource_GetsResourcesDir;
var
  LChunk: TGeminiChunk;
  LRes: TGeminiResource;
  LResources: TArray<TGeminiResource>;
  LResult: TArray<TFormatterResourceInfo>;
begin
  LChunk := TGeminiChunk.Create;
  LChunk.Role := grModel;
  FChunks.Add(LChunk);

  LRes := TGeminiResource.Create('image/jpeg', 'AAAA', 0);
  LResources := TArray<TGeminiResource>.Create(LRes);

  LResult := BuildFormatterResourceInfos(LResources, FChunks);
  try
    Assert.IsTrue(LResult[0].FileName.StartsWith('resources/resource_'),
      'Non-thinking resource should be in resources/ directly');
    Assert.IsFalse(LResult[0].IsThinking);
  finally
    LRes.Free;
  end;
end;

procedure TTestBuildFormatterResourceInfos.Base64Data_AlwaysEmpty;
var
  LChunk: TGeminiChunk;
  LRes: TGeminiResource;
  LResources: TArray<TGeminiResource>;
  LResult: TArray<TFormatterResourceInfo>;
begin
  LChunk := TGeminiChunk.Create;
  FChunks.Add(LChunk);

  LRes := TGeminiResource.Create('image/png', 'SomeLargeBase64Data', 0);
  LResources := TArray<TGeminiResource>.Create(LRes);

  LResult := BuildFormatterResourceInfos(LResources, FChunks);
  try
    Assert.AreEqual('', LResult[0].Base64Data,
      'Base64Data should always be empty (loaded on demand by caller)');
  finally
    LRes.Free;
  end;
end;

procedure TTestBuildFormatterResourceInfos.OutOfBoundsChunkIndex_NotThinking;
var
  LRes: TGeminiResource;
  LResources: TArray<TGeminiResource>;
  LResult: TArray<TFormatterResourceInfo>;
begin
  // Chunk index 99 but empty chunk list
  LRes := TGeminiResource.Create('image/png', 'AAAA', 99);
  LResources := TArray<TGeminiResource>.Create(LRes);

  LResult := BuildFormatterResourceInfos(LResources, FChunks);
  try
    Assert.IsFalse(LResult[0].IsThinking,
      'Out-of-bounds chunk index should default to non-thinking');
    Assert.IsTrue(LResult[0].FileName.StartsWith('resources/resource_'));
  finally
    LRes.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGeminiFileTypes);
  TDUnitX.RegisterTestFixture(TTestBuildFormatterResourceInfos);

end.
