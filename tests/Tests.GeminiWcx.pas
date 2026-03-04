/// <summary>
///   Unit tests for WCX plugin logic (TGeminiArchive).
///   Tests virtual file list, header iteration, and file extraction.
///   Directly tests the class -- no DLL loading required.
/// </summary>
unit Tests.GeminiWcx;

interface

uses
	System.SysUtils,
	System.Classes,
	System.IOUtils,
	System.Types,
	System.Generics.Collections,
	DUnitX.TestFramework,
	WcxApi,
	GeminiWcx,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.Parser,
	GeminiFile.Extractor,
	GeminiFile;

type
	[TestFixture]
	TTestGeminiWcxVirtualFileList = class
	public
		[Test]
		procedure FileWithNoResources_ThreeVirtualFiles;
		[Test]
		procedure FileWithResources_IncludesAllTypes;
		[Test]
		procedure ResourceFilenames_FollowNamingPattern;
		[Test]
		procedure FileSizes_NonZeroForAllEntries;
		[Test]
		procedure FileTime_SetFromSourceFile;
		[Test]
		procedure ResourcePaths_MatchResourceInfoPaths;
	end;

	[TestFixture]
	TTestGeminiWcxReadHeader = class
	public
		[Test]
		procedure IteratesAllFiles_ThenEndArchive;
		[Test]
		procedure HeaderFields_PopulatedCorrectly;
		[Test]
		procedure DirectoryEntry_HasDirectoryAttribute;
	end;

	[TestFixture]
	TTestGeminiWcxProcessFile = class
	public
		[Test]
		procedure Skip_AdvancesToNextFile;
		[Test]
		procedure ExtractTextFile_WritesCorrectContent;
		[Test]
		procedure ExtractResource_WritesDecodedBinary;
		[Test]
		procedure ExtractToInvalidPath_ReturnsError;
	end;

	[TestFixture]
	TTestGeminiWcxProcessHtml = class
	private
		/// <summary>
		///   Extracts the HTML virtual file from an archive and returns its content.
		///   Skips entries until conversation.html is found.
		/// </summary>
		function ExtractHtmlContent(const AExampleName: string): string;
	public
		[Test]
		procedure HtmlOutput_BodyHasMdClass;
		[Test]
		procedure HtmlOutput_ContainsMarkdownCss;
		[Test]
		procedure HtmlOutput_ModelTextRenderedAsMarkdown;
	end;

	[TestFixture]
	TTestGeminiWcxGetBaseName = class
	public
		[Test]
		procedure WithUseOriginalName_ReturnsFileNameWithoutExt;
		[Test]
		procedure WithoutUseOriginalName_ReturnsConversation;
	end;

	[TestFixture]
	TTestGeminiWcxPluginConfig = class
	public
		[Test]
		procedure DefaultConfig_RenderMarkdownIsTrue;
		[Test]
		procedure DefaultConfig_HideEmptyBlocksAllTrue;
		[Test]
		procedure DefaultConfig_FullWidthIsFalse;
		[Test]
		procedure DefaultConfig_ExpandThinkingIsFalse;
		[Test]
		procedure DefaultConfig_CombineBlocksAllFalse;
		[Test]
		procedure DefaultConfig_EnableFormatsAllTrue;
	end;

	/// <summary>
	///   Tests for exported WCX API functions (Unicode variants).
	///   Exercises the exported function wrappers, handle validation,
	///   CanYouHandleThisFile file sniffing, and error handling paths.
	/// </summary>
	[TestFixture]
	TTestGeminiWcxExportedApi = class
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
		procedure GetPackerCaps_ReturnsCorrectFlags;
		[Test]
		procedure GetBackgroundFlags_ReturnsBackgroundUnpack;
		[Test]
		procedure CanYouHandleThisFileW_GeminiJson_ReturnsTrue;
		[Test]
		procedure CanYouHandleThisFileW_NonGeminiJson_ReturnsFalse;
		[Test]
		procedure CanYouHandleThisFileW_NonJson_ReturnsFalse;
		[Test]
		procedure CanYouHandleThisFileW_NonExistent_ReturnsFalse;
		[Test]
		procedure CanYouHandleThisFileW_WithBom_ReturnsTrue;
		[Test]
		procedure CanYouHandleThisFileW_WithWhitespace_ReturnsTrue;
		[Test]
		procedure CanYouHandleThisFileW_EmptyFile_ReturnsFalse;
		[Test]
		procedure OpenArchiveW_ValidFile_ReturnsHandle;
		[Test]
		procedure OpenArchiveW_NonExistentFile_SetsEOpen;
		[Test]
		procedure OpenArchiveW_InvalidContent_SetsBadArchive;
		[Test]
		procedure CloseArchive_ValidHandle_ReturnsZero;
		[Test]
		procedure CloseArchive_InvalidHandle_ReturnsBadArchive;
		[Test]
		procedure ReadHeaderExW_InvalidHandle_ReturnsBadArchive;
		[Test]
		procedure ProcessFileW_InvalidHandle_ReturnsBadArchive;
		[Test]
		procedure ProcessFileW_NilDestPath_UsesDestName;
		[Test]
		procedure ProcessFileW_DestPathOnly_CombinesEntryPath;
		[Test]
		procedure ProcessFileW_PkTest_ReturnsZero;
		[Test]
		procedure SetChangeVolProcW_InvalidHandle_NoException;
		[Test]
		procedure SetChangeVolProcW_ValidHandle_SetsCallback;
		[Test]
		procedure SetProcessDataProcW_CallbackInvoked;
		[Test]
		procedure ExportedApi_FullListLifecycle;
		[Test]
		procedure CanYouHandleThisFileW_PartialBom_ReturnsFalse;
		[Test]
		procedure ProcessCurrentFile_AfterExhaustion_ReturnsEndArchive;
		[Test]
		procedure ProcessFileW_ExtractBothPathsNil_ReturnsECreate;
		[Test]
		procedure CanYouHandleThisFileW_WhitespaceOnly_ReturnsFalse;
		[Test]
		procedure CanYouHandleThisFileW_BraceNoMarker_ReturnsFalse;
		[Test]
		procedure CanYouHandleThisFileW_ZeroBytesRead_ReturnsFalse;
		[Test]
		procedure OpenArchiveW_MalformedJson_SetsBadData;
	end;

	/// <summary>
	///   Tests for ANSI compatibility WCX functions.
	///   Verifies that ANSI wrappers correctly delegate to Unicode implementations.
	/// </summary>
	[TestFixture]
	TTestGeminiWcxAnsiCompat = class
	private
		FTempDir: string;
		function CreateTempFile(const AName, AContent: string): string;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;

		[Test]
		procedure OpenArchive_Ansi_ReturnsHandle;
		[Test]
		procedure ReadHeader_Ansi_PopulatesFields;
		[Test]
		procedure ReadHeaderEx_Ansi_PopulatesFields;
		[Test]
		procedure ProcessFile_Ansi_SkipWorks;
		[Test]
		procedure ProcessFile_Ansi_ExtractWithPaths;
		[Test]
		procedure CanYouHandleThisFile_Ansi_Works;
		[Test]
		procedure SetChangeVolProc_Ansi_NoOp;
		[Test]
		procedure SetProcessDataProc_Ansi_NoOp;
		[Test]
		procedure ProcessFile_Ansi_ExtractBothPathsNil_ReturnsECreate;
		[Test]
		procedure OpenArchive_Ansi_NonExistent_SetsEOpen;
	end;

	/// <summary>
	///   Tests for special extraction paths (embedded HTML, directories).
	/// </summary>
	[TestFixture]
	TTestGeminiWcxExtractSpecial = class
	private
		FTempDir: string;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;

		[Test]
		procedure ExtractEmbeddedHtml_ProducesContent;
		[Test]
		procedure ExtractResourceDir_CreatesDirectory;
		[Test]
		procedure ExtractMarkdownFile_ProducesContent;
		[Test]
		procedure ExtractEmbeddedHtml_IncludesCustomCSS;
		[Test]
		procedure ExtractTextToReadOnlyFile_ReturnsECreate;
		[Test]
		procedure ExtractEmbeddedHtmlToReadOnlyFile_ReturnsECreate;
		[Test]
		procedure ExtractResourceToReadOnlyFile_ReturnsEWrite;
	end;

