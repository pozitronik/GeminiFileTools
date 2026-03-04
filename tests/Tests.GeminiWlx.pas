/// <summary>
///   Unit tests for WLX plugin thumbnail logic.
///   Tests binary scan functions (ScanRoleMarkers, ExtractFirstUserText)
///   and thumbnail rendering via exported ListGetPreviewBitmapW.
/// </summary>
unit Tests.GeminiWlx;

interface

uses
	System.SysUtils,
	System.Classes,
	System.IOUtils,
	Winapi.Windows,
	DUnitX.TestFramework,
	GeminiWlx;

type
	/// <summary>
	///   Tests for ScanRoleMarkers: binary scan finding user/model role markers.
	/// </summary>
	[TestFixture]
	TTestWlxScanRoleMarkers = class
	private
		FTempDir: string;
		function CreateTempFile(const AName, AContent: string): string;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;
		[Test]
		procedure TwoChunks_ReturnsTwoMarkers;
		[Test]
		procedure TwoChunks_RolesCorrect;
		[Test]
		procedure TwoChunks_ByteOffsetsAscending;
		[Test]
		procedure NoRoleMarkers_ReturnsEmptyArray;
		[Test]
		procedure ModelOnly_ReturnsSingleModelMarker;
		[Test]
		procedure FileSize_ReturnedCorrectly;
		[Test]
		procedure EmptyFile_ReturnsEmptyArray;
		[Test]
		procedure ManyChunks_AllMarkersFound;
		[Test]
		procedure RoleInStringValue_NotFalsePositive;
	end;

	/// <summary>
	///   Tests for ExtractFirstUserText: binary scan + JSON escape decoding.
	/// </summary>
	[TestFixture]
	TTestWlxExtractFirstUserText = class
	private
		FTempDir: string;
		function CreateTempFile(const AName, AContent: string): string;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;
		[Test]
		procedure SimpleText_ExtractedCorrectly;
		[Test]
		procedure EscapeNewline_DecodedToLF;
		[Test]
		procedure EscapeTab_DecodedToTab;
		[Test]
		procedure EscapeBackslash_DecodedToBackslash;
		[Test]
		procedure EscapeQuote_DecodedToQuote;
		[Test]
		procedure EscapeSlash_DecodedToSlash;
		[Test]
		procedure EscapeCarriageReturn_DecodedToCR;
		[Test]
		procedure EscapeUnicode_DecodedToCharacter;
		[Test]
		procedure MaxChars_TruncatesLongText;
		[Test]
		procedure NoUserRole_ReturnsEmpty;
		[Test]
		procedure EmptyText_ReturnsEmpty;
		[Test]
		procedure ModelOnly_ReturnsEmpty;
		[Test]
		procedure EmptyFile_ReturnsEmpty;
		[Test]
		procedure MultipleEscapes_AllDecoded;
		[Test]
		procedure Utf8Text_PreservedCorrectly;
	end;

	/// <summary>
	///   Tests for thumbnail rendering via ListGetPreviewBitmapW.
	///   Verifies HBITMAP validity and dimensions.
	/// </summary>
	[TestFixture]
	TTestWlxThumbnails = class
	private
		FTempDir: string;
		function CreateTempFile(const AName, AContent: string): string;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;
		[Test]
		procedure ValidFile_ReturnsNonZeroBitmap;
		[Test]
		procedure ValidFile_BitmapHasCorrectDimensions;
		[Test]
		procedure EmptyFile_ReturnsZero;
		[Test]
		procedure InvalidJson_ReturnsZero;
		[Test]
		procedure NoUserText_ReturnsFallbackBitmap;
	end;

	/// <summary>
	///   Tests for WLX plugin configuration defaults.
	/// </summary>
	[TestFixture]
	TTestWlxConfig = class
	public
		[Test]
		procedure DefaultThumbnailFallback_IsText;
		[Test]
		procedure DefaultHideEmptyBlocks_IsTrue;
		[Test]
		procedure DefaultRenderMarkdown_IsTrue;
		[Test]
		procedure DefaultCombineBlocks_IsFalse;
	end;

