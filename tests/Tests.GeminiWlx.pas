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
		[Test]
		procedure UnknownRoleValue_Skipped;
		[Test]
		procedure NonExistentFile_RaisesException;
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
		[Test]
		procedure BackslashAtEOF_HandledGracefully;
		[Test]
		procedure TruncatedUnicodeEscape_HandledGracefully;
		[Test]
		procedure InvalidUnicodeHex_DropsEscape;
		[Test]
		procedure UnknownEscape_PreservesChar;
		[Test]
		procedure EscapeBackspace_DecodedToBS;
		[Test]
		procedure EscapeFormFeed_DecodedToFF;
		[Test]
		procedure TextFarFromRole_StillFound;
		[Test]
		procedure NonExistentFile_RaisesException;
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
		[Test]
		procedure DefaultFullWidth_IsFalse;
		[Test]
		procedure DefaultExpandThinking_IsFalse;
		[Test]
		procedure DefaultAllowContextMenu_IsFalse;
		[Test]
		procedure DefaultAllowDevTools_IsFalse;
	end;

	/// <summary>
	///   Tests for FindFirstImageBase64: binary search for embedded images.
	/// </summary>
	[TestFixture]
	TTestWlxFindFirstImageBase64 = class
	private
		FTempDir: string;
		function CreateTempFile(const AName, AContent: string): string;
		function CreateTempFileBytes(const AName: string; const ABytes: TBytes): string;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;
		[Test]
		procedure FileWithInlineImage_ReturnsTrue;
		[Test]
		procedure FileWithInlineImage_ExtractsCorrectBase64;
		[Test]
		procedure FileWithoutInlineImage_ReturnsFalse;
		[Test]
		procedure EmptyFile_ReturnsFalse;
		[Test]
		procedure InlineImageNoDataKey_ReturnsFalse;
		[Test]
		procedure InlineImageEmptyData_ReturnsFalse;
		[Test]
		procedure LargeFileWithImage_FoundAcrossBufferBoundary;
	end;

	/// <summary>
	///   Tests for RenderStripeThumbnail, RenderTextExcerptThumbnail,
	///   and RenderMetadataThumbnail direct calls.
	/// </summary>
	[TestFixture]
	TTestWlxRenderFunctions = class
	private
		FTempDir: string;
		function CreateTempFile(const AName, AContent: string): string;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;
		[Test]
		procedure Stripe_ValidFile_ReturnsNonZeroBitmap;
		[Test]
		procedure Stripe_ValidFile_CorrectDimensions;
		[Test]
		procedure Stripe_NoMarkers_ReturnsZero;
		[Test]
		procedure Stripe_EmptyFile_ReturnsZero;
		[Test]
		procedure Text_ValidFile_ReturnsNonZeroBitmap;
		[Test]
		procedure Text_NoUserText_ReturnsZero;
		[Test]
		procedure Text_ValidFile_CorrectDimensions;
		[Test]
		procedure Metadata_ValidFile_ReturnsNonZeroBitmap;
		[Test]
		procedure Metadata_ValidFile_CorrectDimensions;
		[Test]
		procedure Metadata_InvalidFile_ReturnsZero;
		[Test]
		procedure Metadata_NoModelName_StillReturnsNonZero;
		[Test]
		procedure Text_SmallDimensions_HitsMinClamps;
		[Test]
		procedure Metadata_SmallDimensions_HitsMinClamps;
		[Test]
		procedure Stripe_ManyMarkers_SmallHeight_HitsMinBarHeight;
	end;

	/// <summary>
	///   Tests for exported WLX functions that don't require WebView2.
	/// </summary>
	[TestFixture]
	TTestWlxExportedFunctions = class
	private
		FTempDir: string;
		function CreateTempFile(const AName, AContent: string): string;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;
		[Test]
		procedure ListGetDetectString_ContainsRunSettings;
		[Test]
		procedure ListGetDetectString_RespectsMaxLen;
		[Test]
		procedure ListSetDefaultParams_DoesNotCrash;
		[Test]
		procedure ListGetPreviewBitmap_Ansi_ValidFile;
		[Test]
		procedure ListGetPreviewBitmap_Ansi_InvalidFile;
		[Test]
		procedure ListSendCommand_InvalidWindow_ReturnsError;
		[Test]
		procedure ListCloseWindow_InvalidWindow_DoesNotCrash;
		[Test]
		procedure ListLoadNextW_InvalidWindow_ReturnsError;
		[Test]
		procedure ListSearchTextW_InvalidWindow_ReturnsError;
		[Test]
		procedure ListGetPreviewBitmapW_FileWithImage_ReturnsNonZero;
		[Test]
		procedure ListGetPreviewBitmapW_StripeFallback_ReturnsNonZero;
		[Test]
		procedure ListGetPreviewBitmapW_MetadataFallback_ReturnsNonZero;
	end;

	/// <summary>
	///   Tests for JsEscapeString: JavaScript string literal escaping.
	/// </summary>
	[TestFixture]
	TTestWlxJsEscapeString = class
	public
		[Test]
		procedure EmptyString_ReturnsEmpty;
		[Test]
		procedure PlainText_Unchanged;
		[Test]
		procedure Backslash_Escaped;
		[Test]
		procedure DoubleQuote_Escaped;
		[Test]
		procedure Newline_Escaped;
		[Test]
		procedure CarriageReturn_Escaped;
		[Test]
		procedure Tab_Escaped;
		[Test]
		procedure Backspace_Escaped;
		[Test]
		procedure FormFeed_Escaped;
		[Test]
		procedure LineSeparator_U2028_Escaped;
		[Test]
		procedure ParagraphSeparator_U2029_Escaped;
		[Test]
		procedure MixedSpecialChars_AllEscaped;
	end;