implementation

uses
	Tests.GeminiFile.TestUtils;

// ========================================================================
// TTestGeminiWcxVirtualFileList
// ========================================================================

procedure TTestGeminiWcxVirtualFileList.FileWithNoResources_ThreeVirtualFiles;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LCount: Integer;
	LPath: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		LCount := 0;
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			Inc(LCount);
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		// No resources: conversation.txt, conversation.md, conversation.html
		Assert.AreEqual<Integer>(3, LCount, 'Should have 3 virtual files for no-resource file');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxVirtualFileList.FileWithResources_IncludesAllTypes;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LCount: Integer;
	LPath: string;
	LHasDir, LHasEmbedded, LHasThinkDir: Boolean;
	LFileName: string;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		LCount := 0;
		LHasDir := False;
		LHasEmbedded := False;
		LHasThinkDir := False;
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			Inc(LCount);
			LFileName := LHeader.FileName;
			if LFileName = 'resources' then
				LHasDir := True;
			if LFileName = 'resources\think' then
				LHasThinkDir := True;
			if LFileName.EndsWith('_full.html') then
				LHasEmbedded := True;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		// 3 conversations + embedded html + resources dir + think dir + 4 resources = 10
		Assert.AreEqual<Integer>(10, LCount, 'Should have 10 virtual files');
		Assert.IsTrue(LHasDir, 'Should have resources directory');
		Assert.IsTrue(LHasThinkDir, 'Should have resources\think directory');
		Assert.IsTrue(LHasEmbedded, 'Should have embedded HTML');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxVirtualFileList.ResourceFilenames_FollowNamingPattern;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LFileName: string;
	LFoundResource: Boolean;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		LFoundResource := False;
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			if LFileName.StartsWith('resources\resource_') or
				LFileName.StartsWith('resources\think\resource_') then
			begin
				LFoundResource := True;
				Assert.IsTrue(LFileName.EndsWith('.jpg') or LFileName.EndsWith('.png') or
					LFileName.EndsWith('.bin'),
					'Resource should have valid extension: ' + LFileName);
			end;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		Assert.IsTrue(LFoundResource, 'Should find at least one resource file');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxVirtualFileList.FileSizes_NonZeroForAllEntries;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LFileName: string;
	LSize: Int64;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			LSize := Int64(LHeader.UnpSize) or (Int64(LHeader.UnpSizeHigh) shl 32);
			Assert.IsTrue(LSize > 0, 'Size should be > 0 for ' + LFileName);
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxVirtualFileList.FileTime_SetFromSourceFile;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		if LArchive.ReadNextHeader(LHeader) = 0 then
		begin
			Assert.IsTrue(LHeader.FileTime > 0,
				'FileTime should be set from source file modification time');
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxVirtualFileList.ResourcePaths_MatchResourceInfoPaths;
var
	LGeminiFile: TGeminiFile;
	LResources: TArray<TGeminiResource>;
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LFileName: string;
	LExpectedPaths: TArray<string>;
	I, LPadWidth: Integer;
	LChunk: TGeminiChunk;
	LIsThinking: Boolean;
	LSubDir: string;
	LResourcePaths: TList<string>;
begin
	// Verify that virtual file list paths for resources correspond exactly
	// to the resource info paths (with / replaced by \)
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then
		Exit;

	// Build expected paths independently using the same naming rules
	LGeminiFile := TGeminiFile.Create;
	try
		LGeminiFile.LoadFromFile(LPath);
		LResources := LGeminiFile.GetResources;
		LPadWidth := ResourcePadWidth(Length(LResources));

		SetLength(LExpectedPaths, Length(LResources));
		for I := 0 to High(LResources) do
		begin
			LIsThinking := False;
			for LChunk in LGeminiFile.Chunks do
				if LChunk.Index = LResources[I].ChunkIndex then
				begin
					LIsThinking := LChunk.IsThought;
					Break;
				end;
			if LIsThinking then
				LSubDir := 'resources\think\'
			else
				LSubDir := 'resources\';
			LExpectedPaths[I] := Format(LSubDir + 'resource_%.*d%s',
				[LPadWidth, I, LResources[I].GetFileExtension]);
		end;
	finally
		LGeminiFile.Free;
	end;

	// Collect resource paths from the archive
	LResourcePaths := TList<string>.Create;
	try
		LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
		try
			while LArchive.ReadNextHeader(LHeader) = 0 do
			begin
				LFileName := LHeader.FileName;
				if LFileName.StartsWith('resources\resource_') or
					LFileName.StartsWith('resources\think\resource_') then
					LResourcePaths.Add(LFileName);
				LArchive.ProcessCurrentFile(PK_SKIP, '', '');
			end;
		finally
			LArchive.Free;
		end;

		Assert.AreEqual(Length(LExpectedPaths), LResourcePaths.Count,
			'Resource count mismatch between expected and actual');
		for I := 0 to LResourcePaths.Count - 1 do
			Assert.AreEqual(LExpectedPaths[I], LResourcePaths[I],
				Format('Resource path mismatch at index %d', [I]));
	finally
		LResourcePaths.Free;
	end;
end;

// ========================================================================
// TTestGeminiWcxReadHeader
// ========================================================================

procedure TTestGeminiWcxReadHeader.IteratesAllFiles_ThenEndArchive;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LResult: Integer;
	LPath: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		// Skip all files
		while LArchive.ReadNextHeader(LHeader) = 0 do
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		// Next call should return E_END_ARCHIVE
		LResult := LArchive.ReadNextHeader(LHeader);
		Assert.AreEqual<Integer>(E_END_ARCHIVE, LResult);
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxReadHeader.HeaderFields_PopulatedCorrectly;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LFileName: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		Assert.AreEqual<Integer>(0, LArchive.ReadNextHeader(LHeader));
		LFileName := LHeader.FileName;
		Assert.AreEqual('Tailscale.txt', LFileName);
		Assert.IsTrue(LHeader.UnpSize > 0, 'UnpSize should be non-zero');
		Assert.IsTrue(LHeader.FileTime > 0, 'FileTime should be non-zero');
		Assert.AreEqual<Integer>($20, LHeader.FileAttr); // FILE_ATTRIBUTE_ARCHIVE
		LArchive.ProcessCurrentFile(PK_SKIP, '', '');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxReadHeader.DirectoryEntry_HasDirectoryAttribute;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LFileName: string;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			if LFileName = 'resources' then
			begin
				Assert.AreEqual<Integer>(faDirectory, LHeader.FileAttr,
					'Directory entry should have faDirectory attribute');
				LArchive.ProcessCurrentFile(PK_SKIP, '', '');
				Exit;
			end;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		Assert.Fail('resources directory entry not found');
	finally
		LArchive.Free;
	end;