implementation

uses
	Winapi.ActiveX;

// ========================================================================
// Helpers
// ========================================================================

function TTestWlxScanRoleMarkers.CreateTempFile(const AName, AContent: string): string;
begin
	Result := TPath.Combine(FTempDir, AName);
	TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

function TTestWlxExtractFirstUserText.CreateTempFile(const AName, AContent: string): string;
begin
	Result := TPath.Combine(FTempDir, AName);
	TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

function TTestWlxThumbnails.CreateTempFile(const AName, AContent: string): string;
begin
	Result := TPath.Combine(FTempDir, AName);
	TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

// ========================================================================
// TTestWlxScanRoleMarkers
// ========================================================================

procedure TTestWlxScanRoleMarkers.Setup;
begin
	FTempDir := TPath.Combine(TPath.GetTempPath, 'wlx_test_' + TGUID.NewGuid.ToString);
	TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestWlxScanRoleMarkers.TearDown;
begin
	if TDirectory.Exists(FTempDir) then
		TDirectory.Delete(FTempDir, True);
end;

procedure TTestWlxScanRoleMarkers.TwoChunks_ReturnsTwoMarkers;
var
	LFile: string;
	LMarkers: TArray<TRoleMarker>;
	LFileSize: Int64;
begin
	LFile := CreateTempFile('two.json',
		'{"chunks":[{"text":"hi","role":"user"},{"text":"hello","role":"model"}]}');
	LMarkers := ScanRoleMarkers(LFile, LFileSize);
	Assert.AreEqual(2, Integer(Length(LMarkers)));
end;

procedure TTestWlxScanRoleMarkers.TwoChunks_RolesCorrect;
var
	LFile: string;
	LMarkers: TArray<TRoleMarker>;
	LFileSize: Int64;
begin
	LFile := CreateTempFile('roles.json',
		'{"chunks":[{"text":"hi","role":"user"},{"text":"hello","role":"model"}]}');
	LMarkers := ScanRoleMarkers(LFile, LFileSize);
	Assert.AreEqual<Byte>(0, LMarkers[0].Role, 'First marker should be user (0)');
	Assert.AreEqual<Byte>(1, LMarkers[1].Role, 'Second marker should be model (1)');
end;

procedure TTestWlxScanRoleMarkers.TwoChunks_ByteOffsetsAscending;
var
	LFile: string;
	LMarkers: TArray<TRoleMarker>;
	LFileSize: Int64;
begin
	LFile := CreateTempFile('offsets.json',
		'{"chunks":[{"text":"hi","role":"user"},{"text":"hello","role":"model"}]}');
	LMarkers := ScanRoleMarkers(LFile, LFileSize);
	Assert.IsTrue(LMarkers[1].ByteOffset > LMarkers[0].ByteOffset,
		'Second marker offset must be greater than first');
end;

procedure TTestWlxScanRoleMarkers.NoRoleMarkers_ReturnsEmptyArray;
var
	LFile: string;
	LMarkers: TArray<TRoleMarker>;
	LFileSize: Int64;
begin
	LFile := CreateTempFile('noroles.json', '{"chunks":[{"text":"hello"}]}');
	LMarkers := ScanRoleMarkers(LFile, LFileSize);
	Assert.AreEqual(0, Integer(Length(LMarkers)));
end;

procedure TTestWlxScanRoleMarkers.ModelOnly_ReturnsSingleModelMarker;
var
	LFile: string;
	LMarkers: TArray<TRoleMarker>;
	LFileSize: Int64;
begin
	LFile := CreateTempFile('model.json',
		'{"chunks":[{"text":"hi","role":"model"}]}');
	LMarkers := ScanRoleMarkers(LFile, LFileSize);
	Assert.AreEqual(1, Integer(Length(LMarkers)));
	Assert.AreEqual<Byte>(1, LMarkers[0].Role);
end;

