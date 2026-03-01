/// <summary>
///   Tests for the pre-scanner, lazy loading, lazy resources,
///   and integration of lazy loading with the TGeminiFile facade.
/// </summary>
unit Tests.GeminiFile.LazyData;

interface

uses
	System.SysUtils,
	System.Classes,
	System.IOUtils,
	System.Generics.Collections,
	DUnitX.TestFramework,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.LazyData,
	GeminiFile;

type
	// =====================================================================
	// Pre-scanner tests
	// =====================================================================
	[TestFixture]
	TTestPreScanner = class
	public
		[Test]
		procedure Scan_NoDataKeys_ReturnsUnchangedJson;
		[Test]
		procedure Scan_SmallDataValue_NotStripped;
		[Test]
		procedure Scan_LargeDataValue_ReplacedWithPlaceholder;
		[Test]
		procedure Scan_MultipleDataValues_SequentialPlaceholders;
		[Test]
		procedure Scan_LocationOffsets_MatchOriginalBytes;
		[Test]
		procedure Scan_EscapedQuotesInText_NotConfusedWithKey;
		[Test]
		procedure Scan_DataKeyAsValueContext_NotStripped;
		[Test]
		procedure Scan_EmptyInput_ReturnsEmpty;
		[Test]
		procedure Scan_WithBOM_SkipsBOM;
		[Test]
		procedure Scan_DataFollowedByNonString_NotStripped;
		[Test]
		procedure Scan_StrippedJsonIsParseable;
		[Test]
		procedure Scan_RealFileWithResources_StrippedCorrectly;
		[Test]
		procedure Scan_RealFileWithoutResources_IdenticalOutput;
	end;

	// =====================================================================
	// Lazy load from file tests
	// =====================================================================
	[TestFixture]
	TTestLazyLoad = class
	public
		[Test]
		procedure LoadBase64_ReturnsCorrectContent;
		[Test]
		procedure LoadBase64_FileNotFound_RaisesError;
		[Test]
		procedure LoadBase64_OffsetBeyondSize_RaisesError;
	end;

	// =====================================================================
	// Lazy resource tests (TGeminiResource.CreateLazy)
	// =====================================================================
	[TestFixture]
	TTestLazyResource = class
	private
		FTempFile: string;
		procedure CreateTempFile(const ABase64: string);
	public
		[TearDown]
		procedure TearDown;
		[Test]
		procedure CreateLazy_DecodedSize_EstimatesWithoutLoading;
		[Test]
		procedure CreateLazy_Base64Size_ReportsWithoutLoading;
		[Test]
		procedure CreateLazy_Base64Data_TriggersLoad;
		[Test]
		procedure CreateLazy_Decode_LoadsAndDecodes;
		[Test]
		procedure CreateLazy_SaveToStream_Works;
		[Test]
		procedure CreateLazy_ReleaseAll_ThenReload_Works;
		[Test]
		procedure CreateLazy_FileDeleted_RaisesOnAccess;
		[Test]
		procedure CreateLazy_IsLazy_ReturnsTrue;
		[Test]
		procedure Create_Regular_IsLazy_ReturnsFalse;
	end;

	// =====================================================================
	// Integration tests (TGeminiFile.LoadFromFile with lazy loading)
	// =====================================================================
	[TestFixture]
	TTestLazyIntegration = class
	private
		function ExamplesDir: string;
		function FindExample(const AName: string): string;
	public
		[Test]
		procedure LoadFromFile_WithResources_ResourcesAreLazy;
		[Test]
		procedure LoadFromFile_WithResources_DecodedSizeCorrect;
		[Test]
		procedure LoadFromFile_WithResources_ExtractWorks;
		[Test]
		procedure LoadFromFile_NoResources_NormalParsing;
		[Test]
		procedure LoadFromStream_ResourcesAreNotLazy;
		[Test]
		procedure LoadFromFile_ProducesSameChunksAsLoadFromStream;
	end;

implementation

uses
	System.JSON,
	System.NetEncoding;

// =========================================================================
// Helpers
// =========================================================================

function MakeJsonBytes(const AJson: string): TBytes;
begin
	Result := TEncoding.UTF8.GetBytes(AJson);
end;