end;

// ========================================================================
// TTestGeminiWcxProcessFile
// ========================================================================

procedure TTestGeminiWcxProcessFile.Skip_AdvancesToNextFile;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LFileName: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		// Read first header
		Assert.AreEqual<Integer>(0, LArchive.ReadNextHeader(LHeader));
		LFileName := LHeader.FileName;
		Assert.AreEqual('Tailscale.txt', LFileName);

		// Skip it
		Assert.AreEqual<Integer>(0, LArchive.ProcessCurrentFile(PK_SKIP, '', ''));

		// Read next header -- should be different file
		Assert.AreEqual<Integer>(0, LArchive.ReadNextHeader(LHeader));
		LFileName := LHeader.FileName;
		Assert.AreEqual('Tailscale.md', LFileName);
		LArchive.ProcessCurrentFile(PK_SKIP, '', '');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxProcessFile.ExtractTextFile_WritesCorrectContent;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutDir, LOutFile: string;
	LContent: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LOutDir := TPath.Combine(TPath.GetTempPath,
		'GemViewTest_Wcx_' + TGUID.NewGuid.ToString);
	LOutFile := TPath.Combine(LOutDir, 'Tailscale.txt');

	LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
	try
		// Read first header (Tailscale.txt)
		Assert.AreEqual<Integer>(0, LArchive.ReadNextHeader(LHeader));

		// Extract it
		Assert.AreEqual<Integer>(0, LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutFile));
		Assert.IsTrue(FileExists(LOutFile), 'Output file should exist');

		LContent := TFile.ReadAllText(LOutFile, TEncoding.UTF8);
		Assert.Contains(LContent, '=== Gemini Conversation - Tailscale ===');
		Assert.Contains(LContent, 'models/gemini-2.5-pro');
	finally
		LArchive.Free;
		if TDirectory.Exists(LOutDir) then
			TDirectory.Delete(LOutDir, True);
	end;
end;

procedure TTestGeminiWcxProcessFile.ExtractResource_WritesDecodedBinary;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutDir, LOutFile: string;
	LFileName: string;
	LFileSize: Int64;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then
		Exit;

	LOutDir := TPath.Combine(TPath.GetTempPath,
		'GemViewTest_WcxRes_' + TGUID.NewGuid.ToString);

	LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
	try
		// Skip until we find a resource file
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			if LFileName.StartsWith('resources\resource_') or
				LFileName.StartsWith('resources\think\resource_') then
			begin
				LOutFile := TPath.Combine(LOutDir, TPath.GetFileName(LFileName));
				Assert.AreEqual<Integer>(0,
					LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutFile));
				Assert.IsTrue(FileExists(LOutFile), 'Extracted resource should exist');
				LFileSize := TFile.GetSize(LOutFile);
				Assert.IsTrue(LFileSize > 0, 'Extracted resource should be non-empty');
				Exit; // Only need to test one
			end;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		Assert.Fail('No resource file found to extract');
	finally
		LArchive.Free;
		if TDirectory.Exists(LOutDir) then
			TDirectory.Delete(LOutDir, True);
	end;
end;

procedure TTestGeminiWcxProcessFile.ExtractToInvalidPath_ReturnsError;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LResult: Integer;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
	try
		Assert.AreEqual<Integer>(0, LArchive.ReadNextHeader(LHeader));
		// Empty destination should return error
		LResult := LArchive.ProcessCurrentFile(PK_EXTRACT, '', '');
		Assert.IsTrue(LResult <> 0, 'Should return error for empty destination');
	finally
		LArchive.Free;
	end;
end;

// ========================================================================
// TTestGeminiWcxGetBaseName
// ========================================================================

// ========================================================================
// TTestGeminiWcxProcessHtml
// ========================================================================

function TTestGeminiWcxProcessHtml.ExtractHtmlContent(const AExampleName: string): string;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutDir, LOutFile: string;
	LFileName: string;
begin
	Result := '';
	LPath := FindExample(AExampleName);
	if LPath = '' then
		Exit;

	LOutDir := TPath.Combine(TPath.GetTempPath,
		'GemViewTest_WcxHtml_' + TGUID.NewGuid.ToString);

	LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
	try
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			if LFileName.EndsWith('.html') and (not LFileName.EndsWith('_full.html')) then
			begin
				LOutFile := TPath.Combine(LOutDir, LFileName);
				LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutFile);
				if FileExists(LOutFile) then
					Result := TFile.ReadAllText(LOutFile, TEncoding.UTF8);
				Exit;
			end;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
	finally
		LArchive.Free;
		if TDirectory.Exists(LOutDir) then
			TDirectory.Delete(LOutDir, True);
	end;
end;

procedure TTestGeminiWcxProcessHtml.HtmlOutput_BodyHasMdClass;
var
	LHtml: string;
begin
	LHtml := ExtractHtmlContent('Tailscale');
	if LHtml = '' then
		Exit;
	// Default RenderMarkdown=True should add 'md' class to body
	Assert.Contains(LHtml, 'md');
	Assert.Contains(LHtml, '<body class="');
end;

procedure TTestGeminiWcxProcessHtml.HtmlOutput_ContainsMarkdownCss;
var
	LHtml: string;
begin
	LHtml := ExtractHtmlContent('Tailscale');
	if LHtml = '' then
		Exit;
	// Markdown CSS rules should be present in output
	Assert.Contains(LHtml, 'body.md .content');
	Assert.Contains(LHtml, 'body.md .content pre');
	Assert.Contains(LHtml, 'body.md .content code');
end;

procedure TTestGeminiWcxProcessHtml.HtmlOutput_ModelTextRenderedAsMarkdown;
var
	LHtml: string;
begin
	// Tailscale has model responses that contain ** bold ** markdown
	LHtml := ExtractHtmlContent('Tailscale');
	if LHtml = '' then
		Exit;
	// With RenderMarkdown=True, content divs should not use pre-wrap for
	// markdown-rendered text -- the body.md CSS overrides white-space
	Assert.Contains(LHtml, 'body.md .content { white-space: normal; }');
	// Model output should contain rendered HTML tags, not raw markers
	Assert.Contains(LHtml, '<div class="content"><p>');
end;

// ========================================================================
// TTestGeminiWcxPluginConfig
// ========================================================================

procedure TTestGeminiWcxPluginConfig.DefaultConfig_RenderMarkdownIsTrue;
var
	LConfig: TPluginConfig;
begin
	LConfig := GetPluginConfig;
	Assert.IsTrue(LConfig.RenderMarkdown,
		'RenderMarkdown should default to True');
end;