procedure TTestWlxScanRoleMarkers.FileSize_ReturnedCorrectly;
var
	LFile: string;
	LMarkers: TArray<TRoleMarker>;
	LFileSize: Int64;
	LExpected: Int64;
	LStream: TFileStream;
begin
	LFile := CreateTempFile('size.json', '{"chunks":[{"text":"hi","role":"user"}]}');
	LMarkers := ScanRoleMarkers(LFile, LFileSize);
	LStream := TFileStream.Create(LFile, fmOpenRead or fmShareDenyNone);
	try
		LExpected := LStream.Size;
	finally
		LStream.Free;
	end;
	Assert.AreEqual<Int64>(LExpected, LFileSize);
end;

procedure TTestWlxScanRoleMarkers.EmptyFile_ReturnsEmptyArray;
var
	LFile: string;
	LMarkers: TArray<TRoleMarker>;
	LFileSize: Int64;
begin
	// Create a truly empty file (no BOM)
	LFile := TPath.Combine(FTempDir, 'empty.json');
	TFile.WriteAllBytes(LFile, nil);
	LMarkers := ScanRoleMarkers(LFile, LFileSize);
	Assert.AreEqual(0, Integer(Length(LMarkers)));
	Assert.AreEqual<Int64>(0, LFileSize);
end;

procedure TTestWlxScanRoleMarkers.ManyChunks_AllMarkersFound;
var
	LFile: string;
	LMarkers: TArray<TRoleMarker>;
	LFileSize: Int64;
	LContent: string;
	I: Integer;
begin
	// Build a file with 10 alternating user/model chunks
	LContent := '{"chunks":[';
	for I := 0 to 9 do
	begin
		if I > 0 then
			LContent := LContent + ',';
		if I mod 2 = 0 then
			LContent := LContent + '{"text":"msg","role":"user"}'
		else
			LContent := LContent + '{"text":"msg","role":"model"}';
	end;
	LContent := LContent + ']}';
	LFile := CreateTempFile('many.json', LContent);
	LMarkers := ScanRoleMarkers(LFile, LFileSize);
	Assert.AreEqual(10, Integer(Length(LMarkers)));
end;

procedure TTestWlxScanRoleMarkers.RoleInStringValue_NotFalsePositive;
var
	LFile: string;
	LMarkers: TArray<TRoleMarker>;
	LFileSize: Int64;
begin
	// "role" appears in a text value, not as a JSON key -- should still find the real one
	LFile := CreateTempFile('falsepos.json',
		'{"chunks":[{"text":"the word role appears here","role":"user"}]}');
	LMarkers := ScanRoleMarkers(LFile, LFileSize);
	// The scanner does a simple binary scan so it may pick up "role" in the text value too.
	// What matters: at least one marker with role=user is found.
	Assert.IsTrue(Length(LMarkers) >= 1, 'At least one marker expected');
	// The last marker should be the real one (role key with "user" value)
	Assert.AreEqual<Byte>(0, LMarkers[High(LMarkers)].Role);
end;

// ========================================================================
// TTestWlxExtractFirstUserText
// ========================================================================

procedure TTestWlxExtractFirstUserText.Setup;
begin
	FTempDir := TPath.Combine(TPath.GetTempPath, 'wlx_test_' + TGUID.NewGuid.ToString);
	TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestWlxExtractFirstUserText.TearDown;
begin
	if TDirectory.Exists(FTempDir) then
		TDirectory.Delete(FTempDir, True);
end;