function MakeBase64(ALength: Integer): string;
begin
	Result := StringOfChar('A', ALength);
end;

// =========================================================================
// TTestPreScanner
// =========================================================================

procedure TTestPreScanner.Scan_NoDataKeys_ReturnsUnchangedJson;
var
	LJson: string;
	LBytes: TBytes;
	LResult: TPreScanResult;
begin
	LJson := '{"name":"test","value":"hello"}';
	LBytes := MakeJsonBytes(LJson);
	LResult := PreScanGeminiFile(LBytes);
	Assert.AreEqual(LJson, LResult.StrippedJson);
	Assert.AreEqual<Integer>(0, Length(LResult.Locations));
end;

procedure TTestPreScanner.Scan_SmallDataValue_NotStripped;
var
	LJson: string;
	LBytes: TBytes;
	LResult: TPreScanResult;
begin
	LJson := '{"mimeType":"image/png","data":"AAAA"}';
	LBytes := MakeJsonBytes(LJson);
	LResult := PreScanGeminiFile(LBytes);
	Assert.AreEqual(LJson, LResult.StrippedJson);
	Assert.AreEqual<Integer>(0, Length(LResult.Locations));
end;

procedure TTestPreScanner.Scan_LargeDataValue_ReplacedWithPlaceholder;
var
	LLargeData: string;
	LJson: string;
	LBytes: TBytes;
	LResult: TPreScanResult;
begin
	LLargeData := MakeBase64(2000);
	LJson := '{"mimeType":"image/png","data":"' + LLargeData + '"}';
	LBytes := MakeJsonBytes(LJson);
	LResult := PreScanGeminiFile(LBytes);
	Assert.AreEqual<Integer>(1, Length(LResult.Locations), 'Should have 1 location');
	Assert.IsTrue(LResult.StrippedJson.Contains('__LAZY:0'),
		'Stripped JSON should contain placeholder');
	Assert.IsFalse(LResult.StrippedJson.Contains(LLargeData),
		'Stripped JSON should not contain original data');
end;

procedure TTestPreScanner.Scan_MultipleDataValues_SequentialPlaceholders;
var
	LData1, LData2: string;
	LJson: string;
	LBytes: TBytes;
	LResult: TPreScanResult;
begin
	LData1 := MakeBase64(2000);
	LData2 := MakeBase64(3000);
	LJson := '{"chunks":[{"inlineImage":{"mimeType":"image/png","data":"' + LData1 +
		'"}},{"inlineImage":{"mimeType":"image/jpeg","data":"' + LData2 + '"}}]}';
	LBytes := MakeJsonBytes(LJson);
	LResult := PreScanGeminiFile(LBytes);
	Assert.AreEqual<Integer>(2, Length(LResult.Locations), 'Should have 2 locations');
	Assert.IsTrue(LResult.StrippedJson.Contains('__LAZY:0'), 'Should have __LAZY:0');
	Assert.IsTrue(LResult.StrippedJson.Contains('__LAZY:1'), 'Should have __LAZY:1');
end;

procedure TTestPreScanner.Scan_LocationOffsets_MatchOriginalBytes;
var
	LData: string;
	LJson: string;
	LBytes: TBytes;
	LResult: TPreScanResult;
	LLocation: TBase64Location;
	LExtracted: string;
begin
	LData := MakeBase64(2000);
	LJson := '{"data":"' + LData + '"}';
	LBytes := MakeJsonBytes(LJson);
	LResult := PreScanGeminiFile(LBytes);
	Assert.AreEqual<Integer>(1, Length(LResult.Locations));

	LLocation := LResult.Locations[0];
	LExtracted := TEncoding.UTF8.GetString(LBytes, LLocation.ByteOffset, LLocation.ByteLength);
	Assert.AreEqual(LData, LExtracted, 'Extracted data should match original');
end;

procedure TTestPreScanner.Scan_EscapedQuotesInText_NotConfusedWithKey;
var
	LData: string;
	LJson: string;
	LBytes: TBytes;
	LResult: TPreScanResult;
