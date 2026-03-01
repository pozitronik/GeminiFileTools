/// <summary>
///   Unit tests for TGeminiResource: decode, save, release, sizes.
/// </summary>
unit Tests.GeminiFile.Resource;

interface

uses
  System.SysUtils,
  System.Classes,
  DUnitX.TestFramework,
  GeminiFile.Types,
  GeminiFile.Model;

type
  [TestFixture]
  TTestGeminiResource = class
  public
    [Test]
    procedure Create_SetsPropertiesCorrectly;
    [Test]
    procedure Decode_ProducesCorrectBytes;
    [Test]
    procedure Decode_ClearsBase64Data;
    [Test]
    procedure DecodedSize_EstimateFromBase64Length;
    [Test]
    procedure DecodedSize_ExactAfterDecode;
    [Test]
    procedure GetFileExtension_DelegatesToMimeToExtension;
    [Test]
    procedure SaveToStream_WritesDecodedData;
    [Test]
    procedure ReleaseBase64_ClearsBase64KeepsDecoded;
    [Test]
    procedure ReleaseAll_ClearsEverything;
    [Test]
    procedure Decode_OnEmptyData_RaisesError;
  end;

implementation

uses
  System.NetEncoding;

{ TTestGeminiResource }

procedure TTestGeminiResource.Create_SetsPropertiesCorrectly;
var
  LRes: TGeminiResource;
begin
  LRes := TGeminiResource.Create('image/png', 'AAAA', 5);
  try
    Assert.AreEqual('image/png', LRes.MimeType);
    Assert.AreEqual(5, LRes.ChunkIndex);
    Assert.IsFalse(LRes.IsDecoded);
    Assert.IsTrue(LRes.Base64Size > 0);
  finally
    LRes.Free;
  end;
end;

procedure TTestGeminiResource.Decode_ProducesCorrectBytes;
var
  LRes: TGeminiResource;
  LExpected: TBytes;
  LStream: TMemoryStream;
  LActual: TBytes;
begin
  // "Hello" in base64 is "SGVsbG8="
  LExpected := TEncoding.UTF8.GetBytes('Hello');
  LRes := TGeminiResource.Create('text/plain', 'SGVsbG8=', 0);
  try
    LRes.Decode;
    Assert.IsTrue(LRes.IsDecoded);

    LStream := TMemoryStream.Create;
    try
      LRes.SaveToStream(LStream);
      SetLength(LActual, LStream.Size);
      LStream.Position := 0;
      LStream.ReadBuffer(LActual[0], LStream.Size);
      Assert.AreEqual(Length(LExpected), Length(LActual));
      Assert.AreEqual(LExpected[0], LActual[0]);
      Assert.AreEqual(LExpected[4], LActual[4]);
    finally
      LStream.Free;
    end;
  finally
    LRes.Free;
  end;
end;

procedure TTestGeminiResource.Decode_ClearsBase64Data;
var
  LRes: TGeminiResource;
begin
  LRes := TGeminiResource.Create('image/png', 'AAAA', 0);
  try
    Assert.IsTrue(LRes.Base64Size > 0, 'Base64Size should be >0 before decode');
    LRes.Decode;
    Assert.AreEqual(Int64(0), LRes.Base64Size, 'Base64Size should be 0 after decode');
  finally
    LRes.Free;
  end;
end;

procedure TTestGeminiResource.DecodedSize_EstimateFromBase64Length;
var
  LRes: TGeminiResource;
  LEstimate: Int64;
begin
  // 8 base64 chars -> estimate = (8 * 3) div 4 = 6
  LRes := TGeminiResource.Create('image/png', 'SGVsbG8=', 0);
  try
    LEstimate := LRes.DecodedSize;
    Assert.IsTrue(LEstimate > 0, 'Estimate should be > 0');
    Assert.AreEqual(Int64(6), LEstimate, 'Estimate for 8-char b64 should be 6');
  finally
    LRes.Free;
  end;
end;

procedure TTestGeminiResource.DecodedSize_ExactAfterDecode;
var
  LRes: TGeminiResource;
begin
  // "Hello" = 5 bytes, base64 = "SGVsbG8="
  LRes := TGeminiResource.Create('text/plain', 'SGVsbG8=', 0);
  try
    LRes.Decode;
    Assert.AreEqual(Int64(5), LRes.DecodedSize, 'Decoded "Hello" should be 5 bytes');
  finally
    LRes.Free;
  end;
end;

procedure TTestGeminiResource.GetFileExtension_DelegatesToMimeToExtension;
var
  LRes: TGeminiResource;
begin
  LRes := TGeminiResource.Create('image/jpeg', 'AAAA', 0);
  try
    Assert.AreEqual('.jpg', LRes.GetFileExtension);
  finally
    LRes.Free;
  end;
end;

procedure TTestGeminiResource.SaveToStream_WritesDecodedData;
var
  LRes: TGeminiResource;
  LStream: TMemoryStream;
begin
  LRes := TGeminiResource.Create('text/plain', 'SGVsbG8=', 0);
  try
    LStream := TMemoryStream.Create;
    try
      LRes.SaveToStream(LStream);
      Assert.AreEqual(Int64(5), LStream.Size, 'Stream should contain 5 bytes');
    finally
      LStream.Free;
    end;
  finally
    LRes.Free;
  end;
end;

procedure TTestGeminiResource.ReleaseBase64_ClearsBase64KeepsDecoded;
var
  LRes: TGeminiResource;
begin
  LRes := TGeminiResource.Create('text/plain', 'SGVsbG8=', 0);
  try
    LRes.Decode;
    LRes.ReleaseBase64;
    Assert.AreEqual(Int64(0), LRes.Base64Size);
    Assert.IsTrue(LRes.IsDecoded, 'Should still be decoded');
    Assert.AreEqual(Int64(5), LRes.DecodedSize, 'Decoded data should be preserved');
  finally
    LRes.Free;
  end;
end;

procedure TTestGeminiResource.ReleaseAll_ClearsEverything;
var
  LRes: TGeminiResource;
begin
  LRes := TGeminiResource.Create('text/plain', 'SGVsbG8=', 0);
  try
    LRes.Decode;
    LRes.ReleaseAll;
    Assert.AreEqual(Int64(0), LRes.Base64Size);
    Assert.IsFalse(LRes.IsDecoded, 'IsDecoded should be False after ReleaseAll');
    Assert.AreEqual(Int64(0), LRes.DecodedSize, 'DecodedSize should be 0');
  finally
    LRes.Free;
  end;
end;

procedure TTestGeminiResource.Decode_OnEmptyData_RaisesError;
var
  LRes: TGeminiResource;
begin
  LRes := TGeminiResource.Create('text/plain', 'SGVsbG8=', 0);
  try
    LRes.Decode;      // first decode works
    LRes.ReleaseAll;  // clears everything
    Assert.WillRaise(
      procedure
      begin
        LRes.Decode;  // should raise because base64 is empty
      end,
      EGeminiParseError, '');
  finally
    LRes.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGeminiResource);

end.