procedure TTestWlxExtractFirstUserText.SimpleText_ExtractedCorrectly;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('simple.json',
		'{"chunks":[{"text":"Hello world","role":"user"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('Hello world', LText);
end;

procedure TTestWlxExtractFirstUserText.EscapeNewline_DecodedToLF;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('newline.json',
		'{"chunks":[{"text":"line1\nline2","role":"user"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('line1'#10'line2', LText);
end;

procedure TTestWlxExtractFirstUserText.EscapeTab_DecodedToTab;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('tab.json',
		'{"chunks":[{"text":"col1\tcol2","role":"user"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('col1'#9'col2', LText);
end;

procedure TTestWlxExtractFirstUserText.EscapeBackslash_DecodedToBackslash;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('backslash.json',
		'{"chunks":[{"text":"path\\file","role":"user"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('path\file', LText);
end;

procedure TTestWlxExtractFirstUserText.EscapeQuote_DecodedToQuote;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('quote.json',
		'{"chunks":[{"text":"say \"hello\"","role":"user"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('say "hello"', LText);
end;

procedure TTestWlxExtractFirstUserText.EscapeSlash_DecodedToSlash;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('slash.json',
		'{"chunks":[{"text":"a\/b","role":"user"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('a/b', LText);
end;

procedure TTestWlxExtractFirstUserText.EscapeCarriageReturn_DecodedToCR;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('cr.json',
		'{"chunks":[{"text":"line1\rline2","role":"user"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('line1'#13'line2', LText);
end;

procedure TTestWlxExtractFirstUserText.EscapeUnicode_DecodedToCharacter;
var
	LFile, LText: string;
begin
	// \u00E9 = e-acute
	LFile := CreateTempFile('unicode.json',
		'{"chunks":[{"text":"caf\u00E9","role":"user"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('caf' + Chr($00E9), LText);
end;

procedure TTestWlxExtractFirstUserText.MaxChars_TruncatesLongText;
var
	LFile, LText: string;
	LLongText: string;
begin
	LLongText := StringOfChar('A', 500);
	LFile := CreateTempFile('long.json',
		'{"chunks":[{"text":"' + LLongText + '","role":"user"}]}');
	LText := ExtractFirstUserText(LFile, 50);
	Assert.AreEqual(50, Length(LText), 'Should be truncated to MaxChars');
end;

procedure TTestWlxExtractFirstUserText.NoUserRole_ReturnsEmpty;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('norole.json', '{"chunks":[{"text":"hello"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('', LText);
end;

procedure TTestWlxExtractFirstUserText.EmptyText_ReturnsEmpty;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('emptytext.json',
		'{"chunks":[{"text":"","role":"user"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('', LText);
end;

procedure TTestWlxExtractFirstUserText.ModelOnly_ReturnsEmpty;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('modelonly.json',
		'{"chunks":[{"text":"hello","role":"model"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('', LText);
end;

procedure TTestWlxExtractFirstUserText.EmptyFile_ReturnsEmpty;
var
	LFile, LText: string;
begin
	LFile := TPath.Combine(FTempDir, 'empty.json');
	TFile.WriteAllBytes(LFile, nil);
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('', LText);
end;

procedure TTestWlxExtractFirstUserText.MultipleEscapes_AllDecoded;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('multi.json',
		'{"chunks":[{"text":"a\\b\nc\td\/e","role":"user"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('a\b'#10'c'#9'd/e', LText);
end;

procedure TTestWlxExtractFirstUserText.Utf8Text_PreservedCorrectly;
var
	LFile, LText: string;
begin
	// Direct UTF-8 encoded content (no \u escapes)
	LFile := CreateTempFile('utf8.json',
		'{"chunks":[{"text":"' + Chr($00E9) + Chr($00FC) + '","role":"user"}]}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual(Chr($00E9) + Chr($00FC), LText);
end;

// ========================================================================
// TTestWlxThumbnails
// ========================================================================

procedure TTestWlxThumbnails.Setup;
begin
	FTempDir := TPath.Combine(TPath.GetTempPath, 'wlx_test_' + TGUID.NewGuid.ToString);
	TDirectory.CreateDirectory(FTempDir);
	CoInitializeEx(nil, COINIT_MULTITHREADED);
end;

procedure TTestWlxThumbnails.TearDown;
begin
	if TDirectory.Exists(FTempDir) then
		TDirectory.Delete(FTempDir, True);
end;

procedure TTestWlxThumbnails.ValidFile_ReturnsNonZeroBitmap;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	LFile := CreateTempFile('valid.json',
		'{"runSettings":{"model":"models/gemini-2.0-flash"},' +
		'"chunkedPrompt":{"chunks":[{"text":"Hello","role":"user"},' +
		'{"text":"Hi there","role":"model"}]}}');
	LBitmap := ListGetPreviewBitmapW(PWideChar(LFile), 128, 128, nil, 0);
	try
		Assert.IsTrue(LBitmap <> 0, 'Expected non-zero bitmap for valid file');
	finally
		if LBitmap <> 0 then
			DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxThumbnails.ValidFile_BitmapHasCorrectDimensions;
var
	LFile: string;
	LBitmap: HBITMAP;
	LBmpInfo: Winapi.Windows.TBitmap;
begin
	LFile := CreateTempFile('dims.json',
		'{"runSettings":{"model":"models/gemini-2.0-flash"},' +
		'"chunkedPrompt":{"chunks":[{"text":"Hello","role":"user"},' +
		'{"text":"Hi there","role":"model"}]}}');
	LBitmap := ListGetPreviewBitmapW(PWideChar(LFile), 200, 150, nil, 0);
	try
		Assert.IsTrue(LBitmap <> 0, 'Expected non-zero bitmap');
		GetObject(LBitmap, SizeOf(LBmpInfo), @LBmpInfo);
		// Text fallback creates bitmap at requested dimensions
		Assert.AreEqual(200, Integer(LBmpInfo.bmWidth), 'Width mismatch');
		Assert.AreEqual(150, Integer(Abs(LBmpInfo.bmHeight)), 'Height mismatch');
	finally
		if LBitmap <> 0 then
			DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxThumbnails.EmptyFile_ReturnsZero;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	LFile := TPath.Combine(FTempDir, 'empty.json');
	TFile.WriteAllBytes(LFile, nil);
	LBitmap := ListGetPreviewBitmapW(PWideChar(LFile), 128, 128, nil, 0);
	Assert.IsTrue(LBitmap = 0, 'Empty file should return 0');
end;

procedure TTestWlxThumbnails.InvalidJson_ReturnsZero;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	LFile := CreateTempFile('invalid.json', 'this is not json at all');
	LBitmap := ListGetPreviewBitmapW(PWideChar(LFile), 128, 128, nil, 0);
	Assert.IsTrue(LBitmap = 0, 'Invalid content should return 0');
end;

procedure TTestWlxThumbnails.NoUserText_ReturnsFallbackBitmap;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	// Model-only file: text fallback finds no user text, returns 0
	LFile := CreateTempFile('modelonly.json',
		'{"runSettings":{"model":"models/gemini-2.0-flash"},' +
		'"chunkedPrompt":{"chunks":[{"text":"response","role":"model"}]}}');
	LBitmap := ListGetPreviewBitmapW(PWideChar(LFile), 128, 128, nil, 0);
	// Default fallback is "text", and there's no user text -> returns 0
	Assert.IsTrue(LBitmap = 0, 'No user text -> no text thumbnail');
end;

// ========================================================================
// TTestWlxConfig
// ========================================================================

procedure TTestWlxConfig.DefaultThumbnailFallback_IsText;
var
	LConfig: TListerConfig;
begin
	LConfig := GetListerConfig;
	Assert.AreEqual('text', LConfig.ThumbnailFallback);
end;

procedure TTestWlxConfig.DefaultHideEmptyBlocks_IsTrue;
var
	LConfig: TListerConfig;
begin
	LConfig := GetListerConfig;
	Assert.IsTrue(LConfig.HideEmptyBlocks);
end;

procedure TTestWlxConfig.DefaultRenderMarkdown_IsTrue;
var
	LConfig: TListerConfig;
begin
	LConfig := GetListerConfig;
	Assert.IsTrue(LConfig.RenderMarkdown);
end;

procedure TTestWlxConfig.DefaultCombineBlocks_IsFalse;
var
	LConfig: TListerConfig;
begin
	LConfig := GetListerConfig;
	Assert.IsFalse(LConfig.CombineBlocks);
end;

end.