begin
	LData := MakeBase64(2000);
	LJson := '{"text":"He said \"data\" is important","data":"' + LData + '"}';
	LBytes := MakeJsonBytes(LJson);
	LResult := PreScanGeminiFile(LBytes);
	Assert.AreEqual<Integer>(1, Length(LResult.Locations),
		'Should strip exactly 1 data value (the real one)');
	Assert.IsTrue(LResult.StrippedJson.Contains('__LAZY:0'));
	Assert.IsTrue(LResult.StrippedJson.Contains('He said \"data\" is important'),
		'Text with escaped quotes should be preserved');
end;

procedure TTestPreScanner.Scan_DataKeyAsValueContext_NotStripped;
var
	LJson: string;
	LBytes: TBytes;
	LResult: TPreScanResult;
begin
	LJson := '{"key":"data","value":"something"}';
	LBytes := MakeJsonBytes(LJson);
	LResult := PreScanGeminiFile(LBytes);
	Assert.AreEqual(LJson, LResult.StrippedJson, 'Should pass through unchanged');
	Assert.AreEqual<Integer>(0, Length(LResult.Locations));
end;

procedure TTestPreScanner.Scan_EmptyInput_ReturnsEmpty;
var
	LBytes: TBytes;
	LResult: TPreScanResult;
begin
	SetLength(LBytes, 0);
	LResult := PreScanGeminiFile(LBytes);
	Assert.AreEqual('', LResult.StrippedJson);
	Assert.AreEqual<Integer>(0, Length(LResult.Locations));
end;

procedure TTestPreScanner.Scan_WithBOM_SkipsBOM;
var
	LJson: string;
	LBytes, LBomBytes: TBytes;
	LResult: TPreScanResult;
begin
	LJson := '{"name":"test"}';
	LBytes := TEncoding.UTF8.GetBytes(LJson);
	SetLength(LBomBytes, 3 + Length(LBytes));
	LBomBytes[0] := $EF; LBomBytes[1] := $BB; LBomBytes[2] := $BF;
	Move(LBytes[0], LBomBytes[3], Length(LBytes));

	LResult := PreScanGeminiFile(LBomBytes);
	Assert.AreEqual(LJson, LResult.StrippedJson, 'BOM should be skipped in output');
end;

procedure TTestPreScanner.Scan_DataFollowedByNonString_NotStripped;
var
	LJson: string;
	LBytes: TBytes;
	LResult: TPreScanResult;
begin
	LJson := '{"data": 42, "name":"test"}';
	LBytes := MakeJsonBytes(LJson);
	LResult := PreScanGeminiFile(LBytes);
	Assert.AreEqual(LJson, LResult.StrippedJson, 'Non-string data value should pass through');
	Assert.AreEqual<Integer>(0, Length(LResult.Locations));
end;

procedure TTestPreScanner.Scan_StrippedJsonIsParseable;
var
	LData: string;
	LJson: string;
	LBytes: TBytes;
	LResult: TPreScanResult;
	LRoot: TJSONValue;
begin
	LData := MakeBase64(2000);
	LJson := '{"chunkedPrompt":{"chunks":[{"inlineImage":{"mimeType":"image/png","data":"' +
		LData + '"}}]}}';
	LBytes := MakeJsonBytes(LJson);
	LResult := PreScanGeminiFile(LBytes);

	LRoot := TJSONObject.ParseJSONValue(LResult.StrippedJson);
	try
		Assert.IsNotNull(LRoot, 'Stripped JSON should be parseable');
	finally
		LRoot.Free;
	end;
end;

procedure TTestPreScanner.Scan_RealFileWithResources_StrippedCorrectly;
var
	LPath: string;
	LBytes: TBytes;
	LResult: TPreScanResult;
	LRoot: TJSONValue;
	LStream: TFileStream;