procedure TTestGeminiWcxPluginConfig.DefaultConfig_HideEmptyBlocksAllTrue;
var
	LConfig: TPluginConfig;
begin
	LConfig := GetPluginConfig;
	Assert.IsTrue(LConfig.HideEmptyBlocksText, 'HideEmptyBlocksText default');
	Assert.IsTrue(LConfig.HideEmptyBlocksMd, 'HideEmptyBlocksMd default');
	Assert.IsTrue(LConfig.HideEmptyBlocksHtml, 'HideEmptyBlocksHtml default');
end;

procedure TTestGeminiWcxPluginConfig.DefaultConfig_FullWidthIsFalse;
var
	LConfig: TPluginConfig;
begin
	LConfig := GetPluginConfig;
	Assert.IsFalse(LConfig.DefaultFullWidth,
		'DefaultFullWidth should default to False');
end;

procedure TTestGeminiWcxPluginConfig.DefaultConfig_ExpandThinkingIsFalse;
var
	LConfig: TPluginConfig;
begin
	LConfig := GetPluginConfig;
	Assert.IsFalse(LConfig.DefaultExpandThinking,
		'DefaultExpandThinking should default to False');
end;

procedure TTestGeminiWcxPluginConfig.DefaultConfig_CombineBlocksAllFalse;
var
	LConfig: TPluginConfig;
begin
	LConfig := GetPluginConfig;
	Assert.IsFalse(LConfig.CombineBlocksText, 'CombineBlocksText default');
	Assert.IsFalse(LConfig.CombineBlocksMd, 'CombineBlocksMd default');
	Assert.IsFalse(LConfig.CombineBlocksHtml, 'CombineBlocksHtml default');
end;

procedure TTestGeminiWcxPluginConfig.DefaultConfig_EnableFormatsAllTrue;
var
	LConfig: TPluginConfig;
begin
	LConfig := GetPluginConfig;
	Assert.IsTrue(LConfig.EnableText, 'EnableText default');
	Assert.IsTrue(LConfig.EnableMarkdown, 'EnableMarkdown default');
	Assert.IsTrue(LConfig.EnableHtml, 'EnableHtml default');
	Assert.IsTrue(LConfig.EnableHtmlEmbedded, 'EnableHtmlEmbedded default');
end;

// ========================================================================
// TTestGeminiWcxGetBaseName
// ========================================================================

procedure TTestGeminiWcxGetBaseName.WithUseOriginalName_ReturnsFileNameWithoutExt;
begin
	Assert.AreEqual('My Chat', GetBaseName('D:\files\My Chat', True),
		'File without extension should return its name');
	Assert.AreEqual('data', GetBaseName('D:\files\data.json', True),
		'File with extension should return name without extension');
end;

procedure TTestGeminiWcxGetBaseName.WithoutUseOriginalName_ReturnsConversation;
begin
	Assert.AreEqual('conversation', GetBaseName('D:\files\My Chat', False));
	Assert.AreEqual('conversation', GetBaseName('D:\files\data.json', False));
end;

// ========================================================================
// Progress callback for SetProcessDataProcW test
// ========================================================================

var
	GProgressCallbackCalled: Boolean;

function TestProgressCallback(FileName: PWideChar; Size: Integer): Integer; stdcall;
begin
	GProgressCallbackCalled := True;
	Result := 0;
end;

// ========================================================================
// TTestGeminiWcxExportedApi
// ========================================================================

function TTestGeminiWcxExportedApi.CreateTempFile(const AName, AContent: string): string;
begin
	Result := TPath.Combine(FTempDir, AName);
	TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

function TTestGeminiWcxExportedApi.CreateTempFileBytes(const AName: string;
	const ABytes: TBytes): string;
var
	LStream: TFileStream;
begin
	Result := TPath.Combine(FTempDir, AName);
	LStream := TFileStream.Create(Result, fmCreate);
	try
		if Length(ABytes) > 0 then
			LStream.WriteBuffer(ABytes[0], Length(ABytes));
	finally
		LStream.Free;
	end;
end;

procedure TTestGeminiWcxExportedApi.Setup;
begin
	FTempDir := TPath.Combine(TPath.GetTempPath,
		'GemViewTest_WcxApi_' + TGUID.NewGuid.ToString);
	ForceDirectories(FTempDir);
end;

procedure TTestGeminiWcxExportedApi.TearDown;
begin
	if TDirectory.Exists(FTempDir) then
		TDirectory.Delete(FTempDir, True);
end;

procedure TTestGeminiWcxExportedApi.GetPackerCaps_ReturnsCorrectFlags;
begin
	Assert.AreEqual<Integer>(
		PK_CAPS_MULTIPLE or PK_CAPS_BY_CONTENT or PK_CAPS_SEARCHTEXT,
		GetPackerCaps, 'Should include MULTIPLE, BY_CONTENT, SEARCHTEXT');
end;

procedure TTestGeminiWcxExportedApi.GetBackgroundFlags_ReturnsBackgroundUnpack;
begin
	Assert.AreEqual<Integer>(BACKGROUND_UNPACK, GetBackgroundFlags);
end;

procedure TTestGeminiWcxExportedApi.CanYouHandleThisFileW_GeminiJson_ReturnsTrue;
var
	LPath: string;
begin
	LPath := CreateTempFile('valid.json', '{"runSettings":{"model":"models/gemini-2.0-flash"},"chunkedPrompt":{"chunks":[]}}');
	Assert.IsTrue(CanYouHandleThisFileW(PWideChar(LPath)));
end;

procedure TTestGeminiWcxExportedApi.CanYouHandleThisFileW_NonGeminiJson_ReturnsFalse;
var
	LPath: string;
begin
	// Generic JSON without Gemini markers should be rejected
	LPath := CreateTempFile('package.json', '{"name":"my-app","version":"1.0.0"}');
	Assert.IsFalse(CanYouHandleThisFileW(PWideChar(LPath)));
end;

procedure TTestGeminiWcxExportedApi.CanYouHandleThisFileW_NonJson_ReturnsFalse;
var
	LPath: string;
begin
	LPath := CreateTempFile('notjson.txt', 'This is not JSON');
	Assert.IsFalse(CanYouHandleThisFileW(PWideChar(LPath)));
end;

procedure TTestGeminiWcxExportedApi.CanYouHandleThisFileW_NonExistent_ReturnsFalse;
var
	LPath: string;
begin
	LPath := TPath.Combine(FTempDir, 'nonexistent_file');
	Assert.IsFalse(CanYouHandleThisFileW(PWideChar(LPath)));
end;

procedure TTestGeminiWcxExportedApi.CanYouHandleThisFileW_WithBom_ReturnsTrue;
var
	LPath: string;
	LBytes, LJson: TBytes;
begin
	// UTF-8 BOM (EF BB BF) followed by Gemini JSON
	LJson := TEncoding.UTF8.GetBytes('{"runSettings":{"model":"models/gemini-2.0-flash"}}');
	SetLength(LBytes, 3 + Length(LJson));
	LBytes[0] := $EF;
	LBytes[1] := $BB;
	LBytes[2] := $BF;
	if Length(LJson) > 0 then
		Move(LJson[0], LBytes[3], Length(LJson));
	LPath := CreateTempFileBytes('bom.json', LBytes);
	Assert.IsTrue(CanYouHandleThisFileW(PWideChar(LPath)));