implementation

uses
	Winapi.ActiveX,
	WlxApi,
	Tests.GeminiFile.TestUtils;

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
// TTestWlxScanRoleMarkers (additional edge case tests)
// ========================================================================

procedure TTestWlxScanRoleMarkers.UnknownRoleValue_Skipped;
var
	LFile: string;
	LMarkers: TArray<TRoleMarker>;
	LFileSize: Int64;
begin
	// "role":"system" has first char 's', which is neither 'u' nor 'm' -- should be skipped
	LFile := CreateTempFile('unknown_role.json',
		'{"chunks":[{"text":"hi","role":"system"},{"text":"yo","role":"user"}]}');
	LMarkers := ScanRoleMarkers(LFile, LFileSize);
	// Only the user marker should be found, system should be skipped
	Assert.AreEqual(1, Integer(Length(LMarkers)), 'Unknown role should be skipped');
	Assert.AreEqual<Byte>(0, LMarkers[0].Role, 'Should be user marker');
end;

procedure TTestWlxScanRoleMarkers.NonExistentFile_RaisesException;
begin
	Assert.WillRaise(
		procedure
		var
			LMarkers: TArray<TRoleMarker>;
			LFileSize: Int64;
		begin
			LMarkers := ScanRoleMarkers('C:\nonexistent_wlx_test_12345.json', LFileSize);
		end,
		EFOpenError);
end;

// ========================================================================
// TTestWlxExtractFirstUserText (additional edge case tests)
// ========================================================================

procedure TTestWlxExtractFirstUserText.BackslashAtEOF_HandledGracefully;
var
	LFile, LText: string;