begin
	LPath := TPath.Combine(
		TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
			TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
		'examples');
	if not TDirectory.Exists(LPath) then
		LPath := TPath.GetFullPath('..\examples');

	LPath := TPath.Combine(LPath, 'Gadget Hackwrench In Tulle Dress');
	if not FileExists(LPath) then
		Exit;

	LStream := TFileStream.Create(LPath, fmOpenRead or fmShareDenyNone);
	try
		SetLength(LBytes, LStream.Size);
		if LStream.Size > 0 then
			LStream.ReadBuffer(LBytes[0], LStream.Size);
	finally
		LStream.Free;
	end;

	LResult := PreScanGeminiFile(LBytes);
	// File has 4 images, each appears in both inlineImage and parts.inlineData = 8 "data" keys
	Assert.IsTrue(Length(LResult.Locations) >= 4,
		Format('Gadget file should have at least 4 data locations, got %d', [Length(LResult.Locations)]));

	Assert.IsTrue(Length(LResult.StrippedJson) < Length(LBytes),
		'Stripped JSON should be smaller than original');

	LRoot := TJSONObject.ParseJSONValue(LResult.StrippedJson);
	try
		Assert.IsNotNull(LRoot, 'Stripped real file JSON should be parseable');
	finally
		LRoot.Free;
	end;
end;

procedure TTestPreScanner.Scan_RealFileWithoutResources_IdenticalOutput;
var
	LPath: string;
	LBytes: TBytes;
	LResult: TPreScanResult;
	LOriginal: string;
	LStream: TFileStream;
begin
	LPath := TPath.Combine(
		TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
			TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
		'examples');
	if not TDirectory.Exists(LPath) then
		LPath := TPath.GetFullPath('..\examples');

	LPath := TPath.Combine(LPath, 'Tailscale');
	if not FileExists(LPath) then
		Exit;

	LStream := TFileStream.Create(LPath, fmOpenRead or fmShareDenyNone);
	try
		SetLength(LBytes, LStream.Size);
		if LStream.Size > 0 then
			LStream.ReadBuffer(LBytes[0], LStream.Size);
	finally
		LStream.Free;
	end;

	LOriginal := TEncoding.UTF8.GetString(LBytes);
	LResult := PreScanGeminiFile(LBytes);
	Assert.AreEqual<Integer>(0, Length(LResult.Locations), 'Tailscale should have 0 locations');
	Assert.AreEqual(LOriginal, LResult.StrippedJson,
		'File without resources should be identical after scan');
end;

// =========================================================================
// TTestLazyLoad
// =========================================================================

procedure TTestLazyLoad.LoadBase64_ReturnsCorrectContent;
var
	LTempFile: string;
	LContent: string;
	LBytes: TBytes;
	LLocation: TBase64Location;
	LResult: string;
	LPrefixLen: Integer;
begin
	LContent := '{"data":"SGVsbG8gV29ybGQ="}';
	LBytes := TEncoding.UTF8.GetBytes(LContent);
	LTempFile := TPath.Combine(TPath.GetTempPath, 'lazy_test_' + TGUID.NewGuid.ToString);
	TFile.WriteAllBytes(LTempFile, LBytes);
	try
		LPrefixLen := Length(TEncoding.UTF8.GetBytes('{"data":"'));
		LLocation.ByteOffset := LPrefixLen;
		LLocation.ByteLength := Length(TEncoding.UTF8.GetBytes('SGVsbG8gV29ybGQ='));
		LResult := LoadBase64FromFile(LTempFile, LLocation);
		Assert.AreEqual('SGVsbG8gV29ybGQ=', LResult);
	finally
		TFile.Delete(LTempFile);
	end;
end;

procedure TTestLazyLoad.LoadBase64_FileNotFound_RaisesError;
begin
	Assert.WillRaise(
		procedure
		var
			LLocation: TBase64Location;
		begin
			LLocation.ByteOffset := 0;
			LLocation.ByteLength := 10;
			LoadBase64FromFile('nonexistent_file_xyz_123', LLocation);
		end,
		ELazyLoadError);
end;

procedure TTestLazyLoad.LoadBase64_OffsetBeyondSize_RaisesError;
var
	LTempFile: string;
begin
	LTempFile := TPath.Combine(TPath.GetTempPath, 'lazy_test_' + TGUID.NewGuid.ToString);
	TFile.WriteAllText(LTempFile, 'short');
	try
		Assert.WillRaise(
			procedure
			var
				LLocation: TBase64Location;
			begin
				LLocation.ByteOffset := 1000;
				LLocation.ByteLength := 10;
				LoadBase64FromFile(LTempFile, LLocation);
			end,
			ELazyLoadError);
	finally
		TFile.Delete(LTempFile);
	end;
end;

// =========================================================================
// TTestLazyResource
// =========================================================================