end;

procedure TTestGeminiWcxExportedApi.CanYouHandleThisFileW_WithWhitespace_ReturnsTrue;
var
	LPath: string;
begin
	// Leading whitespace (tab, LF, CR, spaces) before Gemini JSON
	LPath := CreateTempFile('spaces.json', #9#10#13'  {"runSettings":{}}');
	Assert.IsTrue(CanYouHandleThisFileW(PWideChar(LPath)));
end;

procedure TTestGeminiWcxExportedApi.CanYouHandleThisFileW_EmptyFile_ReturnsFalse;
var
	LPath: string;
begin
	LPath := CreateTempFileBytes('empty.dat', nil);
	Assert.IsFalse(CanYouHandleThisFileW(PWideChar(LPath)));
end;

procedure TTestGeminiWcxExportedApi.OpenArchiveW_ValidFile_ReturnsHandle;
var
	LPath: string;
	LData: TOpenArchiveDataW;
	LHandle: THandle;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchiveW(LData);
	try
		Assert.IsTrue(LHandle <> 0, 'Handle should be non-zero');
		Assert.AreEqual<Integer>(0, LData.OpenResult);
	finally
		if LHandle <> 0 then
			CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxExportedApi.OpenArchiveW_NonExistentFile_SetsEOpen;
var
	LPath: string;
	LData: TOpenArchiveDataW;
	LHandle: THandle;
begin
	LPath := TPath.Combine(FTempDir, 'nonexistent_file');
	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchiveW(LData);
	Assert.IsTrue(LHandle = 0, 'Handle should be 0 on error');
	Assert.AreEqual<Integer>(E_EOPEN, LData.OpenResult);
end;

procedure TTestGeminiWcxExportedApi.OpenArchiveW_InvalidContent_SetsBadArchive;
var
	LPath: string;
	LData: TOpenArchiveDataW;
	LHandle: THandle;
begin
	LPath := CreateTempFile('invalid.dat', 'This is not valid JSON');
	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchiveW(LData);
	Assert.IsTrue(LHandle = 0, 'Handle should be 0 for invalid content');
	Assert.AreEqual<Integer>(E_BAD_ARCHIVE, LData.OpenResult);
end;

procedure TTestGeminiWcxExportedApi.CloseArchive_ValidHandle_ReturnsZero;
var
	LPath: string;
	LData: TOpenArchiveDataW;
	LHandle: THandle;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchiveW(LData);
	Assert.IsTrue(LHandle <> 0, 'Handle should be valid');
	Assert.AreEqual<Integer>(0, CloseArchive(LHandle));
end;

procedure TTestGeminiWcxExportedApi.CloseArchive_InvalidHandle_ReturnsBadArchive;
begin
	Assert.AreEqual<Integer>(E_BAD_ARCHIVE, CloseArchive(0));
end;

procedure TTestGeminiWcxExportedApi.ReadHeaderExW_InvalidHandle_ReturnsBadArchive;
var
	LHeader: THeaderDataExW;
begin
	Assert.AreEqual<Integer>(E_BAD_ARCHIVE, ReadHeaderExW(0, LHeader));
end;

procedure TTestGeminiWcxExportedApi.ProcessFileW_InvalidHandle_ReturnsBadArchive;
begin
	Assert.AreEqual<Integer>(E_BAD_ARCHIVE, ProcessFileW(0, PK_SKIP, nil, nil));
end;

procedure TTestGeminiWcxExportedApi.ProcessFileW_NilDestPath_UsesDestName;
var
	LPath, LOutFile: string;
	LData: TOpenArchiveDataW;
	LHeader: THeaderDataExW;
	LHandle: THandle;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_EXTRACT;
	LHandle := OpenArchiveW(LData);
	if LHandle = 0 then Exit;
	try
		Assert.AreEqual<Integer>(0, ReadHeaderExW(LHandle, LHeader));
		LOutFile := TPath.Combine(FTempDir, 'extracted.txt');
		// Pass nil for DestPath, valid path for DestName
		Assert.AreEqual<Integer>(0,
			ProcessFileW(LHandle, PK_EXTRACT, nil, PWideChar(LOutFile)));
		Assert.IsTrue(FileExists(LOutFile), 'Extracted file should exist');
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxExportedApi.ProcessFileW_DestPathOnly_CombinesEntryPath;
var
	LPath, LExpectedFile: string;
	LData: TOpenArchiveDataW;
	LHeader: THeaderDataExW;
	LHandle: THandle;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_EXTRACT;
	LHandle := OpenArchiveW(LData);
	if LHandle = 0 then Exit;
	try
		Assert.AreEqual<Integer>(0, ReadHeaderExW(LHandle, LHeader));
		// Pass DestPath only, nil for DestName -- combines path with entry name
		Assert.AreEqual<Integer>(0,
			ProcessFileW(LHandle, PK_EXTRACT, PWideChar(FTempDir), nil));
		LExpectedFile := TPath.Combine(FTempDir, 'Tailscale.txt');
		Assert.IsTrue(FileExists(LExpectedFile),
			'File should exist at combined path');
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxExportedApi.ProcessFileW_PkTest_ReturnsZero;
var
	LPath, LDummyDest: string;
	LData: TOpenArchiveDataW;
	LHeader: THeaderDataExW;
	LHandle: THandle;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_EXTRACT;
	LHandle := OpenArchiveW(LData);
	if LHandle = 0 then Exit;
	try
		Assert.AreEqual<Integer>(0, ReadHeaderExW(LHandle, LHeader));
		// PK_TEST requires a path (path validation happens before operation check)
		LDummyDest := TPath.Combine(FTempDir, 'test_dummy.txt');
		Assert.AreEqual<Integer>(0,
			ProcessFileW(LHandle, PK_TEST, nil, PWideChar(LDummyDest)));
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxExportedApi.SetChangeVolProcW_InvalidHandle_NoException;
begin
	// Should not crash with invalid handle
	SetChangeVolProcW(0, nil);
end;

procedure TTestGeminiWcxExportedApi.SetChangeVolProcW_ValidHandle_SetsCallback;
var
	LPath: string;
	LData: TOpenArchiveDataW;
	LHandle: THandle;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchiveW(LData);
	if LHandle = 0 then Exit;
	try
		// Should not crash and should set the callback on a valid handle
		SetChangeVolProcW(LHandle, nil);
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxExportedApi.CanYouHandleThisFileW_PartialBom_ReturnsFalse;
var
	LPath: string;
	LBytes: TBytes;
begin
	// File starts with $EF (like BOM start) but next bytes don't match $BB $BF
	// Covers the partial BOM rewind path
	SetLength(LBytes, 4);
	LBytes[0] := $EF;
	LBytes[1] := $00; // Not $BB
	LBytes[2] := $00;
	LBytes[3] := Ord('{');
	LPath := CreateTempFileBytes('partial_bom.dat', LBytes);
	// After BOM check fails, rewinds to 0 and reads $EF which is not '{'
	Assert.IsFalse(CanYouHandleThisFileW(PWideChar(LPath)));
end;

procedure TTestGeminiWcxExportedApi.ProcessCurrentFile_AfterExhaustion_ReturnsEndArchive;
var
	LPath: string;
	LData: TOpenArchiveDataW;
	LHeader: THeaderDataExW;
	LHandle: THandle;
	LResult: Integer;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchiveW(LData);
	if LHandle = 0 then Exit;
	try
		// Exhaust all entries
		while ReadHeaderExW(LHandle, LHeader) = 0 do
			ProcessFileW(LHandle, PK_SKIP, nil, nil);
		// Call ProcessFileW after exhaustion
		LResult := ProcessFileW(LHandle, PK_SKIP, nil, nil);
		Assert.AreEqual<Integer>(E_END_ARCHIVE, LResult,
			'Should return E_END_ARCHIVE when archive is exhausted');
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxExportedApi.SetProcessDataProcW_CallbackInvoked;
var
	LPath, LOutFile: string;
	LData: TOpenArchiveDataW;
	LHeader: THeaderDataExW;
	LHandle: THandle;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_EXTRACT;
	LHandle := OpenArchiveW(LData);
	if LHandle = 0 then Exit;
	try
		GProgressCallbackCalled := False;
		SetProcessDataProcW(LHandle, @TestProgressCallback);
		Assert.AreEqual<Integer>(0, ReadHeaderExW(LHandle, LHeader));
		LOutFile := TPath.Combine(FTempDir, 'callback_test.txt');
		ProcessFileW(LHandle, PK_EXTRACT, nil, PWideChar(LOutFile));
		Assert.IsTrue(GProgressCallbackCalled,
			'Progress callback should have been invoked');
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxExportedApi.ExportedApi_FullListLifecycle;
var
	LPath: string;
	LData: TOpenArchiveDataW;
	LHeader: THeaderDataExW;
	LHandle: THandle;
	LCount: Integer;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchiveW(LData);
	Assert.IsTrue(LHandle <> 0);
	try
		LCount := 0;
		while ReadHeaderExW(LHandle, LHeader) = 0 do
		begin
			Inc(LCount);
			ProcessFileW(LHandle, PK_SKIP, nil, nil);
		end;
		Assert.AreEqual<Integer>(3, LCount,
			'Tailscale should have 3 virtual files via exported API');
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxExportedApi.ProcessFileW_ExtractBothPathsNil_ReturnsECreate;
var
	LPath: string;
	LData: TOpenArchiveDataW;
	LHeader: THeaderDataExW;
	LHandle: THandle;
	LResult: Integer;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_EXTRACT;
	LHandle := OpenArchiveW(LData);
	if LHandle = 0 then Exit;
	try
		Assert.AreEqual<Integer>(0, ReadHeaderExW(LHandle, LHeader));
		// PK_EXTRACT with both paths nil -> E_ECREATE
		LResult := ProcessFileW(LHandle, PK_EXTRACT, nil, nil);
		Assert.AreEqual<Integer>(E_ECREATE, LResult,
			'Should return E_ECREATE when both paths are nil');
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxExportedApi.CanYouHandleThisFileW_WhitespaceOnly_ReturnsFalse;
var
	LPath: string;
begin
	// File with only whitespace and no opening brace
	LPath := CreateTempFile('whitespace_only.txt', '   '#13#10#9'  ');
	Assert.IsFalse(CanYouHandleThisFileW(PWideChar(LPath)),
		'Whitespace-only file should not be handled');
end;

procedure TTestGeminiWcxExportedApi.CanYouHandleThisFileW_BraceNoMarker_ReturnsFalse;
var
	LPath: string;
begin
	// Valid JSON opening brace but no 'runSettings' marker
	LPath := CreateTempFile('no_marker.json', '{"someOtherKey": "value"}');
	Assert.IsFalse(CanYouHandleThisFileW(PWideChar(LPath)),
		'JSON without runSettings should not be handled');
end;

procedure TTestGeminiWcxExportedApi.CanYouHandleThisFileW_ZeroBytesRead_ReturnsFalse;
var
	LPath: string;
begin
	// Single byte file: just the opening brace, no content after
	LPath := CreateTempFile('just_brace.txt', '{');
	Assert.IsFalse(CanYouHandleThisFileW(PWideChar(LPath)),
		'File with only a brace should not be handled');
end;

procedure TTestGeminiWcxExportedApi.OpenArchiveW_MalformedJson_SetsBadData;
var
	LPath: string;
	LData: TOpenArchiveDataW;
	LHandle: THandle;
begin
	// File that passes sniff check but fails JSON parse with a generic exception
	LPath := CreateTempFile('malformed.json',
		'{"runSettings": invalid json content here!!!}');
	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PWideChar(LPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchiveW(LData);
	Assert.AreEqual<THandle>(0, LHandle, 'Handle should be 0 for malformed file');
	// Should set OpenResult to E_BAD_DATA or E_BAD_ARCHIVE
	Assert.IsTrue(LData.OpenResult <> 0, 'OpenResult should be non-zero for malformed JSON');
end;

// ========================================================================
// TTestGeminiWcxAnsiCompat
// ========================================================================

function TTestGeminiWcxAnsiCompat.CreateTempFile(const AName, AContent: string): string;
begin
	Result := TPath.Combine(FTempDir, AName);
	TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

procedure TTestGeminiWcxAnsiCompat.Setup;
begin
	FTempDir := TPath.Combine(TPath.GetTempPath,
		'GemViewTest_Ansi_' + TGUID.NewGuid.ToString);
	ForceDirectories(FTempDir);
end;

procedure TTestGeminiWcxAnsiCompat.TearDown;
begin
	if TDirectory.Exists(FTempDir) then
		TDirectory.Delete(FTempDir, True);
end;

procedure TTestGeminiWcxAnsiCompat.OpenArchive_Ansi_ReturnsHandle;
var
	LPath: string;
	LAnsiPath: AnsiString;
	LData: TOpenArchiveData;
	LHandle: THandle;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	LAnsiPath := AnsiString(LPath);
	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PAnsiChar(LAnsiPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchive(LData);
	try
		Assert.IsTrue(LHandle <> 0, 'ANSI handle should be non-zero');
		Assert.AreEqual<Integer>(0, LData.OpenResult);
	finally
		if LHandle <> 0 then
			CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxAnsiCompat.ReadHeader_Ansi_PopulatesFields;
var
	LPath: string;
	LAnsiPath: AnsiString;
	LData: TOpenArchiveData;
	LHeader: THeaderData;
	LHandle: THandle;
	LFileName: AnsiString;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	LAnsiPath := AnsiString(LPath);
	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PAnsiChar(LAnsiPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchive(LData);
	if LHandle = 0 then Exit;
	try
		Assert.AreEqual<Integer>(0, ReadHeader(LHandle, LHeader));
		LFileName := AnsiString(LHeader.FileName);
		Assert.AreEqual(AnsiString('Tailscale.txt'), LFileName);
		Assert.IsTrue(LHeader.UnpSize > 0, 'UnpSize should be non-zero');
		Assert.IsTrue(LHeader.FileTime > 0, 'FileTime should be non-zero');
		ProcessFile(LHandle, PK_SKIP, nil, nil);
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxAnsiCompat.ReadHeaderEx_Ansi_PopulatesFields;
var
	LPath: string;
	LAnsiPath: AnsiString;
	LData: TOpenArchiveData;
	LHeader: THeaderDataEx;
	LHandle: THandle;
	LFileName: AnsiString;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	LAnsiPath := AnsiString(LPath);
	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PAnsiChar(LAnsiPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchive(LData);
	if LHandle = 0 then Exit;
	try
		Assert.AreEqual<Integer>(0, ReadHeaderEx(LHandle, LHeader));
		LFileName := AnsiString(LHeader.FileName);
		Assert.AreEqual(AnsiString('Tailscale.txt'), LFileName);
		Assert.IsTrue(LHeader.UnpSize > 0, 'UnpSize should be non-zero');
		ProcessFile(LHandle, PK_SKIP, nil, nil);
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxAnsiCompat.ProcessFile_Ansi_SkipWorks;
var
	LPath: string;
	LAnsiPath: AnsiString;
	LData: TOpenArchiveData;
	LHeader: THeaderData;
	LHandle: THandle;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	LAnsiPath := AnsiString(LPath);
	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PAnsiChar(LAnsiPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchive(LData);
	if LHandle = 0 then Exit;
	try
		Assert.AreEqual<Integer>(0, ReadHeader(LHandle, LHeader));
		Assert.AreEqual<Integer>(0, ProcessFile(LHandle, PK_SKIP, nil, nil));
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxAnsiCompat.ProcessFile_Ansi_ExtractWithPaths;
var
	LPath: string;
	LAnsiPath: AnsiString;
	LData: TOpenArchiveData;
	LHeader: THeaderData;
	LHandle: THandle;
	LAnsiDestPath, LAnsiDestName: AnsiString;
	LOutFile: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	LAnsiPath := AnsiString(LPath);
	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PAnsiChar(LAnsiPath);
	LData.OpenMode := PK_OM_EXTRACT;
	LHandle := OpenArchive(LData);
	if LHandle = 0 then Exit;
	try
		Assert.AreEqual<Integer>(0, ReadHeader(LHandle, LHeader));
		// Extract with both DestPath and DestName as ANSI strings
		LOutFile := TPath.Combine(FTempDir, 'ansi_extract.txt');
		LAnsiDestPath := AnsiString(FTempDir);
		LAnsiDestName := AnsiString(LOutFile);
		Assert.AreEqual<Integer>(0,
			ProcessFile(LHandle, PK_EXTRACT, PAnsiChar(LAnsiDestPath),
				PAnsiChar(LAnsiDestName)));
		Assert.IsTrue(FileExists(LOutFile), 'ANSI extracted file should exist');
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxAnsiCompat.CanYouHandleThisFile_Ansi_Works;
var
	LPath: string;
	LAnsiPath: AnsiString;
begin
	LPath := CreateTempFile('ansi_test.json', '{"runSettings":{}}');
	LAnsiPath := AnsiString(LPath);
	Assert.IsTrue(CanYouHandleThisFile(PAnsiChar(LAnsiPath)));
end;

procedure TTestGeminiWcxAnsiCompat.SetChangeVolProc_Ansi_NoOp;
begin
	// ANSI callback is a no-op, should not crash
	SetChangeVolProc(0, nil);
end;

procedure TTestGeminiWcxAnsiCompat.SetProcessDataProc_Ansi_NoOp;
begin
	// ANSI callback is a no-op, should not crash
	SetProcessDataProc(0, nil);
end;

procedure TTestGeminiWcxAnsiCompat.ProcessFile_Ansi_ExtractBothPathsNil_ReturnsECreate;
var
	LPath: string;
	LData: TOpenArchiveData;
	LHeader: THeaderData;
	LHandle: THandle;
	LAnsiPath: AnsiString;
	LResult: Integer;
begin
	LPath := CreateTempFile('ansi_ecreate.json',
		'{"runSettings":{},"chunkedPrompt":{"chunks":[{"text":"hi","role":"user"}]}}');
	LAnsiPath := AnsiString(LPath);

	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PAnsiChar(LAnsiPath);
	LData.OpenMode := PK_OM_EXTRACT;
	LHandle := OpenArchive(LData);
	if LHandle = 0 then Exit;
	try
		Assert.AreEqual<Integer>(0, ReadHeader(LHandle, LHeader));
		// PK_EXTRACT with both paths nil -> E_ECREATE
		LResult := ProcessFile(LHandle, PK_EXTRACT, nil, nil);
		Assert.AreEqual<Integer>(E_ECREATE, LResult,
			'ANSI extract with nil paths should return E_ECREATE');
	finally
		CloseArchive(LHandle);
	end;
end;

procedure TTestGeminiWcxAnsiCompat.OpenArchive_Ansi_NonExistent_SetsEOpen;
var
	LData: TOpenArchiveData;
	LAnsiPath: AnsiString;
	LHandle: THandle;
begin
	LAnsiPath := AnsiString('C:\nonexistent_file_12345.gemini');
	FillChar(LData, SizeOf(LData), 0);
	LData.ArcName := PAnsiChar(LAnsiPath);
	LData.OpenMode := PK_OM_LIST;
	LHandle := OpenArchive(LData);
	Assert.AreEqual<THandle>(0, LHandle, 'Handle should be 0 for non-existent file');
	Assert.AreEqual<Integer>(E_EOPEN, LData.OpenResult, 'Should set E_EOPEN');
end;

// ========================================================================
// TTestGeminiWcxExtractSpecial
// ========================================================================

procedure TTestGeminiWcxExtractSpecial.Setup;
begin
	FTempDir := TPath.Combine(TPath.GetTempPath,
		'GemViewTest_WcxSpecial_' + TGUID.NewGuid.ToString);
	ForceDirectories(FTempDir);
end;

procedure TTestGeminiWcxExtractSpecial.TearDown;
begin
	if TDirectory.Exists(FTempDir) then
		TDirectory.Delete(FTempDir, True);
end;

procedure TTestGeminiWcxExtractSpecial.ExtractEmbeddedHtml_ProducesContent;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutFile: string;
	LFileName: string;
	LContent: string;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
	try
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			if LFileName.EndsWith('_full.html') then
			begin
				LOutFile := TPath.Combine(FTempDir, 'full.html');
				Assert.AreEqual<Integer>(0,
					LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutFile));
				Assert.IsTrue(FileExists(LOutFile), 'Embedded HTML should exist');
				LContent := TFile.ReadAllText(LOutFile, TEncoding.UTF8);
				Assert.Contains(LContent, '<!DOCTYPE html>');
				// Embedded HTML should contain base64 data URIs
				Assert.Contains(LContent, 'data:image/jpeg;base64,');
				Exit;
			end;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		Assert.Fail('Embedded HTML entry not found');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxExtractSpecial.ExtractMarkdownFile_ProducesContent;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutFile: string;
	LFileName: string;
	LContent: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
	try
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			if LFileName.EndsWith('.md') then
			begin
				LOutFile := TPath.Combine(FTempDir, 'conversation.md');
				Assert.AreEqual<Integer>(0,
					LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutFile));
				Assert.IsTrue(FileExists(LOutFile), 'Markdown file should exist');
				LContent := TFile.ReadAllText(LOutFile, TEncoding.UTF8);
				Assert.Contains(LContent, '# Gemini Conversation');
				Exit;
			end;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		Assert.Fail('Markdown file entry not found');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxExtractSpecial.ExtractResourceDir_CreatesDirectory;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutDir: string;
	LFileName: string;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
	try
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			if LFileName = 'resources' then
			begin
				LOutDir := TPath.Combine(FTempDir, 'resources');
				Assert.AreEqual<Integer>(0,
					LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutDir));
				Assert.IsTrue(TDirectory.Exists(LOutDir),
					'Directory should be created');
				Exit;
			end;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		Assert.Fail('resources directory entry not found');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxExtractSpecial.ExtractEmbeddedHtml_IncludesCustomCSS;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutFile: string;
	LFileName: string;
	LContent: string;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
	try
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			if LFileName.EndsWith('_full.html') then
			begin
				LOutFile := TPath.Combine(FTempDir, 'css_test.html');
				Assert.AreEqual<Integer>(0,
					LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutFile));
				LContent := TFile.ReadAllText(LOutFile, TEncoding.UTF8);
				// Custom CSS from gemini.css should be embedded in the output
				Assert.Contains(LContent, '.gcv-coverage-test',
					'Embedded HTML should include custom CSS from gemini.css');
				Exit;
			end;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		Assert.Fail('Embedded HTML entry not found');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxExtractSpecial.ExtractTextToReadOnlyFile_ReturnsECreate;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutFile: string;
	LFileName: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then Exit;

	LOutFile := TPath.Combine(FTempDir, 'readonly.txt');
	TFile.WriteAllText(LOutFile, 'existing');
	TFile.SetAttributes(LOutFile, [TFileAttribute.faReadOnly]);
	try
		LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
		try
			while LArchive.ReadNextHeader(LHeader) = 0 do
			begin
				LFileName := LHeader.FileName;
				if LFileName.EndsWith('.txt') then
				begin
					// Extract over the read-only file -- should fail with E_ECREATE
					Assert.AreEqual<Integer>(E_ECREATE,
						LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutFile),
						'Should return E_ECREATE for read-only destination');
					Exit;
				end;
				LArchive.ProcessCurrentFile(PK_SKIP, '', '');
			end;
			Assert.Fail('Text file entry not found');
		finally
			LArchive.Free;
		end;
	finally
		TFile.SetAttributes(LOutFile, []);
	end;
end;

procedure TTestGeminiWcxExtractSpecial.ExtractEmbeddedHtmlToReadOnlyFile_ReturnsECreate;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutFile: string;
	LFileName: string;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then Exit;

	LOutFile := TPath.Combine(FTempDir, 'readonly.html');
	TFile.WriteAllText(LOutFile, 'existing');
	TFile.SetAttributes(LOutFile, [TFileAttribute.faReadOnly]);
	try
		LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
		try
			while LArchive.ReadNextHeader(LHeader) = 0 do
			begin
				LFileName := LHeader.FileName;
				if LFileName.EndsWith('_full.html') then
				begin
					// Extract over the read-only file -- should fail with E_ECREATE
					Assert.AreEqual<Integer>(E_ECREATE,
						LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutFile),
						'Should return E_ECREATE for read-only HTML destination');
					Exit;
				end;
				LArchive.ProcessCurrentFile(PK_SKIP, '', '');
			end;
			Assert.Fail('Embedded HTML entry not found');
		finally
			LArchive.Free;
		end;
	finally
		TFile.SetAttributes(LOutFile, []);
	end;
end;

procedure TTestGeminiWcxExtractSpecial.ExtractResourceToReadOnlyFile_ReturnsEWrite;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutFile: string;
	LFileName: string;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then Exit;

	LOutFile := TPath.Combine(FTempDir, 'readonly.jpg');
	TFile.WriteAllText(LOutFile, 'existing');
	TFile.SetAttributes(LOutFile, [TFileAttribute.faReadOnly]);
	try
		LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
		try
			while LArchive.ReadNextHeader(LHeader) = 0 do
			begin
				LFileName := LHeader.FileName;
				if LFileName.EndsWith('.jpg') then
				begin
					// Extract over the read-only file -- should fail with E_EWRITE
					Assert.AreEqual<Integer>(E_EWRITE,
						LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutFile),
						'Should return E_EWRITE for read-only resource destination');
					Exit;
				end;
				LArchive.ProcessCurrentFile(PK_SKIP, '', '');
			end;
			Assert.Fail('Resource file entry not found');
		finally
			LArchive.Free;
		end;
	finally
		TFile.SetAttributes(LOutFile, []);
	end;
