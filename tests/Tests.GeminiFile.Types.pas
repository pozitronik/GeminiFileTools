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

initialization
  TDUnitX.RegisterTestFixture(TTestGeminiFileTypes);

end.
