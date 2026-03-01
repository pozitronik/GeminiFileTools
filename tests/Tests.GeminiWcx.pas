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
	private
		function ExamplesDir: string;
		function FindExample(const AName: string): string;
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
	end;

	[TestFixture]
	TTestGeminiWcxReadHeader = class
	private
		function ExamplesDir: string;
		function FindExample(const AName: string): string;
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
	private
		function ExamplesDir: string;
		function FindExample(const AName: string): string;
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
		function ExamplesDir: string;
		function FindExample(const AName: string): string;
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
	end;

implementation

// Shared helpers for finding example files

function TTestGeminiWcxVirtualFileList.ExamplesDir: string;
begin
	Result := TPath.Combine(
		TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
			TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
		'examples');
	if not TDirectory.Exists(Result) then
		Result := TPath.GetFullPath('..\examples');
end;

function TTestGeminiWcxVirtualFileList.FindExample(const AName: string): string;
begin
	Result := TPath.Combine(ExamplesDir, AName);
	if not FileExists(Result) then
		Result := '';
end;

function TTestGeminiWcxReadHeader.ExamplesDir: string;
begin
	Result := TPath.Combine(
		TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
			TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
		'examples');
	if not TDirectory.Exists(Result) then
		Result := TPath.GetFullPath('..\examples');
end;

function TTestGeminiWcxReadHeader.FindExample(const AName: string): string;
begin
	Result := TPath.Combine(ExamplesDir, AName);
	if not FileExists(Result) then
		Result := '';
end;

function TTestGeminiWcxProcessFile.ExamplesDir: string;
begin
	Result := TPath.Combine(
		TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
			TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
		'examples');
	if not TDirectory.Exists(Result) then
		Result := TPath.GetFullPath('..\examples');
end;

function TTestGeminiWcxProcessFile.FindExample(const AName: string): string;
begin
	Result := TPath.Combine(ExamplesDir, AName);
	if not FileExists(Result) then
		Result := '';
end;

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
		Assert.Contains(LContent, '=== Gemini Conversation ===');
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

function TTestGeminiWcxProcessHtml.ExamplesDir: string;
begin
	Result := TPath.Combine(
		TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
			TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
		'examples');
	if not TDirectory.Exists(Result) then
		Result := TPath.GetFullPath('..\examples');
end;

function TTestGeminiWcxProcessHtml.FindExample(const AName: string): string;
begin
	Result := TPath.Combine(ExamplesDir, AName);
	if not FileExists(Result) then
		Result := '';
end;

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

initialization
	TDUnitX.RegisterTestFixture(TTestGeminiWcxVirtualFileList);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxReadHeader);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxProcessFile);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxProcessHtml);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxGetBaseName);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxPluginConfig);

end.