end;

const
	/// INI content with all default values -- exercises the INI reading path
	/// without changing behavior for other tests
	TEST_INI_CONTENT =
		'[General]' + sLineBreak +
		'UseOriginalName=1' + sLineBreak +
		sLineBreak +
		'[Formatters]' + sLineBreak +
		'EnableText=1' + sLineBreak +
		'EnableMarkdown=1' + sLineBreak +
		'EnableHtml=1' + sLineBreak +
		'EnableHtmlEmbedded=1' + sLineBreak +
		'HideEmptyBlocksText=1' + sLineBreak +
		'HideEmptyBlocksMd=1' + sLineBreak +
		'HideEmptyBlocksHtml=1' + sLineBreak +
		'CombineBlocksText=0' + sLineBreak +
		'CombineBlocksMd=0' + sLineBreak +
		'CombineBlocksHtml=0' + sLineBreak +
		sLineBreak +
		'[HtmlDefaults]' + sLineBreak +
		'DefaultFullWidth=0' + sLineBreak +
		'DefaultExpandThinking=0' + sLineBreak +
		'RenderMarkdown=1';

	/// CSS content with identifiable marker for custom CSS loading test
	TEST_CSS_CONTENT = '.gcv-coverage-test { display: none; }';

var
	GTestExeDir: string;

