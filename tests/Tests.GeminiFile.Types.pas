/// <summary>
///   Unit tests for GeminiFile.Types: MimeToExtension and FormatByteSize.
/// </summary>
unit Tests.GeminiFile.Types;

interface

uses
  DUnitX.TestFramework,
  GeminiFile.Types;

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
  end;

implementation

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

initialization
  TDUnitX.RegisterTestFixture(TTestGeminiFileTypes);

end.