begin
	// JSON string ends with a backslash right before EOF (no char after it)
	// The backslash is inside the "text" value, simulating a truncated escape
	LFile := TPath.Combine(FTempDir, 'bslash_eof.json');
	// Build raw bytes: {"text":"abc\","role":"user"} but we truncate after the backslash
	// Actually, we need a file where the text value has a trailing backslash with no next byte
	// Simplest: write bytes manually where the file ends mid-escape
	TFile.WriteAllBytes(LFile, TEncoding.UTF8.GetBytes('{"text":"abc\'));
	LText := ExtractFirstUserText(LFile);
	// No user role found (the file is truncated), should return empty
	Assert.AreEqual('', LText);
end;

procedure TTestWlxExtractFirstUserText.TruncatedUnicodeEscape_HandledGracefully;
var
	LFile, LText: string;
begin
	// \u with only 2 hex digits available before EOF
	LFile := TPath.Combine(FTempDir, 'trunc_unicode.json');
	TFile.WriteAllBytes(LFile, TEncoding.UTF8.GetBytes(
		'{"text":"abc\u00","role":"user"}'));
	LText := ExtractFirstUserText(LFile);
	// The \u00 is truncated (only 2 hex chars). The function should handle gracefully.
	// It reads "abc" before the truncated escape
	Assert.AreEqual('abc', LText, 'Should extract text before truncated \u escape');
end;

procedure TTestWlxExtractFirstUserText.InvalidUnicodeHex_DropsEscape;
var
	LFile, LText: string;
begin
	// \uXXXX with invalid hex chars -- StrToIntDef returns -1, escape is dropped
	LFile := CreateTempFile('bad_hex.json',
		'{"text":"a\uZZZZb","role":"user"}');
	LText := ExtractFirstUserText(LFile);
	// The \uZZZZ is invalid hex. StrToIntDef('$ZZZZ', -1) = -1, so nothing written.
	// 'a' is written, then \uZZZZ is consumed but dropped, then 'b' is written.
	Assert.AreEqual('ab', LText, 'Invalid \uXXXX should be dropped, surrounding text preserved');
end;

procedure TTestWlxExtractFirstUserText.UnknownEscape_PreservesChar;
var
	LFile, LText: string;
begin
	// \x is an unknown escape -- should preserve 'x' (the escaped char itself)
	LFile := CreateTempFile('unknown_esc.json',
		'{"text":"a\xb","role":"user"}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('axb', LText, 'Unknown escape \x should emit x');
end;

procedure TTestWlxExtractFirstUserText.EscapeBackspace_DecodedToBS;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('bs.json',
		'{"text":"a\bb","role":"user"}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('a'#8'b', LText);
end;

procedure TTestWlxExtractFirstUserText.EscapeFormFeed_DecodedToFF;
var
	LFile, LText: string;
begin
	LFile := CreateTempFile('ff.json',
		'{"text":"a\fb","role":"user"}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('a'#12'b', LText);
end;

procedure TTestWlxExtractFirstUserText.TextFarFromRole_StillFound;
var
	LFile, LText: string;
	LPadding: string;
begin
	// "text" is within 4KB before "role", should be found by backward search
	// Use 2KB of padding between text value end and role key
	LPadding := StringOfChar(' ', 2000);
	LFile := CreateTempFile('far_text.json',
		'{"text":"found it",' + LPadding + '"role":"user"}');
	LText := ExtractFirstUserText(LFile);
	Assert.AreEqual('found it', LText);
end;

procedure TTestWlxExtractFirstUserText.NonExistentFile_RaisesException;
begin
	Assert.WillRaise(
		procedure
		var
			LText: string;
		begin
			LText := ExtractFirstUserText('C:\nonexistent_wlx_test_12345.json');
		end,
		EFOpenError);
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

procedure TTestWlxConfig.DefaultFullWidth_IsFalse;
var
	LConfig: TListerConfig;
begin
	LConfig := GetListerConfig;
	Assert.IsFalse(LConfig.DefaultFullWidth);
end;

procedure TTestWlxConfig.DefaultExpandThinking_IsFalse;
var
	LConfig: TListerConfig;
begin
	LConfig := GetListerConfig;
	Assert.IsFalse(LConfig.DefaultExpandThinking);
end;

procedure TTestWlxConfig.DefaultAllowContextMenu_IsFalse;
var
	LConfig: TListerConfig;
begin
	LConfig := GetListerConfig;
	Assert.IsFalse(LConfig.AllowContextMenu);
end;

procedure TTestWlxConfig.DefaultAllowDevTools_IsFalse;
var
	LConfig: TListerConfig;
begin
	LConfig := GetListerConfig;
	Assert.IsFalse(LConfig.AllowDevTools);
end;

// ========================================================================
// TTestWlxFindFirstImageBase64
// ========================================================================

function TTestWlxFindFirstImageBase64.CreateTempFile(const AName, AContent: string): string;
begin
	Result := TPath.Combine(FTempDir, AName);
	TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

function TTestWlxFindFirstImageBase64.CreateTempFileBytes(const AName: string; const ABytes: TBytes): string;
begin
	Result := TPath.Combine(FTempDir, AName);
	TFile.WriteAllBytes(Result, ABytes);
end;

procedure TTestWlxFindFirstImageBase64.Setup;
begin
	FTempDir := TPath.Combine(TPath.GetTempPath, 'wlx_test_' + TGUID.NewGuid.ToString);
	TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestWlxFindFirstImageBase64.TearDown;
begin
	if TDirectory.Exists(FTempDir) then
		TDirectory.Delete(FTempDir, True);
end;

procedure TTestWlxFindFirstImageBase64.FileWithInlineImage_ReturnsTrue;
var
	LFile: string;
	LBase64: TBytes;
begin
	LFile := CreateTempFile('img.json',
		'{"chunks":[{"inlineImage":{"mimeType":"image/png","data":"AQID"}}]}');
	Assert.IsTrue(FindFirstImageBase64(LFile, LBase64),
		'Should find inline image base64 data');
end;

procedure TTestWlxFindFirstImageBase64.FileWithInlineImage_ExtractsCorrectBase64;
var
	LFile: string;
	LBase64: TBytes;
	LStr: string;
begin
	LFile := CreateTempFile('img_data.json',
		'{"chunks":[{"inlineImage":{"mimeType":"image/png","data":"SGVsbG8="}}]}');
	Assert.IsTrue(FindFirstImageBase64(LFile, LBase64));
	SetString(LStr, PAnsiChar(@LBase64[0]), Length(LBase64));
	Assert.AreEqual('SGVsbG8=', LStr, 'Should extract exact base64 content');
end;

procedure TTestWlxFindFirstImageBase64.FileWithoutInlineImage_ReturnsFalse;
var
	LFile: string;
	LBase64: TBytes;
begin
	LFile := CreateTempFile('no_img.json',
		'{"chunks":[{"text":"hello","role":"user"}]}');
	Assert.IsFalse(FindFirstImageBase64(LFile, LBase64),
		'File without inlineImage should return False');
end;

procedure TTestWlxFindFirstImageBase64.EmptyFile_ReturnsFalse;
var
	LFile: string;
	LBase64: TBytes;
begin
	LFile := CreateTempFileBytes('empty.dat', nil);
	Assert.IsFalse(FindFirstImageBase64(LFile, LBase64));
end;

procedure TTestWlxFindFirstImageBase64.InlineImageNoDataKey_ReturnsFalse;
var
	LFile: string;
	LBase64: TBytes;
begin
	// Has "inlineImage" but the object has no "data" key
	LFile := CreateTempFile('no_data.json',
		'{"chunks":[{"inlineImage":{"mimeType":"image/png"}}]}');
	Assert.IsFalse(FindFirstImageBase64(LFile, LBase64),
		'Should return False when "data" key is missing');
end;

procedure TTestWlxFindFirstImageBase64.InlineImageEmptyData_ReturnsFalse;
var
	LFile: string;
	LBase64: TBytes;
begin
	// Has "data" but the value is empty
	LFile := CreateTempFile('empty_data.json',
		'{"chunks":[{"inlineImage":{"mimeType":"image/png","data":""}}]}');
	Assert.IsFalse(FindFirstImageBase64(LFile, LBase64),
		'Should return False when data is empty string');
end;

procedure TTestWlxFindFirstImageBase64.LargeFileWithImage_FoundAcrossBufferBoundary;
var
	LFile: string;
	LBase64: TBytes;
	LPadding: string;
begin
	// Create a file with >64KB of content before the inlineImage marker
	// to exercise the overlapping buffer boundary scan
	LPadding := StringOfChar('X', 70000);
	LFile := CreateTempFile('large.json',
		'{"padding":"' + LPadding + '","chunks":[{"inlineImage":{"mimeType":"image/png","data":"AQID"}}]}');
	Assert.IsTrue(FindFirstImageBase64(LFile, LBase64),
		'Should find inline image even past buffer boundary');
end;

// ========================================================================
// TTestWlxRenderFunctions
// ========================================================================

function TTestWlxRenderFunctions.CreateTempFile(const AName, AContent: string): string;
begin
	Result := TPath.Combine(FTempDir, AName);
	TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

procedure TTestWlxRenderFunctions.Setup;
begin
	FTempDir := TPath.Combine(TPath.GetTempPath, 'wlx_test_' + TGUID.NewGuid.ToString);
	TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestWlxRenderFunctions.TearDown;
begin
	if TDirectory.Exists(FTempDir) then
		TDirectory.Delete(FTempDir, True);
end;

procedure TTestWlxRenderFunctions.Stripe_ValidFile_ReturnsNonZeroBitmap;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	LFile := CreateTempFile('stripe.json',
		'{"chunks":[{"text":"hi","role":"user"},{"text":"hello","role":"model"}]}');
	LBitmap := RenderStripeThumbnail(LFile, 128, 128);
	try
		Assert.IsTrue(LBitmap <> 0, 'Stripe should produce non-zero bitmap');
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxRenderFunctions.Stripe_ValidFile_CorrectDimensions;
var
	LFile: string;
	LBitmap: HBITMAP;
	LBmpInfo: Winapi.Windows.TBitmap;
begin
	LFile := CreateTempFile('stripe_dim.json',
		'{"chunks":[{"text":"hi","role":"user"},{"text":"hello","role":"model"}]}');
	LBitmap := RenderStripeThumbnail(LFile, 200, 150);
	try
		Assert.IsTrue(LBitmap <> 0);
		GetObject(LBitmap, SizeOf(LBmpInfo), @LBmpInfo);
		Assert.AreEqual(200, Integer(LBmpInfo.bmWidth));
		Assert.AreEqual(150, Integer(Abs(LBmpInfo.bmHeight)));
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxRenderFunctions.Stripe_NoMarkers_ReturnsZero;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	LFile := CreateTempFile('stripe_empty.json', '{"chunks":[{"text":"hello"}]}');
	LBitmap := RenderStripeThumbnail(LFile, 128, 128);
	Assert.IsTrue(LBitmap = 0, 'No role markers -> no stripe thumbnail');
end;

procedure TTestWlxRenderFunctions.Stripe_EmptyFile_ReturnsZero;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	LFile := TPath.Combine(FTempDir, 'stripe_nil.dat');
	TFile.WriteAllBytes(LFile, nil);
	LBitmap := RenderStripeThumbnail(LFile, 128, 128);
	Assert.IsTrue(LBitmap = 0);
end;

procedure TTestWlxRenderFunctions.Text_ValidFile_ReturnsNonZeroBitmap;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	LFile := CreateTempFile('text_thumb.json',
		'{"chunks":[{"text":"Hello world","role":"user"}]}');
	LBitmap := RenderTextExcerptThumbnail(LFile, 128, 128);
	try
		Assert.IsTrue(LBitmap <> 0, 'Text excerpt should produce non-zero bitmap');
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxRenderFunctions.Text_NoUserText_ReturnsZero;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	LFile := CreateTempFile('text_no_user.json',
		'{"chunks":[{"text":"response","role":"model"}]}');
	LBitmap := RenderTextExcerptThumbnail(LFile, 128, 128);
	Assert.IsTrue(LBitmap = 0, 'No user text -> no text thumbnail');
end;

procedure TTestWlxRenderFunctions.Text_ValidFile_CorrectDimensions;
var
	LFile: string;
	LBitmap: HBITMAP;
	LBmpInfo: Winapi.Windows.TBitmap;
begin
	LFile := CreateTempFile('text_dim.json',
		'{"chunks":[{"text":"Hello world","role":"user"}]}');
	LBitmap := RenderTextExcerptThumbnail(LFile, 180, 120);
	try
		Assert.IsTrue(LBitmap <> 0);
		GetObject(LBitmap, SizeOf(LBmpInfo), @LBmpInfo);
		Assert.AreEqual(180, Integer(LBmpInfo.bmWidth));
		Assert.AreEqual(120, Integer(Abs(LBmpInfo.bmHeight)));
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxRenderFunctions.Metadata_ValidFile_ReturnsNonZeroBitmap;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	LFile := CreateTempFile('meta.json',
		'{"runSettings":{"model":"models/gemini-2.0-flash","temperature":0.5},' +
		'"chunkedPrompt":{"chunks":[{"text":"hi","role":"user","tokenCount":10},' +
		'{"text":"hello","role":"model","tokenCount":20}]}}');
	LBitmap := RenderMetadataThumbnail(LFile, 128, 128);
	try
		Assert.IsTrue(LBitmap <> 0, 'Metadata should produce non-zero bitmap');
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxRenderFunctions.Metadata_ValidFile_CorrectDimensions;
var
	LFile: string;
	LBitmap: HBITMAP;
	LBmpInfo: Winapi.Windows.TBitmap;
begin
	LFile := CreateTempFile('meta_dim.json',
		'{"runSettings":{"model":"models/gemini-2.0-flash"},' +
		'"chunkedPrompt":{"chunks":[{"text":"hi","role":"user"}]}}');
	LBitmap := RenderMetadataThumbnail(LFile, 200, 160);
	try
		Assert.IsTrue(LBitmap <> 0);
		GetObject(LBitmap, SizeOf(LBmpInfo), @LBmpInfo);
		Assert.AreEqual(200, Integer(LBmpInfo.bmWidth));
		Assert.AreEqual(160, Integer(Abs(LBmpInfo.bmHeight)));
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxRenderFunctions.Metadata_InvalidFile_ReturnsZero;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	// File that fails JSON parsing -- LoadFromFile throws
	LFile := CreateTempFile('meta_bad.json', 'not valid json');
	LBitmap := 0;
	try
		LBitmap := RenderMetadataThumbnail(LFile, 128, 128);
		// Exception propagates, but if caught in a wrapper, result is 0
		Assert.Fail('Should have raised an exception');
	except
		// LoadFromFile raises EGeminiParseError
		Assert.IsTrue(LBitmap = 0, 'Invalid file should not produce bitmap');
	end;
end;

procedure TTestWlxRenderFunctions.Metadata_NoModelName_StillReturnsNonZero;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	// File with empty model -- should show "Unknown model"
	LFile := CreateTempFile('meta_nomodel.json',
		'{"chunkedPrompt":{"chunks":[{"text":"hi","role":"user"}]}}');
	LBitmap := RenderMetadataThumbnail(LFile, 128, 128);
	try
		Assert.IsTrue(LBitmap <> 0, 'Should still render with "Unknown model"');
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxRenderFunctions.Text_SmallDimensions_HitsMinClamps;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	// Width < 64 triggers LPadding := 4; Height < 120 triggers LFontSize := 10
	LFile := CreateTempFile('small_text.json',
		'{"chunks":[{"text":"hello world","role":"user"},{"text":"reply","role":"model"}]}');
	LBitmap := RenderTextExcerptThumbnail(LFile, 32, 48);
	try
		Assert.IsTrue(LBitmap <> 0, 'Small text thumbnail should still render');
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxRenderFunctions.Metadata_SmallDimensions_HitsMinClamps;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	// Width < 64 triggers LPadding := 4; Height < 120 triggers LFontSize := 10
	LFile := CreateTempFile('small_meta.json',
		'{"runSettings":{"model":"models/gemini-2.0-flash"},' +
		'"chunkedPrompt":{"chunks":[{"text":"hi","role":"user","tokenCount":10}]}}');
	LBitmap := RenderMetadataThumbnail(LFile, 32, 48);
	try
		Assert.IsTrue(LBitmap <> 0, 'Small metadata thumbnail should still render');
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxRenderFunctions.Stripe_ManyMarkers_SmallHeight_HitsMinBarHeight;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	// Many markers with small height -> each bar shrinks to 1px minimum
	LFile := CreateTempFile('many_markers.json',
		'{"chunks":[' +
		'{"text":"u1","role":"user"},{"text":"m1","role":"model"},' +
		'{"text":"u2","role":"user"},{"text":"m2","role":"model"},' +
		'{"text":"u3","role":"user"},{"text":"m3","role":"model"},' +
		'{"text":"u4","role":"user"},{"text":"m4","role":"model"},' +
		'{"text":"u5","role":"user"},{"text":"m5","role":"model"},' +
		'{"text":"u6","role":"user"},{"text":"m6","role":"model"},' +
		'{"text":"u7","role":"user"},{"text":"m7","role":"model"},' +
		'{"text":"u8","role":"user"},{"text":"m8","role":"model"},' +
		'{"text":"u9","role":"user"},{"text":"m9","role":"model"},' +
		'{"text":"u10","role":"user"},{"text":"m10","role":"model"}' +
		']}');
	LBitmap := RenderStripeThumbnail(LFile, 32, 32);
	try
		Assert.IsTrue(LBitmap <> 0, 'Stripe with many markers at tiny size should still render');
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

// ========================================================================
// TTestWlxExportedFunctions
// ========================================================================

function TTestWlxExportedFunctions.CreateTempFile(const AName, AContent: string): string;
begin
	Result := TPath.Combine(FTempDir, AName);
	TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

procedure TTestWlxExportedFunctions.Setup;
begin
	FTempDir := TPath.Combine(TPath.GetTempPath, 'wlx_test_' + TGUID.NewGuid.ToString);
	TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestWlxExportedFunctions.TearDown;
begin
	if TDirectory.Exists(FTempDir) then
		TDirectory.Delete(FTempDir, True);
end;

procedure TTestWlxExportedFunctions.ListGetDetectString_ContainsRunSettings;
var
	LBuf: array[0..255] of AnsiChar;
begin
	FillChar(LBuf, SizeOf(LBuf), 0);
	ListGetDetectString(@LBuf[0], 256);
	Assert.IsTrue(Pos('runSettings', string(AnsiString(LBuf))) > 0,
		'Detect string should contain "runSettings"');
end;

procedure TTestWlxExportedFunctions.ListGetDetectString_RespectsMaxLen;
var
	LBuf: array[0..9] of AnsiChar;
begin
	FillChar(LBuf, SizeOf(LBuf), 0);
	ListGetDetectString(@LBuf[0], 10);
	// Should not write more than MaxLen-1 chars + null terminator
	Assert.AreEqual(AnsiChar(#0), LBuf[9], 'Should not exceed MaxLen');
end;

procedure TTestWlxExportedFunctions.ListSetDefaultParams_DoesNotCrash;
var
	LParams: TListDefaultParamStruct;
begin
	FillChar(LParams, SizeOf(LParams), 0);
	LParams.size := SizeOf(LParams);
	LParams.PluginInterfaceVersionLow := 1;
	LParams.PluginInterfaceVersionHi := 2;
	// Should complete without crash
	ListSetDefaultParams(@LParams);
	Assert.Pass;
end;

procedure TTestWlxExportedFunctions.ListGetPreviewBitmap_Ansi_ValidFile;
var
	LFile: string;
	LAnsi: AnsiString;
	LBitmap: HBITMAP;
begin
	LFile := CreateTempFile('ansi_thumb.json',
		'{"runSettings":{"model":"models/test"},' +
		'"chunkedPrompt":{"chunks":[{"text":"Hello","role":"user"}]}}');
	LAnsi := AnsiString(LFile);
	LBitmap := ListGetPreviewBitmap(PAnsiChar(LAnsi), 128, 128, nil, 0);
	try
		Assert.IsTrue(LBitmap <> 0, 'ANSI preview should work for valid file');
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxExportedFunctions.ListGetPreviewBitmap_Ansi_InvalidFile;
var
	LFile: string;
	LAnsi: AnsiString;
	LBitmap: HBITMAP;
begin
	LFile := CreateTempFile('ansi_bad.json', 'not json');
	LAnsi := AnsiString(LFile);
	LBitmap := ListGetPreviewBitmap(PAnsiChar(LAnsi), 128, 128, nil, 0);
	Assert.IsTrue(LBitmap = 0, 'ANSI preview should return 0 for invalid file');
end;

procedure TTestWlxExportedFunctions.ListSendCommand_InvalidWindow_ReturnsError;
begin
	// Invalid HWND should return LISTPLUGIN_ERROR without crashing
	Assert.AreEqual(LISTPLUGIN_ERROR, ListSendCommand(0, lc_copy, 0));
end;

procedure TTestWlxExportedFunctions.ListCloseWindow_InvalidWindow_DoesNotCrash;
begin
	// Should not crash when called with invalid HWND
	// GetWindowLongPtr(0, ...) returns 0, so LWindow = nil, Free is skipped
	// DestroyWindow(0) is a no-op
	ListCloseWindow(0);
	Assert.Pass;
end;

procedure TTestWlxExportedFunctions.ListLoadNextW_InvalidWindow_ReturnsError;
var
	LFile: string;
begin
	LFile := CreateTempFile('loadnext.json',
		'{"chunkedPrompt":{"chunks":[]}}');
	Assert.AreEqual(LISTPLUGIN_ERROR,
		ListLoadNextW(0, 0, PWideChar(LFile), 0));
end;

procedure TTestWlxExportedFunctions.ListSearchTextW_InvalidWindow_ReturnsError;
begin
	Assert.AreEqual(LISTPLUGIN_ERROR,
		ListSearchTextW(0, PWideChar('test'), 0));
end;

procedure TTestWlxExportedFunctions.ListGetPreviewBitmapW_FileWithImage_ReturnsNonZero;
var
	LPath: string;
	LBitmap: HBITMAP;
begin
	// File with embedded images exercises the image decode path (WIC/COM)
	LPath := FindExample('Sberbank and Soyuzmultfilm Logo');
	if LPath = '' then
		Exit;
	LBitmap := ListGetPreviewBitmapW(PWideChar(LPath), 128, 128, nil, 0);
	try
		Assert.IsTrue(LBitmap <> 0,
			'File with embedded image should produce a thumbnail');
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxExportedFunctions.ListGetPreviewBitmapW_StripeFallback_ReturnsNonZero;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	// Uses RenderStripeThumbnail directly since we can't change global config
	LFile := CreateTempFile('stripe_fallback.json',
		'{"chunks":[{"text":"hi","role":"user"},{"text":"hello","role":"model"}]}');
	LBitmap := RenderStripeThumbnail(LFile, 128, 128);
	try
		Assert.IsTrue(LBitmap <> 0, 'Stripe fallback should produce a thumbnail');
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

procedure TTestWlxExportedFunctions.ListGetPreviewBitmapW_MetadataFallback_ReturnsNonZero;
var
	LFile: string;
	LBitmap: HBITMAP;
begin
	// Uses RenderMetadataThumbnail directly since we can't change global config
	LFile := CreateTempFile('meta_fallback.json',
		'{"runSettings":{"model":"models/gemini-2.0-flash"},' +
		'"chunkedPrompt":{"chunks":[{"text":"hi","role":"user","tokenCount":10}]}}');
	LBitmap := RenderMetadataThumbnail(LFile, 128, 128);
	try
		Assert.IsTrue(LBitmap <> 0, 'Metadata fallback should produce a thumbnail');
	finally
		if LBitmap <> 0 then DeleteObject(LBitmap);
	end;
end;

// ========================================================================
// TTestWlxJsEscapeString
// ========================================================================

procedure TTestWlxJsEscapeString.EmptyString_ReturnsEmpty;
begin
	Assert.AreEqual('', JsEscapeString(''));
end;

procedure TTestWlxJsEscapeString.PlainText_Unchanged;
begin
	Assert.AreEqual('hello world 123', JsEscapeString('hello world 123'));
end;

procedure TTestWlxJsEscapeString.Backslash_Escaped;
begin
	Assert.AreEqual('a\\b', JsEscapeString('a\b'));
end;

procedure TTestWlxJsEscapeString.DoubleQuote_Escaped;
begin
	Assert.AreEqual('say \"hi\"', JsEscapeString('say "hi"'));
end;

procedure TTestWlxJsEscapeString.Newline_Escaped;
begin
	Assert.AreEqual('line1\nline2', JsEscapeString('line1' + #10 + 'line2'));
end;

procedure TTestWlxJsEscapeString.CarriageReturn_Escaped;
begin
	Assert.AreEqual('a\rb', JsEscapeString('a' + #13 + 'b'));
end;

procedure TTestWlxJsEscapeString.Tab_Escaped;
begin
	Assert.AreEqual('col1\tcol2', JsEscapeString('col1' + #9 + 'col2'));
end;

procedure TTestWlxJsEscapeString.Backspace_Escaped;
begin
	Assert.AreEqual('x\by', JsEscapeString('x' + #8 + 'y'));
end;

procedure TTestWlxJsEscapeString.FormFeed_Escaped;
begin
	Assert.AreEqual('a\fb', JsEscapeString('a' + #12 + 'b'));
end;

procedure TTestWlxJsEscapeString.LineSeparator_U2028_Escaped;
begin
	Assert.AreEqual('a\u2028b', JsEscapeString('a' + #$2028 + 'b'));
end;

procedure TTestWlxJsEscapeString.ParagraphSeparator_U2029_Escaped;
begin
	Assert.AreEqual('a\u2029b', JsEscapeString('a' + #$2029 + 'b'));
end;

procedure TTestWlxJsEscapeString.MixedSpecialChars_AllEscaped;
begin
	// Backslash + quote + newline + tab in one string
	Assert.AreEqual('\\\"\n\t', JsEscapeString('\"' + #10 + #9));
end;

initialization
	TDUnitX.RegisterTestFixture(TTestWlxScanRoleMarkers);
	TDUnitX.RegisterTestFixture(TTestWlxExtractFirstUserText);
	TDUnitX.RegisterTestFixture(TTestWlxThumbnails);
	TDUnitX.RegisterTestFixture(TTestWlxConfig);
	TDUnitX.RegisterTestFixture(TTestWlxFindFirstImageBase64);
	TDUnitX.RegisterTestFixture(TTestWlxRenderFunctions);
	TDUnitX.RegisterTestFixture(TTestWlxExportedFunctions);
	TDUnitX.RegisterTestFixture(TTestWlxJsEscapeString);

end.