initialization
	// Place INI and CSS config files next to the test executable so that
	// GetPluginConfig and GetCustomCSS find and read them (HInstance points
	// to the test exe, so GetModuleFileName returns its directory).
	GTestExeDir := TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)));
	TFile.WriteAllText(TPath.Combine(GTestExeDir, 'gemini.ini'),
		TEST_INI_CONTENT, TEncoding.UTF8);
	TFile.WriteAllText(TPath.Combine(GTestExeDir, 'gemini.css'),
		TEST_CSS_CONTENT, TEncoding.UTF8);

	TDUnitX.RegisterTestFixture(TTestGeminiWcxVirtualFileList);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxReadHeader);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxProcessFile);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxProcessHtml);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxGetBaseName);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxPluginConfig);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxExportedApi);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxAnsiCompat);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxExtractSpecial);

finalization
	// Clean up test config files
	if (GTestExeDir <> '') and TFile.Exists(TPath.Combine(GTestExeDir, 'gemini.ini')) then
		TFile.Delete(TPath.Combine(GTestExeDir, 'gemini.ini'));
	if (GTestExeDir <> '') and TFile.Exists(TPath.Combine(GTestExeDir, 'gemini.css')) then
		TFile.Delete(TPath.Combine(GTestExeDir, 'gemini.css'));

end.