procedure TTestLazyResource.CreateTempFile(const ABase64: string);
var
	LJson: string;
	LBytes: TBytes;
begin
	LJson := '{"data":"' + ABase64 + '"}';
	LBytes := TEncoding.UTF8.GetBytes(LJson);
	FTempFile := TPath.Combine(TPath.GetTempPath, 'lazy_res_' + TGUID.NewGuid.ToString);
	TFile.WriteAllBytes(FTempFile, LBytes);
end;

procedure TTestLazyResource.TearDown;
begin
	if (FTempFile <> '') and TFile.Exists(FTempFile) then
		TFile.Delete(FTempFile);
	FTempFile := '';
end;

procedure TTestLazyResource.CreateLazy_DecodedSize_EstimatesWithoutLoading;
var
	LRes: TGeminiResource;
	LLocation: TBase64Location;
begin
	LLocation.ByteOffset := 0;
	LLocation.ByteLength := 1000;
	LRes := TGeminiResource.CreateLazy('image/png', 0, 'no_file', LLocation);
	try
		Assert.AreEqual(Int64(750), LRes.DecodedSize,
			'Should estimate decoded size from byte length');
	finally
		LRes.Free;
	end;
end;

procedure TTestLazyResource.CreateLazy_Base64Size_ReportsWithoutLoading;
var
	LRes: TGeminiResource;
	LLocation: TBase64Location;
begin
	LLocation.ByteOffset := 0;
	LLocation.ByteLength := 2000;
	LRes := TGeminiResource.CreateLazy('image/png', 0, 'no_file', LLocation);
	try
		Assert.AreEqual(Int64(2000), LRes.Base64Size,
			'Should report base64 size from byte length');
	finally
		LRes.Free;
	end;
end;

procedure TTestLazyResource.CreateLazy_Base64Data_TriggersLoad;
var
	LRes: TGeminiResource;
	LLocation: TBase64Location;
	LBase64: string;
	LPrefixLen: Integer;
begin
	LBase64 := 'SGVsbG8gV29ybGQ=';
	CreateTempFile(LBase64);

	LPrefixLen := Length(TEncoding.UTF8.GetBytes('{"data":"'));
	LLocation.ByteOffset := LPrefixLen;
	LLocation.ByteLength := Length(TEncoding.UTF8.GetBytes(LBase64));

	LRes := TGeminiResource.CreateLazy('text/plain', 0, FTempFile, LLocation);
	try
		Assert.AreEqual(LBase64, LRes.Base64Data, 'Base64Data should trigger load');
	finally
		LRes.Free;
	end;
end;

procedure TTestLazyResource.CreateLazy_Decode_LoadsAndDecodes;
var
	LRes: TGeminiResource;
	LLocation: TBase64Location;
	LBase64: string;
	LStream: TMemoryStream;
	LBytes: TBytes;
	LPrefixLen: Integer;
begin
	LBase64 := 'SGVsbG8=';
	CreateTempFile(LBase64);

	LPrefixLen := Length(TEncoding.UTF8.GetBytes('{"data":"'));
	LLocation.ByteOffset := LPrefixLen;
	LLocation.ByteLength := Length(TEncoding.UTF8.GetBytes(LBase64));

	LRes := TGeminiResource.CreateLazy('text/plain', 0, FTempFile, LLocation);
	try
		LStream := TMemoryStream.Create;
		try
			LRes.SaveToStream(LStream);
			Assert.AreEqual(Int64(5), LStream.Size, 'Decoded "Hello" should be 5 bytes');
			SetLength(LBytes, LStream.Size);
			LStream.Position := 0;
			LStream.ReadBuffer(LBytes[0], LStream.Size);
			Assert.AreEqual('Hello', TEncoding.UTF8.GetString(LBytes));
		finally
			LStream.Free;
		end;
	finally
		LRes.Free;
	end;
end;

procedure TTestLazyResource.CreateLazy_SaveToStream_Works;
var
	LRes: TGeminiResource;
	LLocation: TBase64Location;
	LBase64: string;
	LStream: TMemoryStream;
	LPrefixLen: Integer;
begin
	LBase64 := 'SGVsbG8=';
	CreateTempFile(LBase64);

	LPrefixLen := Length(TEncoding.UTF8.GetBytes('{"data":"'));
	LLocation.ByteOffset := LPrefixLen;
	LLocation.ByteLength := Length(TEncoding.UTF8.GetBytes(LBase64));

	LRes := TGeminiResource.CreateLazy('text/plain', 0, FTempFile, LLocation);
	try
		LStream := TMemoryStream.Create;
		try
			LRes.SaveToStream(LStream);
			Assert.IsTrue(LStream.Size > 0, 'SaveToStream should produce output');
		finally
			LStream.Free;
		end;
	finally
		LRes.Free;
	end;
end;

procedure TTestLazyResource.CreateLazy_ReleaseAll_ThenReload_Works;
var
	LRes: TGeminiResource;
	LLocation: TBase64Location;
	LBase64: string;
	LStream: TMemoryStream;
	LPrefixLen: Integer;
begin
	LBase64 := 'SGVsbG8=';
	CreateTempFile(LBase64);

	LPrefixLen := Length(TEncoding.UTF8.GetBytes('{"data":"'));
	LLocation.ByteOffset := LPrefixLen;
	LLocation.ByteLength := Length(TEncoding.UTF8.GetBytes(LBase64));

	LRes := TGeminiResource.CreateLazy('text/plain', 0, FTempFile, LLocation);
	try
		LRes.Decode;
		Assert.IsTrue(LRes.IsDecoded);
		Assert.AreEqual(Int64(5), LRes.DecodedSize);

		LRes.ReleaseAll;
		Assert.IsFalse(LRes.IsDecoded);

		LStream := TMemoryStream.Create;
		try
			LRes.SaveToStream(LStream);
			Assert.AreEqual(Int64(5), LStream.Size, 'Re-load after ReleaseAll should work');
		finally
			LStream.Free;
		end;
	finally
		LRes.Free;
	end;
end;

procedure TTestLazyResource.CreateLazy_FileDeleted_RaisesOnAccess;
var
	LRes: TGeminiResource;
	LLocation: TBase64Location;
	LBase64: string;
	LPrefixLen: Integer;
begin
	LBase64 := 'SGVsbG8=';
	CreateTempFile(LBase64);

	LPrefixLen := Length(TEncoding.UTF8.GetBytes('{"data":"'));
	LLocation.ByteOffset := LPrefixLen;
	LLocation.ByteLength := Length(TEncoding.UTF8.GetBytes(LBase64));

	LRes := TGeminiResource.CreateLazy('text/plain', 0, FTempFile, LLocation);
	try
		TFile.Delete(FTempFile);
		FTempFile := '';

		Assert.WillRaise(
			procedure
			begin
				LRes.Decode;
			end,
			ELazyLoadError);
	finally
		LRes.Free;
	end;
end;

procedure TTestLazyResource.CreateLazy_IsLazy_ReturnsTrue;
var
	LRes: TGeminiResource;
	LLocation: TBase64Location;
begin
	LLocation.ByteOffset := 0;
	LLocation.ByteLength := 100;
	LRes := TGeminiResource.CreateLazy('image/png', 0, 'file', LLocation);
	try
		Assert.IsTrue(LRes.IsLazy);
	finally
		LRes.Free;
	end;
end;

procedure TTestLazyResource.Create_Regular_IsLazy_ReturnsFalse;
var
	LRes: TGeminiResource;
begin
	LRes := TGeminiResource.Create('image/png', 'AAAA', 0);
	try
		Assert.IsFalse(LRes.IsLazy);
	finally
		LRes.Free;
	end;
end;

// =========================================================================
// TTestLazyIntegration
// =========================================================================

function TTestLazyIntegration.ExamplesDir: string;
begin
	Result := TPath.Combine(
		TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
			TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
		'examples');
	if not TDirectory.Exists(Result) then
		Result := TPath.GetFullPath('..\examples');
end;

function TTestLazyIntegration.FindExample(const AName: string): string;
begin
	Result := TPath.Combine(ExamplesDir, AName);
	if FileExists(Result) then
		Exit;
	Result := '';
end;

procedure TTestLazyIntegration.LoadFromFile_WithResources_ResourcesAreLazy;
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
			Assert.IsTrue(LResources[I].IsLazy,
				Format('Resource %d should be lazy', [I]));
	finally
		LFile.Free;
	end;
end;

procedure TTestLazyIntegration.LoadFromFile_WithResources_DecodedSizeCorrect;
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
		for I := 0 to High(LResources) do
			Assert.IsTrue(LResources[I].DecodedSize > 0,
				Format('Resource %d DecodedSize should be > 0', [I]));
	finally
		LFile.Free;
	end;
end;

procedure TTestLazyIntegration.LoadFromFile_WithResources_ExtractWorks;
var
	LFile: TGeminiFile;
	LPath, LOutDir: string;
	LCount: Integer;
	LFiles: TArray<string>;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then
		Exit;

	LOutDir := TPath.Combine(TPath.GetTempPath, 'GemViewTest_Lazy_' + TGUID.NewGuid.ToString);
	LFile := TGeminiFile.Create;
	try
		LFile.LoadFromFile(LPath);
		LCount := LFile.ExtractAllResources(LOutDir, False, 'resource');
		Assert.AreEqual<Integer>(4, LCount, 'Should extract 4 resources');

		LFiles := TDirectory.GetFiles(LOutDir);
		Assert.AreEqual<Integer>(4, Length(LFiles), 'Should produce 4 files');

		Assert.IsTrue(TFile.GetSize(TPath.Combine(LOutDir, 'resource_000.jpg')) > 0,
			'Extracted file should be non-empty');
	finally
		LFile.Free;
		if TDirectory.Exists(LOutDir) then
			TDirectory.Delete(LOutDir, True);
	end;
end;

procedure TTestLazyIntegration.LoadFromFile_NoResources_NormalParsing;
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
		Assert.AreEqual<Integer>(40, LFile.ChunkCount, 'Tailscale should have 40 chunks');
		Assert.AreEqual<Integer>(0, LFile.GetResourceCount, 'Tailscale should have 0 resources');
	finally
		LFile.Free;
	end;
end;

procedure TTestLazyIntegration.LoadFromStream_ResourcesAreNotLazy;
var
	LFile: TGeminiFile;
	LStream: TStringStream;
	LResources: TArray<TGeminiResource>;
begin
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
		Assert.AreEqual<Integer>(1, Length(LResources));
		Assert.IsFalse(LResources[0].IsLazy,
			'Stream-loaded resources should not be lazy');
	finally
		LFile.Free;
	end;
end;

procedure TTestLazyIntegration.LoadFromFile_ProducesSameChunksAsLoadFromStream;
var
	LFileLoaded, LStreamLoaded: TGeminiFile;
	LPath: string;
	LStream: TFileStream;
	I: Integer;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then
		Exit;

	LFileLoaded := TGeminiFile.Create;
	LStreamLoaded := TGeminiFile.Create;
	try
		LFileLoaded.LoadFromFile(LPath);

		LStream := TFileStream.Create(LPath, fmOpenRead or fmShareDenyNone);
		try
			LStreamLoaded.LoadFromStream(LStream);
		finally
			LStream.Free;
		end;

		Assert.AreEqual<Integer>(LStreamLoaded.ChunkCount, LFileLoaded.ChunkCount,
			'Chunk count should match');
		Assert.AreEqual<Integer>(LStreamLoaded.GetResourceCount, LFileLoaded.GetResourceCount,
			'Resource count should match');
		Assert.AreEqual(LStreamLoaded.SystemInstruction, LFileLoaded.SystemInstruction,
			'System instruction should match');

		for I := 0 to LFileLoaded.ChunkCount - 1 do
			Assert.AreEqual(
				LStreamLoaded.Chunks[I].GetFullText,
				LFileLoaded.Chunks[I].GetFullText,
				Format('Chunk %d text should match', [I]));
	finally
		LFileLoaded.Free;
		LStreamLoaded.Free;
	end;
end;

initialization
	TDUnitX.RegisterTestFixture(TTestPreScanner);
	TDUnitX.RegisterTestFixture(TTestLazyLoad);
	TDUnitX.RegisterTestFixture(TTestLazyResource);
	TDUnitX.RegisterTestFixture(TTestLazyIntegration);

end.
